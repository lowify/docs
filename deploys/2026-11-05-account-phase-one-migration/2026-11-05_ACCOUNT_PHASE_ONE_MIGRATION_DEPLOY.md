# Deploy — migração de contas da fase 1 para a fase 2

## Objetivo

Publicar um migrador administrativo e canônico para promover sellers da fase 1
para a fase 2. A execução é restrita a administradores e a lotes explícitos;
ela não migra contas automaticamente durante o deploy.

A migração passa pelo Dashboard, Gateway e Public API até o Account, que
valida documentos pessoais, prepara KYC de sócios quando aplicável e atualiza
o cache de completude. Checkout no Commerce V2 não é alterado nesta entrega.

## Componentes e referências

| Repositório | Diretório na VPS | Branch de deploy | Commit |
| --- | --- | --- | --- |
| `services-account` | `/opt/lowify/services/services-account` | `feat/account-phase-one-migration` | `96f393764478e983c5fda87d4f446de49c0136e6` |
| `edge-public-api` | `/opt/lowify/edge/edge-public-api` | `feat/account-phase-one-migration` | `293bc896266f2c5eb535bec606e1f687b15c17c7` |
| `edge-gateway` | `/opt/lowify/edge/edge-gateway` | `feat/account-phase-one-migration` | `2c12e2336e59f55f7fbac2607a08182ef3fe2258` |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `feat/account-phase-one-migration` | `a3f2327d228cc0a985ba1fa3896edf0f6bccc7fc` |

## Alterações incluídas

1. O Account expõe internamente `POST /admin/users/{user_id}/phase-one-migration`.
2. O Public API valida JWT administrativo (`permissao` 1, 2 ou 4) e encaminha
   a rota; o Gateway encaminha a mesma rota ao Public API.
3. O Dashboard conserva a permissão `user_migrate_v2`, mas deixa de modificar
   diretamente os dados de migração; ele consulta/executa pelo endpoint.
4. Para PF, a migração preserva dados pessoais, define `pj_migrate=127` quando
   ainda era zero e marca identidade como pendente se selfie e documento
   pessoal não estiverem completos.
5. Para PJ com CNPJ, a migração usa `pj_migrate=1`. Para PJ legada com CPF,
   cria sócio, usa `pj_migrate=10` e replica os documentos pessoais enviados
   para o contexto do sócio.
6. A migração deixa `account_review_status` nulo. O fluxo de completude cria a
   revisão no momento correto. O cache é invalidado antes da promoção para
   impedir saque com estado anterior; o worker grava cache positivo apenas
   depois de a revisão estar aprovada.
7. O comando operacional é:

```bash
php bin/hyperf.php account-phase:migrate-phase-one --user-ids=2200,2201
php bin/hyperf.php account-phase:migrate-phase-one --user-ids=2200,2201 --apply
```

Sem `--apply`, o comando é apenas prévia. Ele não seleciona todos os sellers
implicitamente.

## Pré-requisitos

1. Confirmar que os quatro diretórios estão limpos antes da troca de branch.
   Se `git status --porcelain=v1` apresentar linhas, parar e preservar o
   trabalho local.
2. Confirmar saúde do Account e que o processo
   `PROFILE_COMPLETION_REFRESH_PROCESS_ENABLED` está ativo. Ele consome a fila
   `accounts:complete:refresh` após cada migração.
3. Usar uma conta administrativa com permissão `user_migrate_v2` para a ação
   pelo Dashboard. A API também exige JWT com permissão administrativa.
4. Preparar uma lista explícita de IDs de sellers para o primeiro lote. Não
   executar o comando de aplicação em toda a base sem a prévia revisada.
5. Não alterar segredos, não limpar Redis e não manipular mensagens das filas
   manualmente durante esta operação.

## Banco de dados

Não há migration, DDL ou DML de deploy. As alterações de `tbl_usuarios`,
`user_partner`, `documents` e `user_verification_sessions` ocorrem somente
quando um lote explícito é executado pelo comando ou pela rota administrativa.

## Sequência de deploy

Modo de rebuild: incremental. Atualizar na ordem abaixo para que a rota tenha
sempre um destino disponível antes de o Dashboard apresentá-la.

### 1. `services-account`

```bash
cd /opt/lowify/services/services-account
git status --porcelain=v1
git fetch origin --prune
git switch feat/account-phase-one-migration
git pull --ff-only origin feat/account-phase-one-migration
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

### 2. `edge-public-api`

```bash
cd /opt/lowify/edge/edge-public-api
git status --porcelain=v1
git fetch origin --prune
git switch feat/account-phase-one-migration
git pull --ff-only origin feat/account-phase-one-migration
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

### 3. `edge-gateway`

```bash
cd /opt/lowify/edge/edge-gateway
git status --porcelain=v1
git fetch origin --prune
git switch feat/account-phase-one-migration
git pull --ff-only origin feat/account-phase-one-migration
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

### 4. `dashboard-seller`

```bash
cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git fetch origin --prune
git switch feat/account-phase-one-migration
git pull --ff-only origin feat/account-phase-one-migration
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

## Testes de compatibilidade em homologação

Executor: ambiente publicado do `dashboard-seller`, com uma conta de teste PF
da fase 1 que possua saldo e uma conta PJ-CNPJ/PJ-CPF de teste, sem dados de
clientes reais.

1. Faça login como administrador autorizado e abra o overview de um seller da
   fase 1. A ação exibida deve ser “Migrar para fase 2”.
2. Solicite a prévia. Ela deve informar o tipo de migração, o valor final de
   `pj_migrate` e se documentos pessoais estão completos, sem alterar a conta.
3. Confirme a migração de uma PF com documento faltando. O seller deve acessar
   “Completar cadastro”, ver a solicitação de documento e não conseguir pedir
   saque.
4. Complete documentos e cadastro da conta de teste. A conta deve entrar na
   revisão; o saque continua bloqueado até a aprovação administrativa.
5. Aprove a revisão e confirme que o saque passa a estar disponível. Crie uma
   venda ou checkout de teste antes e depois: a fase 2 não deve bloquear o
   checkout do Commerce V2.
6. Repita com PJ-CPF e confirme que o sócio aparece com KYC pendente quando
   documentos estiverem faltando. Repita com PJ-CNPJ e confirme que o cadastro
   pede sócio/documentação empresarial quando esses dados não existirem.

Como conferência técnica opcional, verificar os logs do Account para o refresh
enfileirado na chave `accounts:complete:refresh`; não consumir, limpar ou
republicar a fila manualmente.

## Validação pós-deploy

1. Faça login como administrador e abra um seller da fase 1. Confirme que a
   opção de migração aparece somente para contas nessa fase.
2. Abra a prévia antes de confirmar. A tela deve informar que saque ficará
   bloqueado até cadastro completo e revisão aprovada.
3. Após confirmar, atualize a página do seller. A conta deve aparecer na fase
   2 e o botão “Completar cadastro” deve abrir normalmente.
4. Entre como o seller de teste e abra o saldo. A opção de saque deve aparecer
   indisponível até a revisão ser aprovada.
5. Se a tela mostrar erro de migração, não repita em massa. Registre o ID do
   seller e execute primeiro a prévia do comando no Account para investigar.

## Rollback

1. Interromper novos lotes e ocultar o uso administrativo da migração, se
   necessário.
2. Reverter código na ordem: Dashboard, Gateway, Public API e Account, sempre
   para a revisão anterior aprovada de cada repositório.
3. Não apagar documentos, sócios, sessões de verificação, reviews ou mensagens
   da fila. A migração de dados já aplicada não é revertida automaticamente;
   cada seller afetado requer análise e correção controlada.
4. Após rollback de código, não executar o comando de migração até a causa do
   incidente estar resolvida.

## Referências

- `services-account/app/Application/UseCase/AccountMigration/MigratePhaseOneAccountUseCase.php`
- `services-account/app/Command/AccountPhaseOneMigrationCommand.php`
- `edge-public-api/routes/api.php`
- `edge-gateway/config/routes.php`
- `dashboard-seller/includes/user/migrate.php`
