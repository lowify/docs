# Deploy — Alertas de saúde de entregas

> Status: preparação operacional — **não promover para produção antes de concluir a validação visual em homologação e limpar o cenário sintético ativo**.

## Objetivo

Publicar a detecção recorrente de falhas de entrega por WhatsApp Meta e e-mail. Quando uma categoria tiver os últimos `N` envios terminais em falha, o Notification ativa uma manutenção global pelo Account, grava um log mínimo, publica uma notificação interna para administradores e o Dashboard Seller mostra um alerta prioritário que pode ser reconhecido. A família `sale_recovering_ct_1` a `sale_recovering_ct_7` é exceção: ela gera somente notificação interna e alterna o template de recuperação de venda.

Esta entrega não reenvia mensagens, não bloqueia novos envios, não altera provedores e não expõe conteúdo, telefones, e-mails ou payloads de entrega.

Foram executados testes em homologação com cenário controlado: a detecção criou os logs mínimos, ativou a manutenção global e publicou as notificações internas para administradores. A validação visual do Dashboard deve ser concluída quando a branch da feature estiver selecionada sem troca concorrente de diretório.

## Componentes e referências

| Repositório | Branch de deploy | Responsabilidade |
| --- | --- | --- |
| `services-account` | `feat/communication-delivery-health-alerts` | Endpoint interno idempotente e upsert das sysvars globais. |
| `services-notification` | `feat/communication-delivery-health-alerts` | Processo a cada minuto, cursor Redis, migration, logs e notificações in-app. |
| `dashboard-seller` | `feat/communication-delivery-health-alerts` | Banner prioritário, resolução local e roteamento das notificações. |

Não há mudança em Gateway, Public API, Webhook, infraestrutura, banco compartilhado fora da migration do Notification ou filas existentes.

## Alterações incluídas

- Notification avalia apenas categorias afetadas por alterações recentes em `whatsapp_meta` e `email_single`; cada consulta lê somente os últimos `N` registros terminais da própria população.
- O processo usa Redis para cursor e cooldown por categoria. A fila existente `notifications:in_app:create` recebe notificações com destino `admin`.
- Account recebe `POST /internal/communication-delivery-maintenance/activate`. A chamada aceita somente uma detecção posterior à última resolução e usa `SystemVarService` para manter as chaves globais.
- Dashboard lê e resolve as sysvars localmente. O aviso tem prioridade `1000`, não é dispensável por sessão e só é elegível para `admin_service_status` (perfis 1, 2 e 4).
- A migration `2026_10_06_000060_create_delivery_health_logs_and_templates` cria `delivery_health_logs`, índices compostos e os quatro templates in-app.
- A migration `2026_10_08_000061_add_default_type_to_whatsapp_meta_templates` adiciona o estado persistido do template padrão de recuperação de venda. O valor `default_type = 1` representa `SALE_RECOVERY` e inicia em `sale_recovering_ct_4`.
- Quando o template padrão dessa família falha recorrentemente, o Notification não ativa a manutenção global nem o banner. Ele registra o evento, notifica administradores e muda `default_type = 1` para o próximo template. Em `_7`, não há rotação circular: a notificação pede ajuste manual.
- Em **Configurações do sistema → WhatsApp Meta**, o Dashboard exibe somente para leitura a etapa **Recuperação de venda — etapa 1** e seu template padrão. O valor vem da resposta já existente de `/admin/system/overview`; não há nova rota nem edição nessa tela.

## Pré-requisitos e bloqueios de promoção

1. As três branches devem existir no remoto e apontar para os commits da tabela acima, ou para commits aprovados posteriores da mesma feature.
2. Confirmar que cada repositório produtivo está limpo antes de qualquer `fetch`, `switch` ou Docker. Se houver alteração local, parar; não usar stash, reset ou limpeza.
3. Confirmar as URLs internas já existentes entre Notification e Account e a conectividade Redis. Não criar novos segredos nem copiar valores de `.env` para este documento.
4. Confirmar em homologação, com um administrador de perfis 1, 2 ou 4, o banner vermelho, as ações **Detalhes** e **Resolvido**. A validação visual ficou pendente no ciclo de homologação de 2026-10-06 porque o diretório do Dashboard foi alternado concorrentemente para outra branch.
5. Limpar e resolver o incidente sintético de homologação `delivery-health-hml-20261006205305` antes de qualquer promoção. Não transportar esse dado de teste para produção.
6. Escolher uma janela de menor volume para a migration: ela cria índices em `whatsapp_meta` e `email_single`.

## Banco de dados

Aplicar somente no banco do `services-notification` a migration:

```text
2026_10_06_000060_create_delivery_health_logs_and_templates
2026_10_08_000061_add_default_type_to_whatsapp_meta_templates
```

Ela cria:

- tabela `delivery_health_logs`;
- índices por `updated_at`/`id`, template e provider nas tabelas de envio;
- templates `delivery_health_*` em `in_app_notifications_template`.
- coluna nullable e única `whatsapp_meta_templates.default_type`;
- registros da família `sale_recovering_ct_1` a `_7` e templates in-app de rotação/esgotamento.

Antes de aplicar, conferir o status da migration. Depois, conferir que ela aparece como `Yes`. Não executar rollback automático de schema, não apagar logs e não limpar Redis como parte da reversão.

As sysvars `communication_delivery_maintenance_*` não precisam de seed: são criadas pelo Account apenas após uma detecção aceita.

### Ajuste manual do template de recuperação

O template ativo é consultável diretamente em `whatsapp_meta_templates`: o registro com `default_type = 1` é o padrão de recuperação de venda. Para trocar manualmente, realizar uma transação, remover o `default_type` do registro atual e atribuir `1` ao template desejado da família `sale_recovering_ct_1` a `_7`. O índice único garante que só exista um padrão desse tipo. Não usar rotação circular nem definir `default_type` em templates de outra família.

## Sequência de deploy

Os caminhos abaixo seguem o padrão já usado no servidor principal. O operador deve confirmar host e diretórios produtivos antes do início; estes não são os caminhos da VPS de homologação.

### 1. `services-account`

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

### 2. `services-notification` e migration

```bash
cd /opt/lowify/services/services-notifications
git fetch origin --prune
git switch feat/communication-delivery-health-alerts
git pull --ff-only origin feat/communication-delivery-health-alerts
git rev-parse --short HEAD
docker compose up -d --build
docker compose exec -T services-notifications php bin/hyperf.php migrate:status
docker compose exec -T services-notifications php bin/hyperf.php migrate --force --path=migrations/2026_10_06_000060_create_delivery_health_logs_and_templates.php
docker compose exec -T services-notifications php bin/hyperf.php migrate --force --path=migrations/2026_10_08_000061_add_default_type_to_whatsapp_meta_templates.php
docker compose exec -T services-notifications php bin/hyperf.php migrate:status
docker compose ps
docker compose logs --tail=80 services-notifications
```

Resultado esperado: processo `delivery_health.0` iniciado, migrations marcadas como aplicadas, `sale_recovering_ct_4` com `default_type = 1` e nenhum erro de schema, Redis ou HTTP interno nos logs.

### 3. `dashboard-seller`

```bash
cd /opt/lowify/front/dashboard-seller
git fetch origin --prune
git switch feat/communication-delivery-health-alerts
git pull --ff-only origin feat/communication-delivery-health-alerts
git rev-parse --short HEAD
```

O compose do Dashboard monta o diretório do repositório no container; portanto não é necessário executar `docker compose up -d --build` para esta entrega. Confirmar que a branch não é trocada por outra operação enquanto a validação estiver em andamento.

## Validação pós-deploy

Esta validação depende de uma falha real de template ou de provedor atingir o limiar configurado após o deploy. Não injetar nem induzir falhas em produção.

1. Aguardar a abertura natural de um incidente e fazer login com um administrador de perfil 1, 2 ou 4.
2. Confirmar que aparece uma faixa vermelha sobre falhas recorrentes de envio, acima de avisos de cadastro incompleto.
3. Clicar em **Detalhes** e confirmar que abre o Status de serviços sem remover o alerta.
4. Clicar em **Resolvido**. Cancelar uma vez e confirmar que o alerta continua. Depois confirmar a resolução e verificar o desaparecimento do banner.
5. Abrir as notificações internas e confirmar que o alerta leva ao Status de serviços apenas para administrador autorizado.
6. Se qualquer resultado visível não ocorrer, registrar página, horário e comportamento observado. Não limpar filas ou dados para forçar aprovação.

Para uma falha recorrente da família `sale_recovering_ct_*`, a confirmação é diferente: não deve aparecer faixa global nem ocorrer ativação de manutenção. Deve ser criada somente a notificação interna e o registro ativo deve avançar de `default_type = 1` para o próximo template. Em `sale_recovering_ct_7`, confirmar a notificação de esgotamento e fazer o ajuste manual descrito acima.

## Rollback

1. Primeiro interromper a geração de novos incidentes retornando `services-notification` à revisão anterior aprovada e reconstruindo apenas esse componente.
2. Reverter `dashboard-seller` à revisão anterior aprovada e reconstruí-lo; o Dashboard deixa de exibir/permitir a resolução, mas os dados persistidos permanecem como evidência.
3. Reverter `services-account` por último, somente após Notification não chamar mais o endpoint interno novo.
4. Não reverter automaticamente a migration, índices, logs, notificações, sysvars, o `default_type` do template ativo ou chaves Redis. Avaliar qualquer remoção de dados em plano separado, após preservar evidências.
5. Para encerrar um incidente legítimo durante rollback, usar o caminho administrativo **Resolvido** enquanto o Dashboard ainda estiver disponível; não apagar manualmente sysvars.
