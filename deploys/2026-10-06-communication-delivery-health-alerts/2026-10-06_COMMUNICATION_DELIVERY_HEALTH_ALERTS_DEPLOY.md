# Deploy — Alertas de saúde de entregas

> Status: preparação operacional — **não promover para produção antes de concluir a validação visual em homologação e limpar o cenário sintético ativo**.

## Objetivo

Publicar a detecção recorrente de falhas de entrega por WhatsApp Meta e e-mail. Quando uma categoria tiver os últimos `N` envios terminais em falha, o Notification ativa uma manutenção global pelo Account, grava um log mínimo, publica uma notificação interna para administradores e o Dashboard Seller mostra um alerta prioritário que pode ser reconhecido.

Esta entrega não reenvia mensagens, não bloqueia novos envios, não altera provedores e não expõe conteúdo, telefones, e-mails ou payloads de entrega.

## Componentes e referências

| Repositório | Branch de deploy | Commit de referência | Responsabilidade |
| --- | --- | --- | --- |
| `services-account` | `feat/communication-delivery-health-alerts` | `7570fd9` | Endpoint interno idempotente e upsert das sysvars globais. |
| `services-notification` | `feat/communication-delivery-health-alerts` | `0a79e1c` | Processo a cada minuto, cursor Redis, migration, logs e notificações in-app. |
| `dashboard-seller` | `feat/communication-delivery-health-alerts` | `3d4b79db` | Banner prioritário, resolução local e roteamento das notificações. |

Não há mudança em Gateway, Public API, Webhook, infraestrutura, banco compartilhado fora da migration do Notification ou filas existentes.

## Alterações incluídas

- Notification avalia apenas categorias afetadas por alterações recentes em `whatsapp_meta` e `email_single`; cada consulta lê somente os últimos `N` registros terminais da própria população.
- O processo usa Redis para cursor e cooldown por categoria. A fila existente `notifications:in_app:create` recebe notificações com destino `admin`.
- Account recebe `POST /internal/communication-delivery-maintenance/activate`. A chamada aceita somente uma detecção posterior à última resolução e usa `SystemVarService` para manter as chaves globais.
- Dashboard lê e resolve as sysvars localmente. O aviso tem prioridade `1000`, não é dispensável por sessão e só é elegível para `admin_service_status` (perfis 1, 2 e 4).
- A migration `2026_10_06_000060_create_delivery_health_logs_and_templates` cria `delivery_health_logs`, índices compostos e os quatro templates in-app.

## Pré-requisitos e bloqueios de promoção

1. As três branches devem existir no remoto e apontar para os commits da tabela acima, ou para commits aprovados posteriores da mesma feature.
2. Confirmar que cada repositório produtivo está limpo antes de qualquer `fetch`, `switch` ou Docker. Se houver alteração local, parar; não usar stash, reset ou limpeza.
3. Confirmar as URLs internas já existentes entre Notification e Account e a conectividade Redis. Não criar novos segredos nem copiar valores de `.env` para este documento.
4. Confirmar em homologação, com um administrador de perfis 1, 2 ou 4, o banner vermelho, as ações **Detalhes** e **Resolvido**. A validação visual ficou pendente no ciclo de homologação de 2026-10-06 porque o diretório do Dashboard foi alternado concorrentemente para outra branch.
5. Limpar e resolver o incidente sintético de homologação `delivery-health-hml-20261006205305` antes de qualquer promoção. Não transportar esse dado de teste para produção.
6. Escolher uma janela de menor volume para a migration: ela cria índices em `whatsapp_meta` e `email_single`.

## Configuração

Os defaults de código permitem deploy sem valor novo obrigatório. Se a operação precisar alterar o comportamento, declarar somente os nomes abaixo no `.env` de `services-notifications`; nunca registrar valores secretos neste documento.

| Variável | Default |
| --- | --- |
| `DELIVERY_HEALTH_WHATSAPP_META_PROVIDER_FAILURE_THRESHOLD` | `5` |
| `DELIVERY_HEALTH_WHATSAPP_TEMPLATE_FAILURE_THRESHOLD` | `5` |
| `DELIVERY_HEALTH_EMAIL_PROVIDER_FAILURE_THRESHOLD` | `5` |
| `DELIVERY_HEALTH_EMAIL_TEMPLATE_FAILURE_THRESHOLD` | `5` |
| `DELIVERY_HEALTH_NOTIFICATION_COOLDOWN_MINUTES` | `10` |
| `DELIVERY_HEALTH_BATCH_SIZE` | `500` |

Valores ausentes, inválidos ou menores que `1` voltam aos defaults. Não habilitar override de teste em produção.

## Banco de dados

Aplicar somente no banco do `services-notification` a migration:

```text
2026_10_06_000060_create_delivery_health_logs_and_templates
```

Ela cria:

- tabela `delivery_health_logs`;
- índices por `updated_at`/`id`, template e provider nas tabelas de envio;
- templates `delivery_health_*` em `in_app_notifications_template`.

Antes de aplicar, conferir o status da migration. Depois, conferir que ela aparece como `Yes`. Não executar rollback automático de schema, não apagar logs e não limpar Redis como parte da reversão.

As sysvars `communication_delivery_maintenance_*` não precisam de seed: são criadas pelo Account apenas após uma detecção aceita.

## Sequência de deploy

Os caminhos abaixo seguem o padrão já usado no servidor principal. O operador deve confirmar host e diretórios produtivos antes do início; estes não são os caminhos da VPS de homologação.

### 1. Pré-checagem

Em cada diretório participante, antes de alterar qualquer branch:

```bash
git status --porcelain=v1
git branch --show-current
git remote get-url origin
```

Se qualquer saída de `git status --porcelain=v1` não for vazia, parar todo o deploy.

### 2. `services-account`

```bash
cd /opt/lowify/services/services-account
git fetch origin --prune
git switch feat/communication-delivery-health-alerts
git pull --ff-only origin feat/communication-delivery-health-alerts
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=50
```

Resultado esperado: container `Up`, health sem erro e endpoint interno disponível na rede entre serviços.

### 3. `services-notification` e migration

```bash
cd /opt/lowify/services/services-notifications
git fetch origin --prune
git switch feat/communication-delivery-health-alerts
git pull --ff-only origin feat/communication-delivery-health-alerts
git rev-parse --short HEAD
docker compose up -d --build
docker compose exec -T services-notifications php bin/hyperf.php migrate:status
docker compose exec -T services-notifications php bin/hyperf.php migrate --force --path=migrations/2026_10_06_000060_create_delivery_health_logs_and_templates.php
docker compose exec -T services-notifications php bin/hyperf.php migrate:status
docker compose ps
docker compose logs --tail=80 services-notifications
```

Resultado esperado: processo `delivery_health.0` iniciado, migration marcada como aplicada e nenhum erro de schema, Redis ou HTTP interno nos logs.

### 4. `dashboard-seller`

```bash
cd /opt/lowify/front/dashboard-seller
git fetch origin --prune
git switch feat/communication-delivery-health-alerts
git pull --ff-only origin feat/communication-delivery-health-alerts
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

O compose do Dashboard monta o diretório do repositório no container. Confirmar que a branch não é trocada por outra operação enquanto a validação estiver em andamento.

## Testes de compatibilidade em homologação

Executar somente após os três containers estarem saudáveis e a migration estar aplicada.

- Roteiro: [caso de injeção controlada](../../plans/communication-delivery-health-alerts/HOMOLOGATION_ERROR_INJECTION_TEST.md).
- Executor: containers `services-notifications`, `services-account` e `front-dashboard-seller`.
- Dados: cinco registros sintéticos `whatsapp_meta` com identificador exclusivo; não usar telefone, conteúdo ou dados de clientes reais.
- Resultado esperado: sysvar ativa, log mínimo, duas notificações internas `admin`, banner visível para admin autorizado, resolução idempotente e reabertura apenas após falha nova.
- Limpeza: remover exclusivamente dados sintéticos da execução e restaurar as sysvars ao estado anterior. Não limpar filas, chaves Redis genéricas ou notificações de terceiros.

## Validação pós-deploy

1. Faça login com um administrador de perfil 1, 2 ou 4.
2. Execute o cenário sintético homologado; quando o alerta for aberto, recarregue qualquer página do Dashboard.
3. Confirme que aparece uma faixa vermelha com o texto sobre falhas recorrentes de envio, acima de avisos de cadastro incompleto.
4. Clique em **Detalhes** e confirme que abre o Status de serviços sem remover o alerta.
5. Clique em **Resolvido**. Cancele uma vez e confirme que o alerta continua. Depois confirme a resolução e veja o banner desaparecer.
6. Abra as notificações internas e confirme que o alerta leva ao Status de serviços apenas para administrador autorizado.
7. Se qualquer resultado visível não ocorrer, parar a promoção e registrar página, horário e comportamento observado. Não limpar filas ou dados para forçar aprovação.

## Rollback

1. Primeiro interromper a geração de novos incidentes retornando `services-notification` à revisão anterior aprovada e reconstruindo apenas esse componente.
2. Reverter `dashboard-seller` à revisão anterior aprovada e reconstruí-lo; o Dashboard deixa de exibir/permitir a resolução, mas os dados persistidos permanecem como evidência.
3. Reverter `services-account` por último, somente após Notification não chamar mais o endpoint interno novo.
4. Não reverter automaticamente a migration, índices, logs, notificações, sysvars ou chaves Redis. Avaliar qualquer remoção de dados em plano separado, após preservar evidências.
5. Para encerrar um incidente legítimo durante rollback, usar o caminho administrativo **Resolvido** enquanto o Dashboard ainda estiver disponível; não apagar manualmente sysvars.
