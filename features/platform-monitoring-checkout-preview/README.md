# Monitoramento de plataforma e preview de checkout

## Estado

- Desenvolvimento na branch `feat/service-monitoring-checkout-preview`.
- Implantação validada em homologação; produção pendente conforme o documento de deploy vinculado ao final deste mapa.
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

- O `dashboard-seller` autoriza a prévia por uma chamada backend feita com `GatewayJwtClient`, reutilizando o JWT e o `refresh_token` do fluxo autenticado existente.
- O Public API valida o JWT, rejeita colaboradores e encaminha o ID do usuário ao Commerce V2 pela comunicação interna normal entre esses serviços.
- O Commerce V2 confirma que o `short_code` pertence ao usuário e somente então emite uma autorização aleatória, restrita ao produto, registrada no Redis e válida por 5 minutos.
- A autorização de prévia é emitida e validada pelo Commerce V2, não contém o JWT nem o `refresh_token` e não exige cookie compartilhado entre dashboard e checkout.
- A flag `editor_preview=1` representa somente a intenção de abrir a prévia.
- O `front-checkout` encaminha somente a autorização curta na consulta de contexto da prévia.
- O Commerce V2 libera o bypass de elegibilidade somente quando a autorização temporária é válida para o proprietário daquele produto.
- Sem autorização válida ou com propriedade divergente, a prévia retorna erro.
- O contexto autenticado devolve `editor_preview=true`; o frontend não confia apenas na query string.
- No preview, o formulário e os meios de pagamento são exibidos apenas visualmente e ficam sem interação ou envio; pixels, notificações de venda e fluxos de saída são desativados.
- Requisições de pagamento marcadas como preview são recusadas também no backend.

## Contratos HTTP

Rotas externas envolvidas, expostas pelo Gateway e Public API:

- `GET /admin/platform/overview`
- `GET /admin/platform/metrics?range=24h|7d|30d`
- `GET /admin/platform/backups?page=1`
- `POST /admin/platform/live/activate`
- `GET /admin/platform/live`
- `POST /checkout/preview/session`: exige JWT e cria uma autorização de prévia de 5 minutos após validar a propriedade.
- `GET /checkout/context/{short_code}`: permanece público no checkout normal e exige a autorização curta quando `editor_preview=1`.

Rotas internas equivalentes do `services-platform` usam o prefixo `/platform`.

## Variáveis novas ou alteradas

### edge-public-api

- `INTERNAL_HTTP_PLATFORM_URL`
- `PLATFORM_SERVICE_SIGNATURE_SECRET`
- `PLATFORM_SERVICE_TIMEOUT_SECONDS`

### services-platform

- `PLATFORM_SIGNATURE_SECRET`: mesmo valor de `PLATFORM_SERVICE_SIGNATURE_SECRET` no Public API.
- `PLATFORM_BACKUP_ALERT_COOLDOWN_SECONDS=21600`
- `PLATFORM_NOTIFICATION_URL`
- `PLATFORM_NOTIFICATION_SECRET`
- `PLATFORM_NOTIFICATIONS_ENABLED`

### services-notification

- `INTERNAL_PLATFORM_NOTIFICATION_SECRET`: mesmo valor de `PLATFORM_NOTIFICATION_SECRET` no Platform.

### services-commerce-v2

- `COMMERCE_PREVIEW_TOKEN_TTL_SECONDS=300`

O fluxo de prévia não adiciona segredos nem variáveis de ambiente no `dashboard-seller`, `front-checkout` ou `edge-public-api`. O token opaco é registrado no Redis já usado pelo Commerce V2 com `short_code`, ID do produto, proprietário e expiração; a chave expira automaticamente. A chamada interna do Public API usa a comunicação normal já existente com o Commerce V2.

## Banco de dados

- `services-platform`: migration adiciona `cpu_cores` em `host_metric_snapshots`.
- `services-notification`: migration adiciona os quatro templates internos de plataforma.

## Validação executada

- Sintaxe PHP validada em todos os arquivos alterados.
- Rotas de plataforma e preview conferidas no Laravel.
- Testes unitários do `edge-public-api`: 8 testes e 16 assertions.
- O teste do emissor/validador de preview do Commerce V2 cobre produto correto, produto divergente e token inexistente no Redis.
- Imagem Docker do `services-platform` construída com sucesso.
- Container isolado da imagem iniciou o console Hyperf e resolveu as dependências.
- O comando de testes completo do `edge-public-api` continua com uma limitação anterior: o `phpunit.xml` referencia o diretório ausente `tests/Feature`; os testes de unidade foram executados diretamente.
- A suíte PHPUnit do Commerce V2 não executa nesta máquina porque o binário `co-phpunit` não está instalado no repositório local.

## Implantação em homologação

Executada em 15 de outubro de 2026 na branch `feat/service-monitoring-checkout-preview`:

- `dashboard-seller` e `front-checkout` foram atualizados somente por Git, sem rebuild.
- `edge-gateway`, `edge-public-api`, `services-commerce-v2`, `services-notification` e `services-platform` foram reconstruídos por Docker Compose.
- As migrations de `services-notification` e `services-platform` foram aplicadas.
- O Public API e o Platform receberam o mesmo segredo de assinatura; Platform e Notifications receberam outro segredo compartilhado entre eles.
- O clone do `services-platform` na VPS teve o refspec normalizado para rastrear branches além de `main`.
- Durante a validação, as rotas do Platform foram corrigidas para callables compatíveis com Hyperf, os responses passaram a ser injetados pelo contrato HTTP no construtor e o histórico de load passou a usar a contagem conhecida de vCPUs em amostras antigas. O commit final publicado do Platform é `c444005`.
- A rota do Platform retornou `401` sem assinatura e `200` com assinatura válida e contrato JSON.
- A rota do Notifications aceitou a assinatura interna e retornou `422` para um payload vazio de teste, sem criar notificação.
- A coleta histórica continuou produzindo métricas após o deploy.

Permanecem como validação funcional de produção: modo ao vivo pelo Dashboard, criação real de alerta e preview com proprietário e não proprietário. Backup e R2 estão deliberadamente fora da primeira publicação.

## Deploy de produção

- [Deploy — Monitoramento de plataforma e prévia autorizada do checkout](../../deploys/2026-10-15-platform-monitoring-checkout-preview/2026-10-15_PLATFORM_MONITORING_CHECKOUT_PREVIEW_DEPLOY.md)
- Na primeira publicação, o Platform será ativado somente para monitoramento e notificações internas; backup e R2 permanecerão desabilitados e sem credenciais.
