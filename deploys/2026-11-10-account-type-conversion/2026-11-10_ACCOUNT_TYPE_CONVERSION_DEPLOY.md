# Deploy — conversão administrativa de tipo de conta

## Objetivo

Publicar no `services-account` o comando administrativo `account:convert-type`.
Ele mostra uma prévia por padrão e só grava dados com `--apply` e
`--confirm-user-id`. A conversão PF para PJ cria um sócio a partir da PF; a
conversão PJ para PF reseta o cadastro empresarial e reaproveita os dados de um
sócio ativo apenas quando o CPF informado pertence à própria PJ.

Esta homologação cobre somente o `services-account`. Não há alteração de rota,
JWT, dashboard, edge, banco, Redis ou outro serviço.

## Componentes e referências

| Repositório | Target de homologação | Branch | Commit |
| --- | --- | --- | --- |
| `services-account` | `services-account` | `feat/account-type-conversion` | `8c10b3ec9305b2ddbc275b550ae8f10a694fb2e8` |

Modo de rebuild: incremental.

## Targets mantidos como estão

Por solicitação explícita, não executar pré-checagem, Git nem Docker nos demais
targets operáveis: `dashboard-seller`, `front-chat`, `front-checkout`,
`front-idv`, `front-member-area`, `edge-gateway`, `edge-public-api`,
`edge-webhook`, `services-auth`, `services-banking`, `services-banking-v2`,
`services-commerce`, `services-commerce-v2`, `services-notification`,
`services-platform`, `services-wallet`, `checkout-transparent-api`,
`checkout-transparent-billing`, `checkout-transparent-worker` e `ct-webhook`.

Também permanecem preservados, conforme o mapa: `checkout-transparent-infra` e
`data_layer`. Itens ausentes ou não mapeados na VPS não participam da operação.

## Alterações incluídas

- Novo caso de uso transacional para PF ↔ PJ, com lock por documento alvo.
- CPF/CNPJ de destino obrigatório, normalizado e validado antes da conversão.
- Conflitos em outro seller retornam `document_already_assigned` com `user_id`
  e e-mail do owner.
- A prévia exibe os dados atuais, origem do sócio quando existente, dados finais
  projetados, itens resetados e o refresh que será enfileirado.
- A aplicação invalida a completude e publica em
  `accounts:complete:refresh`; o consumidor já existente é
  `ProfileCompletionRefreshQueueProcess`.

## Pré-requisitos

1. A branch remota e o commit acima devem existir em `origin`.
2. O repositório `services-account` da VPS deve estar limpo antes de qualquer
   troca de branch.
3. O container do serviço deve ficar saudável após o rebuild.
4. O processo de refresh de completude deve estar habilitado por
   `PROFILE_COMPLETION_REFRESH_PROCESS_ENABLED`.
5. A validação deste deploy é somente de prévia: não usar `--apply`, não criar
   contas, não alterar sellers, não limpar Redis e não manipular filas.

## Banco de dados

Não há migration, DDL nem DML de deploy. A validação lê `tbl_usuarios`,
`user_partner`, `addresses`, `documents`, `user_verification_sessions`,
`user_addicional` e `user_reviews` somente pela prévia do comando.

## Sequência de deploy

1. Conectar em `root@217.216.87.77` e, somente no target permitido, conferir:

```bash
cd /root/opt/lowify/services/services-account
git status --porcelain=v1
git branch --show-current
git remote get-url origin
```

2. Se o status estiver vazio e `origin` apontar para o repositório oficial,
validar a branch remota:

```bash
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/account-type-conversion
```

3. Atualizar apenas este repositório e reconstruir o container:

```bash
git switch feat/account-type-conversion
git pull --ff-only origin feat/account-type-conversion
docker compose up --build -d
docker compose ps
```

4. Registrar branch e commit finais. Não executar comandos nos targets listados
em “Targets mantidos como estão”.

## Testes de compatibilidade em homologação

Executor: container `services-account` do repositório
`/root/opt/lowify/services/services-account`.

Selecionar aleatoriamente 50 sellers com `account_phase IN (2, 3)`, sem usar
fase 1. Para cada seller, executar exclusivamente a prévia de conversão para o
tipo oposto com CPF/CNPJ sintaticamente válido e ainda não associado a outro
seller. Registrar o JSON de antes/depois, ou o erro de colisão de documento,
sem expor CPF/CNPJ no relatório.

Critério de aprovação: 50 prévias processadas sem escrita; cada resultado deve
ter `preview: true`, `applied: false`, `before`, `after`, `document_check` e
`will_enqueue`. Sellers fase 1, aplicações (`--apply`) e alterações em filas
reprovam a execução.

## Validação pós-deploy

1. Confirme que o container `services-account` aparece como em execução.
2. Rode uma prévia para um seller de teste PF com um CNPJ ainda livre. Deve ser
   exibida uma comparação entre o cadastro atual e a PJ projetada, sem mudar o
   cadastro.
3. Rode uma prévia para um seller PJ com CPF de sócio ativo. Deve aparecer o
   sócio como origem dos dados PF.
4. Rode uma prévia com CPF/CNPJ vinculado a outro seller. Deve aparecer um erro
   identificando o ID e e-mail desse seller, sem alterar nenhuma conta.

## Rollback

Como a validação não usa `--apply`, não há dados para reverter. A referência
anterior observada na VPS era `feat/account-phase-one-migration` no commit
`96f393764478e983c5fda87d4f446de49c0136e6`. Para retirar o comando, no mesmo
repositório, voltar a essa referência com `git switch
feat/account-phase-one-migration`, `git pull --ff-only origin
feat/account-phase-one-migration` e `docker compose up --build -d`. Não apagar
documentos, sócios, sessões, contas, Redis ou filas.
