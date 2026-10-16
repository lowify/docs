# Deploy — Monitoramento de plataforma e prévia autorizada do checkout

## Objetivo

Publicar em produção duas entregas da branch `feat/service-monitoring-checkout-preview`:

1. monitoramento do host no Dashboard, com histórico de 45 dias, modo ao vivo e alertas internos de disco;
2. prévia autorizada do checkout para o proprietário do produto, inclusive quando o produto não estiver disponível para compra.

O novo `services-platform` será instalado em `/opt/services/services-platform` e entrará nesta etapa **somente para monitoramento**. Backup de bancos, dump local e Cloudflare R2 ficam desativados. Não cadastrar credenciais de banco para backup nem credenciais de storage.

O fluxo de monitoramento será:

`dashboard-seller -> edge-gateway -> edge-public-api -> services-platform`

O fluxo de alerta será:

`services-platform -> services-notifications -> notificação interna para administradores`

O fluxo da prévia será:

`dashboard-seller -> edge-gateway -> edge-public-api -> services-commerce-v2 -> Redis do Commerce V2 -> front-checkout`

## Componentes e referências

Todos os repositórios existentes devem estar sem alterações locais antes do deploy. A revisão curta deve coincidir com a tabela depois do `pull`.

| Repositório | Diretório em produção | Branch | Commit | Ação |
| --- | --- | --- | --- | --- |
| `services-notification` | `/opt/lowify/services/services-notifications` | `feat/service-monitoring-checkout-preview` | `ebda9ff` | Configurar segredo, rebuild e migration |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/service-monitoring-checkout-preview` | `ee32f47` | Configurar TTL e rebuild |
| `services-platform` | `/opt/services/services-platform` | `feat/service-monitoring-checkout-preview` | `d6962db` | Clone novo, configuração, rebuild e migrations |
| `edge-public-api` | `/opt/lowify/edge/edge-public-api` | `feat/service-monitoring-checkout-preview` | `59b1860` | Configurar comunicação e rebuild |
| `edge-gateway` | `/opt/lowify/edge/edge-gateway` | `feat/service-monitoring-checkout-preview` | `f8d2956` | Rebuild |
| `front-checkout` | `/opt/lowify/front/front-checkout` | `feat/service-monitoring-checkout-preview` | `a2e205b` | Somente atualização Git |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `feat/service-monitoring-checkout-preview` | `fc8b0188` | Somente atualização Git |

O deploy é incremental e restrito a esses sete componentes. Não sincronizar nem reconstruir outros repositórios como efeito colateral.

## Alterações incluídas

### Monitoramento

- Coleta persistida de disco, memória, inodes, load de 1/5/15 minutos e quantidade de vCPUs a cada 3 minutos.
- Histórico retido por 45 dias e agregado no backend para consultas de 24 horas, 7 dias e 30 dias.
- Modo ao vivo ativado sob demanda pelo Dashboard, com amostras a cada 5 segundos mantidas somente no Redis exclusivo do Platform.
- Gráfico atualizado sem remontagem, preservando as séries ocultadas pelo usuário.
- Load normalizado pela quantidade de vCPUs, inclusive para amostras históricas anteriores sem `cpu_cores`.
- Alerta interno de disco em 80% e 90%, recuperação e cooldown de 6 horas.
- Página **Infraestrutura** protegida pela permissão `admin_service_status`, disponível para perfis 1, 2 e 4.

### Prévia do checkout

- O Dashboard usa o JWT existente para solicitar a autorização da prévia.
- O Public API extrai a identidade do JWT e rejeita colaboradores.
- O Commerce V2 confirma que o produto pertence ao usuário e grava no Redis um token opaco, vinculado ao produto e válido por 5 minutos.
- O Checkout aceita o token opaco e libera somente a renderização da prévia autorizada.
- O formulário e os meios de pagamento aparecem visualmente, mas ficam sem interação e sem envio.
- Pixels, reCAPTCHA, antifraude, notificações de venda, pagamentos e redirecionamentos comerciais não são executados na prévia.
- Não há cookie novo nem segredo adicional para a prévia; o token temporário permanece no Redis já usado pelo Commerce V2.

## Pré-requisitos

1. Gerar dois segredos aleatórios fortes e independentes no gerenciador de segredos da operação:

   - **segredo A — Public API/Platform**: exatamente 64 caracteres hexadecimais minúsculos (`[0-9a-f]`), com o mesmo valor em `PLATFORM_SERVICE_SIGNATURE_SECRET` no Public API e `PLATFORM_SIGNATURE_SECRET` no Platform;
   - **segredo B — Platform/Notifications**: exatamente 64 caracteres hexadecimais minúsculos (`[0-9a-f]`), com o mesmo valor em `PLATFORM_NOTIFICATION_SECRET` no Platform e `INTERNAL_PLATFORM_NOTIFICATION_SECRET` no Notifications.

   Não reutilizar JWT secret, senha de banco ou o mesmo valor nos dois pares. Não registrar os valores neste documento, em commit, ticket, histórico do shell ou evidência de deploy.

   Em uma sessão privada, cada segredo de comunicação pode ser gerado individualmente com:

   ```bash
   openssl rand -hex 32
   ```

2. Gerar senhas próprias e fortes para `DB_PASSWORD`, `PLATFORM_MARIADB_ROOT_PASSWORD` e `REDIS_AUTH`. Cada uma deve ter exatamente 48 caracteres aleatórios do conjunto `A-Z`, `a-z`, `0-9`, `_` e `-`. Elas protegem somente os componentes locais do Platform e não devem ser iguais entre si nem compartilhadas com outros serviços.

   Cada senha pode ser gerada individualmente com:

   ```bash
   openssl rand -base64 36 | tr '+/' '-_'
   ```
## Espaço em disco

Reservar pelo menos **5 GB livres** no filesystem usado pelo Docker antes da instalação; **10 GB livres** é a margem recomendada para acomodar build, cache e logs sem pressão no host.

Como referência da homologação, as três imagens necessárias ocupam aproximadamente 1,1 GB (`services-platform`, MariaDB e Redis), e os três volumes exclusivos começaram em aproximadamente 203 MB após horas de coleta. O histórico de 45 dias tende a crescer pouco, pois guarda somente métricas agregáveis, mas logs e cache de build do Docker justificam a margem adicional.

Não há consumo de dumps ou de R2 nesta etapa: `BACKUP_ENABLED=false` impede a criação de arquivos de backup.

## Variáveis de ambiente

### `services-platform` — `/opt/services/services-platform/.env`

O arquivo `services-platform/.env.production.example` é a fonte única das variáveis do novo serviço. Copiá-lo para `.env` e alterar somente os cinco placeholders `REPLACE_ME`:

- `DB_PASSWORD`, `PLATFORM_MARIADB_ROOT_PASSWORD` e `REDIS_AUTH`: 48 caracteres aleatórios em `[A-Za-z0-9_-]`, todos diferentes entre si;
- `PLATFORM_SIGNATURE_SECRET`: segredo A, com 64 caracteres `[0-9a-f]`;
- `PLATFORM_NOTIFICATION_SECRET`: segredo B, também com 64 caracteres `[0-9a-f]` e diferente do segredo A.

As demais variáveis devem permanecer exatamente como estão no template, incluindo `BACKUP_ENABLED=false`, R2 sem credenciais, retenção de 45 dias, porta `9515` e a URL interna de Notifications.

### Variáveis a adicionar ou alterar nos serviços existentes

- Em `edge-public-api/.env`: `PLATFORM_SERVICE_SIGNATURE_SECRET` com o segredo A.
- Em `services-notifications/.env`: `INTERNAL_PLATFORM_NOTIFICATION_SECRET` com o segredo B.

Não há variável nova em `edge-gateway`, `front-checkout` ou `dashboard-seller`.

## Banco de dados

### Platform

Como a instalação é nova, aplicar as três migrations no banco `operations` local do container:

| Migration | Efeito |
| --- | --- |
| `2026_10_14_000001_create_platform_tables.php` | Cria métricas, execuções de backup, incidentes e outbox de notificações |
| `2026_10_15_000002_add_backup_queue.php` | Cria a fila durável de upload; permanecerá inativa com backup desligado |
| `2026_10_15_000003_add_cpu_cores_to_host_metrics.php` | Registra vCPUs para normalizar o load |

Embora as tabelas de backup sejam criadas, nenhuma rotina de backup será ativada e nenhum storage será configurado.

### Notifications

Aplicar `2026_10_15_000062_seed_platform_in_app_templates.php`. A migration adiciona os templates internos de alerta de disco e também templates de backup. Os templates de backup permanecerão sem uso enquanto `BACKUP_ENABLED=false`.

Commerce V2, Public API, Gateway, Front Checkout e Dashboard não possuem migration nesta entrega.

## Sequência de deploy

### 1. Publicar Notifications e aplicar o template

Editar o `.env` com o segredo B antes do rebuild, sem imprimir o valor:

```bash
cd /opt/lowify/services/services-notifications
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD
docker compose up -d --build
docker compose exec -T services-notifications php bin/hyperf.php migrate --force --path=migrations/2026_10_15_000062_seed_platform_in_app_templates.php
docker compose exec -T services-notifications php bin/hyperf.php migrate:status
docker compose ps
docker compose logs --tail=100 services-notifications
```

O commit deve ser `ebda9ff`. Não continuar se a migration ou o container falhar.

### 2. Publicar Commerce V2

```bash
cd /opt/lowify/services/service-commerce-v2
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

O commit deve ser `ee32f47`.

### 3. Instalar o novo `services-platform`

O diretório `/opt/services` já existe. O subdiretório `/opt/services/services-platform` não deve existir antes do primeiro clone; se existir, interromper e identificar seu conteúdo; não apagar nem sobrescrever.

```bash
cd /opt/services
git clone --branch feat/service-monitoring-checkout-preview git@github.com:lowify/services-platform.git services-platform
cd /opt/services/services-platform
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD
cp .env.production.example .env
chmod 600 .env
```

O commit deve ser `d6962db`. Editar o `.env` conforme a tabela deste documento antes de continuar. Antes de criar volumes ou containers, confirmar que nenhum placeholder permaneceu:

```bash
cd /opt/services/services-platform
if grep -q 'REPLACE_ME' .env; then
  echo 'ERRO: substitua todos os placeholders REPLACE_ME do .env.' >&2
  exit 1
fi

platform_db_password=$(sed -n 's/^DB_PASSWORD=//p' .env)
platform_db_root_password=$(sed -n 's/^PLATFORM_MARIADB_ROOT_PASSWORD=//p' .env)
platform_redis_password=$(sed -n 's/^REDIS_AUTH=//p' .env)
platform_api_secret=$(sed -n 's/^PLATFORM_SIGNATURE_SECRET=//p' .env)
platform_notification_secret=$(sed -n 's/^PLATFORM_NOTIFICATION_SECRET=//p' .env)

[[ $platform_db_password =~ ^[A-Za-z0-9_-]{48}$ ]] || exit 1
[[ $platform_db_root_password =~ ^[A-Za-z0-9_-]{48}$ ]] || exit 1
[[ $platform_redis_password =~ ^[A-Za-z0-9_-]{48}$ ]] || exit 1
[[ $platform_db_password != "$platform_db_root_password" ]] || exit 1
[[ $platform_db_password != "$platform_redis_password" ]] || exit 1
[[ $platform_db_root_password != "$platform_redis_password" ]] || exit 1
[[ $platform_api_secret =~ ^[0-9a-f]{64}$ ]] || exit 1
[[ $platform_notification_secret =~ ^[0-9a-f]{64}$ ]] || exit 1
[[ $platform_api_secret != "$platform_notification_secret" ]] || exit 1

unset platform_db_password platform_db_root_password platform_redis_password platform_api_secret platform_notification_secret
```

Criar somente os volumes exclusivos declarados pelo Compose. A rede `data_net` já é a rede compartilhada do projeto:

```bash
docker volume inspect services-operations_operations_runtime >/dev/null 2>&1 || docker volume create services-operations_operations_runtime
docker volume inspect services-operations_operations_mariadb_data >/dev/null 2>&1 || docker volume create services-operations_operations_mariadb_data
docker volume inspect services-operations_operations_redis_data >/dev/null 2>&1 || docker volume create services-operations_operations_redis_data
```

Subir o serviço, aplicar todas as migrations e conferir o estado:

```bash
cd /opt/services/services-platform
docker compose up -d --build
docker compose exec -T services-platform php bin/hyperf.php migrate --force
docker compose exec -T services-platform php bin/hyperf.php migrate:status
docker compose ps
docker compose logs --tail=100 services-platform
curl --fail --silent --show-error http://127.0.0.1:9515/health
```

O health check deve retornar `{"status":"ok"}`. Confirmar nos logs que a coleta não apresenta erro de tabela, MariaDB ou Redis. Não cadastrar variáveis `R2_*` nem `BACKUP_MARIADB_*` depois dessa etapa.

### 4. Publicar o Public API

Editar no `.env` somente `PLATFORM_SERVICE_SIGNATURE_SECRET` com o segredo A antes do rebuild:

```bash
cd /opt/lowify/edge/edge-public-api
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 edge-public-api
```

O commit deve ser `59b1860`. A partir do container do Public API, o nome `services-platform` deve resolver na `data_net`; se não resolver, interromper e corrigir a associação de rede, sem substituir a URL por IP efêmero de container.

### 5. Publicar o Gateway

```bash
cd /opt/lowify/edge/edge-gateway
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 edge-gateway
```

O commit deve ser `f8d2956`.

### 6. Atualizar Front Checkout e Dashboard

Esses dois repositórios recebem somente atualização Git neste ambiente:

```bash
cd /opt/lowify/front/front-checkout
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD

cd /opt/lowify/front/dashboard-seller
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD
```

Os commits devem ser, respectivamente, `a2e205b` e `fc8b0188`.

## Validação pós-deploy

### Monitoramento

1. Faça login no Dashboard com um usuário administrativo de perfil 1, 2 ou 4.
2. Abra **Infraestrutura**. Os cards de disco, memória, inodes e load devem mostrar valores do servidor, e não traços ou erro de indisponibilidade.
3. Selecione 24 horas, 7 dias e 30 dias. O gráfico deve carregar sem apresentar picos artificiais de load causados por uma única CPU.
4. Clique em **Acompanhar em tempo real**. Em até 5 segundos, o gráfico deve mostrar disco, memória, inodes e load. Ao ocultar uma série pela legenda, ela deve continuar oculta nos ticks seguintes e o gráfico não deve repetir a animação de montagem.
5. Mantenha o modal aberto por mais de 1 minuto. A coleta deve continuar; ao fechá-lo, deve parar sem persistir as amostras rápidas no histórico.
6. A tabela de backups deve permanecer vazia. Não deve surgir dump em `/var/lib/platform/backups`, job de upload ou tentativa de R2.
7. Não provocar artificialmente 80% de uso de disco em produção. O alerta interno será validado quando ocorrer uma condição real; a conferência técnica opcional pode verificar que Platform e Notifications estão saudáveis e usam o mesmo segredo B, sem imprimir o segredo.

Se a página informar indisponibilidade, interromper a validação funcional e conferir, nesta ordem, Public API, resolução DNS de `services-platform`, assinatura A, health do Platform, MariaDB e Redis próprios.

### Prévia do checkout

1. Entre como o proprietário de um produto e abra **Personalizar aparência**.
2. A prévia deve carregar mesmo quando o produto estiver inativo ou indisponível para uma compra normal.
3. Confirme que banner, textos, preço, depoimentos, formulário e meios de pagamento aparecem.
4. O formulário deve ser apenas visual: campos, botões e pagamento não podem executar compra, validação externa ou redirecionamento.
5. Aguarde mais de 5 minutos e reabra o editor. Uma nova autorização deve ser criada e a prévia deve voltar a abrir normalmente.
6. Tente abrir o editor de um produto que não pertence ao usuário autenticado. A autorização deve ser recusada.
7. Abra o checkout normal do mesmo produto sem `editor_preview=1`. As regras normais de disponibilidade e pagamento devem continuar inalteradas.

## Conferência técnica opcional

Sem exibir segredos ou payloads sensíveis:

```bash
cd /opt/services/services-platform
docker compose ps
docker compose logs --tail=100 services-platform
docker compose exec -T services-platform php bin/hyperf.php migrate:status

cd /opt/lowify/services/services-notifications
docker compose ps
docker compose exec -T services-notifications php bin/hyperf.php migrate:status

cd /opt/lowify/services/service-commerce-v2
docker compose ps

cd /opt/lowify/edge/edge-public-api
docker compose ps

cd /opt/lowify/edge/edge-gateway
docker compose ps
```

Todos os containers devem permanecer em execução, sem ciclo de restart. Não listar o ambiente completo dos containers e não incluir tokens de prévia ou assinaturas nas evidências.

## Rollback

1. Retirar primeiro as interfaces: retornar `dashboard-seller` e `front-checkout` às branches e commits registrados na pré-checagem. O Front Checkout normal continua funcionando sem o modo de prévia.
2. Retornar `edge-gateway` e `edge-public-api` às referências anteriores e reconstruir seus containers. Remover do Public API as três variáveis do Platform somente depois que a versão anterior estiver ativa.
3. Retornar `services-commerce-v2` à referência anterior e reconstruí-lo. Não limpar Redis: os tokens de prévia expiram sozinhos em até 5 minutos.
4. No Platform, definir `PLATFORM_NOTIFICATIONS_ENABLED=false` e reconstruir antes de retirar a rota de Notifications. Isso impede novas tentativas de alerta durante a reversão.
5. Retornar `services-notification` à referência anterior e reconstruir. Manter a migration `2026_10_15_000062` aplicada; os templates são aditivos e não causam envio sem o chamador.
6. Se o Platform precisar ser retirado, parar apenas a aplicação:

   ```bash
   cd /opt/services/services-platform
   docker compose stop services-platform
   ```

7. Não executar `docker compose down -v`, não remover os três volumes, não apagar o banco `operations`, o Redis, incidentes, outbox ou histórico coletado. Não apagar `/opt/services/services-platform` até a investigação e a decisão de retenção dos dados.
8. Os segredos A e B podem permanecer sem uso após o rollback. Rotacioná-los se houver qualquer suspeita de exposição; nunca recuperá-los de logs ou commits.

## Limites desta publicação

- `BACKUP_ENABLED=false` é obrigatório.
- Nenhum banco de aplicação será lido pelo Platform.
- Nenhum dump será criado.
- Nenhuma conta, token ou bucket do Cloudflare R2 será configurado.
- Somente alertas internos são habilitados; não há e-mail de infraestrutura.
- Memória e inodes permanecem apenas no histórico. O único alerta de recurso nesta etapa é uso de disco.

## Referências

- `features/platform-monitoring-checkout-preview/README.md`
- `services-platform/.env.example`
- `services-platform/.env.production.example`
- `services-platform/README.md`
- `services-notification/migrations/2026_10_15_000062_seed_platform_in_app_templates.php`
