# Deploy — abertura manual de contas BaaS

## Objetivo

Publicar o controle de custo da abertura Woovi: novas contas deixam de ser
enviadas automaticamente para a Woovi por padrão. O onboarding automático de
Cielo Split permanece ativo. Operadores autorizados poderão solicitar
explicitamente a abertura Woovi durante a revisão cadastral ou iniciar uma
abertura Woovi/Cielo Split no overview do seller.

## Componentes e referências

Antes da publicação, confirmar que a branch existe no remoto e registrar a
revisão efetivamente publicada com `git rev-parse --short HEAD`.

| Repositório | Diretório na VPS | Branch de deploy | Entrega |
| --- | --- | --- | --- |
| `services-account` | `/opt/lowify/services/services-account` | `feat/manual-woovi-baas-onboarding` | Flag Woovi, decisão de review, evento manual e resolução de abertura Cielo/Woovi. |
| `edge-public-api` | `/opt/lowify/edge/edge-public-api` | `feat/manual-woovi-baas-onboarding` | Autorização JWT e contrato HTTP da abertura manual. |
| `edge-gateway` | `/opt/lowify/edge/edge-gateway` | `feat/manual-woovi-baas-onboarding` | Rota autenticada e encaminhamento ao Public API. |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `feat/manual-woovi-baas-onboarding` | Toggle de revisão e ação manual no overview do seller. |

## Alterações incluídas

1. `WOOVI_BAAS_AUTO_REGISTER_ENABLED` passa a controlar somente o evento
   automático Woovi criado ao completar cadastro. O default é `false`.
2. Cielo Split continua no seu fluxo automático já existente, disparado após a
   aprovação de conta bancária; esta entrega não altera essa fila nem suas
   credenciais.
3. A aprovação de review recebe `send_to_woovi`. Apenas a opção marcada gera
   `register_baas` com provider `woovi`.
4. A rota manual `POST /baas/accounts/open` aceita `user_id` e `provider`
   (`woovi` ou `cielo_split`), exige JWT administrativo e é acessível no
   Dashboard apenas com `admin_financial_providers`.
5. O pedido manual não faz bloqueio prévio baseado em contas BaaS existentes;
   o fluxo do provider mantém a responsabilidade por validar e retornar erros.

## Pré-requisitos

1. Confirmar que os quatro diretórios estão limpos antes de trocar branch. Se
   `git status --porcelain=v1` retornar linhas, parar e preservar o trabalho
   local antes de seguir.
2. Publicar as quatro branches no remoto antes de executar este roteiro.
3. Preservar `ACCOUNT_EVENTS_PROCESS_ENABLED=true` no `services-account`; ele
   consome `account:user:events`, incluindo solicitações manuais Woovi e Cielo.
4. Definir explicitamente `WOOVI_BAAS_AUTO_REGISTER_ENABLED=false` no ambiente
   do `services-account`. A ausência também resulta em `false`, mas declarar a
   variável deixa a operação auditável.
5. Não alterar credenciais Woovi/Cielo, não limpar Redis e não consumir ou
   reprocessar mensagens manualmente durante o deploy.

## Banco de dados

Não há migration, DDL ou DML nesta entrega.

## Sequência de deploy

O modo é incremental. Atualizar e reconstruir Account, Public API e Gateway,
nessa ordem. O `dashboard-seller` recebe somente a atualização Git; não subir
nem reconstruir seu container neste roteiro.

### 1. `services-account`

```bash
cd /opt/lowify/services/services-account
git status --porcelain=v1
git fetch origin --prune
git switch feat/manual-woovi-baas-onboarding
git pull --ff-only origin feat/manual-woovi-baas-onboarding
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

Confirmar no ambiente que `WOOVI_BAAS_AUTO_REGISTER_ENABLED=false` está
configurada e que o processo de eventos da conta iniciou sem erro.

### 2. `edge-public-api`

```bash
cd /opt/lowify/edge/edge-public-api
git status --porcelain=v1
git fetch origin --prune
git switch feat/manual-woovi-baas-onboarding
git pull --ff-only origin feat/manual-woovi-baas-onboarding
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

### 3. `edge-gateway`

```bash
cd /opt/lowify/edge/edge-gateway
git status --porcelain=v1
git fetch origin --prune
git switch feat/manual-woovi-baas-onboarding
git pull --ff-only origin feat/manual-woovi-baas-onboarding
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

### 4. `dashboard-seller`

```bash
cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git fetch origin --prune
git switch feat/manual-woovi-baas-onboarding
git pull --ff-only origin feat/manual-woovi-baas-onboarding
git rev-parse --short HEAD
```

## Testes de compatibilidade em homologação

Executor: ambiente publicado do `dashboard-seller`, usando uma conta de teste
sem dados pessoais reais e uma conta bancária de homologação reversível.

Pré-condições: os quatro componentes acima saudáveis, JWT administrativo de
teste e `WOOVI_BAAS_AUTO_REGISTER_ENABLED=false` no Account.

1. Complete um cadastro elegível e confirme que a tela/fluxo Cielo segue
   disponível, sem abertura automática de conta Woovi.
2. Abra uma revisão cadastral, mantenha “Enviar conta para Woovi” desligado e
   aprove. Confirme que a aprovação conclui sem solicitação Woovi.
3. Repita com o toggle ligado. Confirme a mensagem de aprovação e, como
   conferência técnica opcional, verifique um evento `register_baas` para
   provider `woovi` em `account:user:events`/`user_events`.
4. No overview do seller, abra “Contas BaaS”, selecione “Conta BaaS Woovi” e
   confirme a mensagem de solicitação criada. Repita para “Conta Split Cielo”.
5. Tente a mesma tela com um perfil sem a permissão necessária e confirme que
   a ação não aparece e que a rota retorna acesso negado.

Limpeza: usar apenas contas de teste e registrar os identificadores criados
para o procedimento normal de encerramento/reversão do provider. Não apagar
mensagens ou registros de eventos para encobrir o teste.

## Validação pós-deploy

1. Faça login como administrador autorizado e abra o overview de um seller.
   Em “Contas BaaS”, a opção “Criar envio” deve mostrar Woovi e Cielo Split.
2. Solicite cada provider com uma conta de teste. A tela deve confirmar o
   envio ou mostrar o erro retornado, sem travar a página.
3. Abra uma revisão de conta. A nova etapa “Integração Woovi” deve aparecer
   com o toggle desligado. Aprovar desligado não abre Woovi; aprovar ligado
   solicita Woovi.
4. Complete o cadastro de uma conta de teste com a flag desligada. Cielo deve
   continuar o comportamento normal; Woovi não deve ser solicitada
   automaticamente.
5. Se algum resultado não for o esperado, interrompa novas solicitações
   manuais, mantenha as filas preservadas e reporte o seller de teste, o horário
   e o provider usado para investigação.

## Rollback

1. Primeiro ocultar/interromper o uso administrativo da ação manual, se houver
   incidente operacional.
2. Retornar os componentes na ordem inversa: Dashboard, Gateway, Public API e
   Account, sempre para a revisão anterior aprovada.
3. Manter `WOOVI_BAAS_AUTO_REGISTER_ENABLED=false` durante o rollback para não
   reativar aberturas Woovi por acidente.
4. Não apagar `user_events`, mensagens de `account:user:events`, tentativas,
   contas BaaS ou registros Cielo/Woovi. Eventos já aceitos devem ser
   reconciliados pelo fluxo normal do provider.
5. O rollback de código não desfaz solicitações externas já enviadas; registrar
   as solicitações afetadas e tratá-las com o procedimento operacional de cada
   provider.

## Referências

- `plans/manual-woovi-baas-onboarding/README.md`
- `services-account/app/Domain/Account/AccountCompleteRegisterHandler.php`
- `services-account/app/Application/UseCase/AccountReview/ProcessApprovedAccountReviewQueueUseCase.php`
- `edge-public-api/app/UseCases/Baas/OpenBaasAccountUseCase.php`
