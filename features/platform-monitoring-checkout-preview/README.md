# Monitoramento de plataforma e preview de checkout

## Estado

- Desenvolvimento local na branch `feat/service-monitoring-checkout-preview`.
- Implantação em homologação deliberadamente pendente.
- O `services-platform` existente continua sendo a origem das métricas e dos backups.

## Decisões por etapa

### 1. Limites e fluxo entre aplicações

O dashboard não acessa serviços internos diretamente. O caminho das consultas de infraestrutura é:

`dashboard-seller -> edge-gateway -> edge-public-api -> services-platform`

- `edge-gateway` preserva o JWT e encaminha as rotas.
- `edge-public-api` valida JWT e permissão administrativa.
- Somente o `edge-public-api` conhece o segredo usado para assinar chamadas ao `services-platform`.
- A assinatura HMAC usa método, caminho e timestamp, com janela curta contra replay.

### 2. Coleta e histórico

- A coleta persistida permanece a cada 3 minutos.
- A retenção é de 45 dias, com exclusão em lotes, para preservar a janela necessária aos relatórios.
- Cada amostra contém disco, memória, inodes, load de 1/5/15 minutos e quantidade de vCPUs.
- O load é mostrado também como percentual da capacidade: `load de 1 minuto / vCPUs`.
- O endpoint histórico agrega no servidor para não enviar todas as amostras ao navegador:
  - 24 horas: buckets de 15 minutos;
  - 7 dias: buckets de 1 hora;
  - 30 dias: buckets de 6 horas.
- O histórico retorna média, mínimo e máximo necessários para dar contexto ao load.

### 3. Modo ao vivo

- O modo ao vivo é ativado somente por requisição HTTP.
- Enquanto o modal estiver aberto, o dashboard consulta a cada 5 segundos e renova a concessão a cada 30 segundos.
- A concessão expira em 1 minuto sem renovação.
- As amostras rápidas ficam somente no Redis exclusivo do `services-platform` e não entram no histórico SQL.
- O polling para quando o modal fecha ou a página fica oculta; ao voltar, a concessão é reativada.

### 4. Alertas internos

O fluxo escolhido é:

`services-platform -> services-notification -> notificação interna`

- Não há envio de e-mail nesta entrega.
- O `services-platform` mantém uma outbox para não perder alertas durante indisponibilidade temporária.
- A rota do `services-notification` aceita somente assinatura interna válida e templates de plataforma permitidos.
- Os destinatários são forçados para administradores; o chamador não pode escolher alvos arbitrários.
- Alertas implementados:
  - disco em 80% (warning) e 90% (critical), com cooldown de 6 horas;
  - escalada de warning para critical sem esperar o cooldown;
  - normalização do disco;
  - falha no dump ou atraso no envio ao R2 após três tentativas;
  - recuperação do backup após envio bem-sucedido.
- Memória e inodes permanecem somente no histórico.
- A outbox tenta até 10 vezes e então marca a entrega como falha, evitando retry infinito.

### 5. Backup e R2

- Um único dump MariaDB inclui todos os bancos configurados em `BACKUP_MARIADB_DATABASES`.
- Os horários continuam configuráveis por `BACKUP_SCHEDULE`, aceitando mais de um horário.
- O upload não possui horário próprio: um job é criado assim que o dump local fica pronto.
- Após upload válido, o serviço mantém apenas a quantidade mínima de cópias locais configurada.
- O dashboard mostra horário, alvo, status, tamanho, duração e chave no storage.

### 6. Interface administrativa

- Foi criada uma página separada chamada “Infraestrutura”.
- A página reutiliza os componentes-base de `dashboard-seller/views/components/`:
  - `PageHeader` e `Button`;
  - `StatCardGrid` e `StatCard`;
  - `ContentBox`;
  - `Table` e `TableColumn`;
  - `Modal`.
- A permissão reaproveitada é `admin_service_status`.
- O gráfico apresenta disco, memória, inodes e load normalizado.
- O card de load apresenta valor atual, vCPUs, percentual de capacidade e médias de 5/15 minutos.
- O histórico explicita mínimo e máximo do load no período.

### 7. Autorização do preview

- Não foi criado um novo tipo de token: o JWT já utilizado pelo Dashboard Seller é reutilizado.
- O dashboard copia temporariamente o JWT atual para um cookie `HttpOnly`, `Secure` e `SameSite=Lax`, com duração de 5 minutos e domínio configurável para o host compartilhado do checkout.
- A flag `editor_preview=1` representa somente a intenção de abrir a prévia.
- O `front-checkout` encaminha o JWT somente na consulta de contexto de preview.
- O `edge-public-api` valida o JWT existente e rejeita colaboradores nesse fluxo.
- O Public API propaga internamente o ID do usuário por uma chamada assinada ao Commerce V2.
- O Commerce V2 libera o bypass de elegibilidade somente quando o usuário autenticado é o proprietário do produto.
- Sem JWT, com JWT expirado, assinatura interna inválida ou propriedade divergente, a prévia retorna erro.
- O contexto autenticado devolve `editor_preview=true`; o frontend não confia apenas na query string.
- No preview, formulário, pixels, notificações de venda e fluxos de saída são desativados.
- Requisições de pagamento marcadas como preview são recusadas também no backend.

## Contratos HTTP

Rotas externas autenticadas, expostas pelo Gateway e Public API:

- `GET /admin/platform/overview`
- `GET /admin/platform/metrics?range=24h|7d|30d`
- `GET /admin/platform/backups?page=1`
- `POST /admin/platform/live/activate`
- `GET /admin/platform/live`

Rotas internas equivalentes do `services-platform` usam o prefixo `/platform`.

## Variáveis novas ou alteradas

### edge-public-api

- `INTERNAL_HTTP_PLATFORM_URL`
- `PLATFORM_SERVICE_SIGNATURE_SECRET`
- `PLATFORM_SERVICE_TIMEOUT_SECONDS`
- `COMMERCE_PREVIEW_SIGNATURE_SECRET`

### services-platform

- `PLATFORM_SIGNATURE_SECRET`: mesmo valor de `PLATFORM_SERVICE_SIGNATURE_SECRET` no Public API.
- `PLATFORM_BACKUP_ALERT_COOLDOWN_SECONDS=21600`
- `PLATFORM_NOTIFICATION_URL`
- `PLATFORM_NOTIFICATION_SECRET`
- `PLATFORM_NOTIFICATIONS_ENABLED`

### services-notification

- `INTERNAL_PLATFORM_NOTIFICATION_SECRET`: mesmo valor de `PLATFORM_NOTIFICATION_SECRET` no Platform.

### services-commerce-v2

- `COMMERCE_PREVIEW_SIGNATURE_SECRET`: mesmo valor configurado no Public API.
- `COMMERCE_PREVIEW_SIGNATURE_MAX_AGE_SECONDS=60`

### dashboard-seller

- `CHECKOUT_PREVIEW_COOKIE_NAME=checkout_preview_jwt`
- `CHECKOUT_PREVIEW_COOKIE_DOMAIN`: domínio compartilhado entre dashboard e checkout.
- `CHECKOUT_PREVIEW_COOKIE_SECURE=true`

### front-checkout

- `CHECKOUT_PREVIEW_COOKIE_NAME=checkout_preview_jwt`

## Banco de dados

- `services-platform`: migration adiciona `cpu_cores` em `host_metric_snapshots`.
- `services-notification`: migration adiciona os quatro templates internos de plataforma.

## Validação executada

- Sintaxe PHP validada em todos os arquivos alterados.
- Rotas de plataforma e preview conferidas no Laravel.
- Testes unitários do `edge-public-api`: 11 testes e 21 assertions.
- Imagem Docker do `services-platform` construída com sucesso.
- Container isolado da imagem iniciou o console Hyperf e resolveu as dependências.
- O comando de testes completo do `edge-public-api` continua com uma limitação anterior: o `phpunit.xml` referencia o diretório ausente `tests/Feature`; os testes de unidade foram executados diretamente.
- Os testes do Commerce V2 não executam nesta máquina porque o binário `co-phpunit` não está instalado no repositório local.

## Implantação pendente em homologação

1. Configurar segredos iguais nos dois lados de cada comunicação assinada.
2. Configurar URL interna do `services-platform` no Public API.
3. Confirmar o domínio compartilhado do cookie de preview.
4. Executar migrations de `services-platform` e `services-notification`.
5. Publicar `services-notification`, `services-platform`, `services-commerce-v2`, `edge-public-api`, `edge-gateway`, `front-checkout` e `dashboard-seller`.
6. Validar histórico, live mode, criação de alertas, backup/R2 e preview com proprietário/não proprietário.
