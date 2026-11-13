# Deploy — migração de tipo de conta pelo Dashboard

## Objetivo

Publicar a interface administrativa para converter cadastros PF ↔ PJ pelo Dashboard Seller, usando o motor canônico do `services-account`. A ação gera uma prévia obrigatória antes da confirmação e não é exibida para sellers na fase 1; estes continuam usando exclusivamente “Migrar para fase 2”.

O fluxo passa por Dashboard Seller, Gateway, Public API e Account. Nenhum componente faz conversão diretamente no banco.

## Componentes e referências

| Repositório | Diretório de homologação | Branch de deploy | Referência atual |
| --- | --- | --- | --- |
| `services-account` | `/root/opt/lowify/services/services-account` | `feat/account-type-conversion-dashboard` | `25910df` |
| `edge-public-api` | `/root/opt/lowify/edge/edge-public-api` | `feat/account-type-conversion-dashboard` | `e1f39f1` |
| `edge-gateway` | `/root/opt/lowify/edge/edge-gateway` | `feat/account-type-conversion-dashboard` | `2c2dfe5` |
| `dashboard-seller` | `/root/opt/lowify/front/dashboard-seller` | `feat/account-type-conversion-dashboard` | `541b6cde` |

Modo de rebuild: incremental.

## Targets mantidos como estão

Por solicitação explícita, não executar comandos nos demais targets da VPS de
homologação. Infraestrutura, banco e Redis também permanecem preservados.

## Alterações incluídas

- O Account expõe `POST /admin/users/{user_id}/account-type-conversion`.
- O motor aceita `to`, `document`, `legal_name` e `preview`; a aplicação ocorre apenas quando `preview=false`.
- O motor rejeita contas fora das fases 2 e 3, inclusive quando a rota for chamada fora do Dashboard.
- Public API exige JWT de administrador não colaborador com permissão 1, 2 ou 4 e encaminha a requisição ao Account; Gateway roteia a mesma URL.
- Dashboard mostra “Migrar tipo de conta” no fim de “Adicional” somente para administradores autorizados e sellers nas fases 2 ou 3.
- PF → PJ exige CNPJ e razão social. PJ → PF exige CPF e reaproveita dados do sócio ativo correspondente quando existir.
- A prévia mostra origem dos dados, cópias de documentos/endereço, reset de dados PJ e conflitos de CPF/CNPJ antes de liberar a confirmação.
- Ao aplicar, o Account marca a completude como incompleta e publica na fila `accounts:complete:refresh`; `ProfileCompletionRefreshQueueProcess` já é o consumidor responsável pelo recálculo.

## Pré-requisitos

1. Registrar branch e commit atualmente publicados em cada participante antes de qualquer troca de branch.
2. Confirmar que os quatro repositórios estão limpos na produção.
3. Confirmar a existência das quatro branches remotas e seus commits finais.
4. Confirmar que o processo de refresh de completude do Account está habilitado por `PROFILE_COMPLETION_REFRESH_PROCESS_ENABLED`.
5. Usar um administrador não colaborador, com permissão 1, 2 ou 4, para a validação na interface.
6. Não aplicar conversões em sellers reais durante a validação inicial; usar contas de teste exclusivas e fazer preview antes de qualquer confirmação.

## Banco de dados

Não há migration, DDL ou DML de deploy. O banco é alterado somente quando um administrador confirma uma conversão pela interface. Não limpar Redis, filas, documentos, sócios ou revisões como parte do deploy.

## Sequência de deploy

Executar a pré-checagem em todos os quatro participantes antes de atualizar o primeiro deles. Se qualquer `git status --porcelain=v1` tiver saída, interromper o deploy e preservar o trabalho local.

### 1. Pré-checagem

Em cada diretório listado na tabela de componentes:

```bash
git status --porcelain=v1
git branch --show-current
git rev-parse HEAD
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/account-type-conversion-dashboard
```

### 2. Services Account

```bash
cd /root/opt/lowify/services/services-account
git switch feat/account-type-conversion-dashboard
git pull --ff-only origin feat/account-type-conversion-dashboard
docker compose up --build -d
docker compose ps
```

### 3. Public API

```bash
cd /root/opt/lowify/edge/edge-public-api
git switch feat/account-type-conversion-dashboard
git pull --ff-only origin feat/account-type-conversion-dashboard
docker compose up --build -d
docker compose ps
```

### 4. Gateway

```bash
cd /root/opt/lowify/edge/edge-gateway
git switch feat/account-type-conversion-dashboard
git pull --ff-only origin feat/account-type-conversion-dashboard
docker compose up --build -d
docker compose ps
```

### 5. Dashboard Seller

```bash
cd /root/opt/lowify/front/dashboard-seller
git switch feat/account-type-conversion-dashboard
git pull --ff-only origin feat/account-type-conversion-dashboard
```

## Validação pós-deploy

1. Faça login como administrador e abra uma conta de teste na fase 1. A nova ação não deve aparecer; somente “Migrar para fase 2” deve estar disponível.
2. Abra uma conta PF de teste na fase 2 ou 3. No fim de “Adicional”, clique em “Migrar tipo de conta”, informe CNPJ e razão social e gere a prévia. Confirme que nenhum dado muda antes da confirmação.
3. Abra uma PJ de teste na fase 2 ou 3, informe o CPF de um sócio ativo e gere a prévia. Confirme que o modal mostra o sócio como origem de dados pessoais.
4. Tente um CPF/CNPJ usado por outro seller. O modal deve bloquear a confirmação e identificar o seller vinculado.
5. Confirme uma conversão apenas em conta de teste. Atualize o overview e confirme o novo tipo de cadastro e o aviso de cadastro incompleto.

Como conferência técnica opcional, verificar que o Account recebeu a rota e publicou `accounts:complete:refresh`; não consumir, limpar ou republicar mensagens manualmente.

## Rollback

1. Interromper novas conversões administrativas.
2. Voltar Dashboard, Gateway, Public API e Account às referências registradas na pré-checagem, nessa ordem, usando `git switch`, `git pull --ff-only` e `docker compose up --build -d`.
3. Não apagar dados já convertidos. Conversões confirmadas são persistentes e exigem análise individual para qualquer correção.
