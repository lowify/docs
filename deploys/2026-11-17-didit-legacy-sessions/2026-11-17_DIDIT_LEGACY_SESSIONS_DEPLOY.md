# Deploy — sessões Didit legadas na migração de fase 1

> Status: preparação concluída; publicação bloqueada até os commits de código serem definidos e enviados ao remoto.

## Objetivo

Ao migrar uma conta PF da fase 1 para a fase 2 com documentação pessoal incompleta, preservar os documentos existentes para histórico, revisão e conclusão de cadastro. As sessões Didit antigas passam de `didit` para `didit_legacy`, permitindo uma nova sessão Didit sem reutilizar a anterior.

Webhooks recebidos depois para uma sessão legada são reconhecidos e ignorados: não recriam uma sessão ativa e não alteram documentos, status de identidade, KYC ou ativação da conta.

## Componentes e referências

| Repositório | Branch de deploy | Commit |
| --- | --- | --- |
| `services-account` | `feat/didit-legacy-sessions` | `0679364` |
| `dashboard-seller` | `feat/didit-legacy-sessions` | `853be1b7` |

Não há alteração em `edge-webhook`: ele continua publicando eventos Didit com provider `didit`; o bloqueio seguro do evento de uma sessão legada ocorre no consumidor do `services-account`.

## Alterações incluídas

- `services-account`: a migração PF incompleta altera todas as sessões do titular com provider `didit` para `didit_legacy`.
- `services-account`: sessões `didit_legacy` não são reutilizadas para criar um novo link Didit e seus documentos não contam como documentos Didit ativos para essa decisão.
- `services-account`: callback atrasado da Didit para uma sessão legada não cria um novo registro `didit` e não produz efeitos de cadastro.
- `dashboard-seller`: a revisão administrativa identifica documentos vinculados a `didit_legacy` com o badge “Didit legado”.
- Os documentos e seus status não são alterados; portanto, seguem disponíveis nos fluxos genéricos de revisão e conclusão.

## Pré-requisitos

1. Confirmar backup recuperável e acesso administrativo ao banco `lowify`.
2. Executar os SQLs manualmente na ordem documentada. Não executar migrations automáticas para esta entrega.
3. Antes de atualizar código, confirmar árvores limpas, remoto correto e branches/commits publicados dos dois repositórios.
4. Não limpar Redis, filas ou eventos de webhook. Nenhuma credencial deve ser incluída em comandos, logs ou documentos.
5. A DDL deve ser concluída antes de publicar o `services-account`, pois o novo valor do ENUM precisa existir antes de a migração gravar `didit_legacy`.

## Ajuste de banco

A estrutura observada em homologação é `lowify.user_verification_sessions.provider ENUM('didit','local') NULL DEFAULT NULL`.

1. Execute [PRECHECK.sql](sql/lowify/PRECHECK.sql).
2. Execute [DEPLOY.sql](sql/lowify/DEPLOY.sql) somente se o resultado corresponder exatamente ao formato esperado no precheck.
3. Execute [VALIDATE.sql](sql/lowify/VALIDATE.sql) e confirme `ENUM('didit','didit_legacy','local')`, aceitando `NULL` e default `NULL`.

Se o precheck indicar que `didit_legacy` já existe, não execute o DDL novamente. Se retornar outro formato, interrompa o deploy e revise o schema antes de prosseguir.

## Sequência de deploy

### 1. Aplicar e validar o DDL manual

Executar os três SQLs da seção anterior no banco `lowify`. Esta etapa deve terminar antes de reiniciar o Account.

### 2. Publicar `services-account`

Após definir e enviar o commit da `feat/didit-legacy-sessions` que contém esta entrega:

```bash
cd /root/opt/lowify/services/services-account
git status --porcelain=v1
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/didit-legacy-sessions
git switch feat/didit-legacy-sessions
git pull --ff-only origin feat/didit-legacy-sessions
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

### 3. Publicar `dashboard-seller`

Após enviar o commit do badge “Didit legado” para `feat/didit-legacy-sessions`:

```bash
cd /root/opt/lowify/front/dashboard-seller
git status --porcelain=v1
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/didit-legacy-sessions
git switch feat/didit-legacy-sessions
git pull --ff-only origin feat/didit-legacy-sessions
git rev-parse --short HEAD
```

`dashboard-seller` não usa `docker compose` neste fluxo: a publicação é concluída no `git pull`.

## Validação pós-deploy

1. Em homologação, escolha uma conta PF de teste na fase 1 com selfie ou documento pessoal incompleto e uma sessão Didit prévia. Não use dados reais.
2. Como administrador, faça a migração para fase 2. Confirme que a conta pede novo envio de identidade.
3. Solicite a verificação novamente como seller. Deve abrir uma nova sessão Didit, sem reutilizar o link antigo.
4. Na revisão administrativa, confirme que os documentos antigos continuam disponíveis e recebem “Didit legado”. Eles devem continuar visíveis para revisão/conclusão.
5. Reenvie ou aguarde um webhook da sessão antiga. O seller não deve ter status de identidade, KYC, documentos ou ativação alterados por esse evento.
6. Opcionalmente, conferir nos logs do Account a mensagem de webhook ignorado para a sessão arquivada. Não consuma, limpe ou republique filas manualmente.

## Rollback

1. Interromper novas migrações PF incompletas caso a validação falhe.
2. Reverter o `dashboard-seller` e o `services-account` para os commits anteriores aprovados. Reconstruir somente o container do `services-account`; o Dashboard é atualizado apenas via Git.
3. Não remover `didit_legacy` do ENUM durante um rollback normal: podem existir sessões persistidas com esse valor, e removê-lo exigiria conversão explícita e revisada de dados.
4. Não apagar documentos, sessões, eventos de webhook ou mensagens de fila. Sessões já marcadas como `didit_legacy` permanecem como histórico e devem ser tratadas caso a caso se for necessário reverter seu estado.

## Referências

- [Mapa da feature](../../features/account-phase-one-migration/README.md)
- [PRECHECK.sql](sql/lowify/PRECHECK.sql)
- [DEPLOY.sql](sql/lowify/DEPLOY.sql)
- [VALIDATE.sql](sql/lowify/VALIDATE.sql)
