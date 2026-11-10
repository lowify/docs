# Deploy — conversão administrativa de tipo de conta

## Objetivo

Publicar no `services-account` o comando administrativo `account:convert-type`.
Ele mostra uma prévia por padrão e só grava dados com `--apply` e
`--confirm-user-id`. A conversão PF para PJ cria um sócio a partir da PF; a
conversão PJ para PF reseta o cadastro empresarial e reaproveita os dados de um
sócio ativo apenas quando o CPF informado pertence à própria PJ.

Este deploy de produção cobre somente o `services-account`. Não há alteração de rota,
JWT, dashboard, edge, banco, Redis ou outro serviço.

## Componentes e referências

| Repositório | Target de produção | Branch | Commit |
| --- | --- | --- | --- |
| `services-account` | `services-account` | `feat/account-type-conversion` | `8c10b3ec9305b2ddbc275b550ae8f10a694fb2e8` |

Modo de rebuild: incremental.

## Alterações incluídas

- Novo caso de uso transacional para PF ↔ PJ, com lock por documento alvo.
- CPF/CNPJ de destino obrigatório e normalizado antes da conversão.
- Conflitos em outro seller retornam `document_already_assigned` com `user_id`
  e e-mail do owner.
- A prévia exibe os dados atuais, origem do sócio quando existente, dados finais
  projetados, itens resetados e o refresh que será enfileirado.
- A aplicação marca a completude como incompleta e publica em
  `accounts:complete:refresh`; o consumidor já existente é
  `ProfileCompletionRefreshQueueProcess`.

## Pré-requisitos

1. A branch remota e o commit acima devem existir em `origin`.
2. O repositório `services-account` da VPS deve estar limpo antes de qualquer
   troca de branch.
3. O container do serviço deve ficar saudável após o rebuild.
4. O processo de refresh de completude deve estar habilitado por
   `PROFILE_COMPLETION_REFRESH_PROCESS_ENABLED`.

## Banco de dados

Não há migration, DDL nem DML de deploy. O comando lê `tbl_usuarios`,
`user_partner`, `addresses`, `documents`, `user_verification_sessions`,
`user_addicional` e `user_reviews` somente pela prévia do comando.

## Sequência de deploy

1. Conectar em `root@144.126.149.57` e, somente no target permitido, conferir:

```bash
cd /opt/lowify/services/services-account
git status --porcelain=v1
git branch --show-current
git remote get-url origin
```

2. Se o status estiver vazio e `origin` apontar para o repositório oficial,
consultar a branch remota:

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

## Rollback

Não há dados de deploy para reverter. Antes da troca de branch, registrar a
branch e o commit atualmente publicados em produção. Para retirar o comando,
voltar a essa referência registrada no mesmo repositório com `git switch`,
`git pull --ff-only` e `docker compose up --build -d`. Não apagar documentos,
sócios, sessões, contas, Redis ou filas.
