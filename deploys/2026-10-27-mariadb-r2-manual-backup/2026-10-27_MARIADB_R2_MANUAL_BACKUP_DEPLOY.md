# Deploy — Backup manual do MariaDB para Cloudflare R2

## Objetivo

Disponibilizar no `data_layer` um fluxo manual para enviar ao Cloudflare R2 o backup local já gerado pelo processo existente. O envio não é agendado: cada execução depende de uma ação explícita do operador.

O backup local continua em `/data/backup/db`, com sua retenção atual de oito gerações (`bkp.0.sql.gz` até `bkp.7.sql.gz`). Este deploy não gera, move, remove ou reconfigura backups locais.

Não há alteração em front, edge, JWT, filas, Docker Compose, banco de dados, Redis ou cron.

## Componentes e referências

| Repositório | Diretório de produção | Branch | Commit de referência | Entrega |
| --- | --- | --- | --- | --- |
| `data_layer` | `/opt/lowify/data_layer` | `main` | `9631ef6cb5e005748036c42ca7f6f6618bafaf5e` | Uploader manual para R2 que lê o backup existente em `/data/backup/db`. |

O commit inclui `60aba3bd8fa5e3726b9ecdca65cd31b071610165` como sua dependência imediata.

## Alterações incluídas

- `mariabd/upload_latest_backup_r2.sh` valida `/data/backup/db/bkp.0.sql.gz` e faz upload para R2 via AWS CLI, usando região `auto`.
- `mariabd/backup_mariadb.sh` preserva o diretório e a retenção já usados pelo backup local.
- A configuração R2 é lida exclusivamente de `/opt/lowify/data_layer/mariabd/.env-upload-bkp`; o arquivo é ignorado pelo Git.
- `.env-upload-bkp.example` documenta somente os nomes das variáveis; não contém valores secretos.

## Pré-requisitos

- Execute **todos os comandos deste roteiro como `root`** na VPS de produção. Isso é necessário para acessar `/opt/lowify/data_layer`, `/data/backup/db` e o Docker sem criar arquivos com proprietário ou permissões incorretos.
- Acesso administrativo à VPS de produção e ao repositório `/opt/lowify/data_layer`.
- `aws`, `docker`, `gzip`, `mkdir` e `rmdir` disponíveis no host.
- O container MariaDB em execução com o nome `data-layer-mariadb`.
- Bucket R2 existente e uma credencial S3 com permissão limitada de leitura/escrita ao bucket necessário.

## Configuração do ambiente R2

Execute esta etapa como `root`. O uploader lê exclusivamente o arquivo:

```text
/opt/lowify/data_layer/mariabd/.env-upload-bkp
```

O arquivo não é versionado pelo Git e deve ter permissão `600`. Crie-o somente se ainda não existir; não sobrescreva uma configuração já ativa:

```bash
test -e /opt/lowify/data_layer/mariabd/.env-upload-bkp || install -m 600 /dev/null /opt/lowify/data_layer/mariabd/.env-upload-bkp
chmod 600 /opt/lowify/data_layer/mariabd/.env-upload-bkp
editor /opt/lowify/data_layer/mariabd/.env-upload-bkp
```

No editor seguro, informe os valores fornecidos pelo responsável pelas credenciais:

```dotenv
R2_ACCOUNT_ID=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_BUCKET=
R2_OBJECT_KEY=mariadb/latest.sql.gz
```

Nunca registrar valores de credenciais em terminal compartilhado, Git, ticket ou este documento. Ao concluir a edição, salve o arquivo e mantenha a sessão `root` para os passos de validação e envio.

## Banco de dados

Não há migration, DDL ou DML.

O deploy não executa `mariadb-dump` nem altera o backup local existente. O uploader apenas lê e valida o gzip mais recente antes de transmiti-lo à R2.

## Sequência de deploy

Todos os comandos abaixo devem ser executados na sessão `root` da VPS de produção.

1. Verifique que o repositório está limpo e que a referência remota esperada existe:

   ```bash
   cd /opt/lowify/data_layer
   git status --porcelain=v1
   git fetch origin --prune
   git show-ref --verify --quiet refs/remotes/origin/main
   git show origin/main --format='%H %s' --no-patch
   ```

   Na VPS atualmente conhecida, podem existir estes quatro itens operacionais não rastreados:

   ```text
   redis/.env_redis_secret_rotation.bk
   traefik/.env.bak
   traefik/docker-compose.yml.bak
   traefik/letsencrypt/
   ```

   Preserve-os. Não use `git clean`, `stash`, `reset`, nem mova `traefik/letsencrypt/`, que pode conter certificados ativos. Caso apareça qualquer outro arquivo rastreado ou não rastreado, pare e peça orientação.

   Se o único arquivo rastreado modificado for `mariabd/backup_mariadb.sh` com a mudança manual de `MAX_INDEX=7` para `MAX_INDEX=2`, descarte somente essa cópia local para preservar a retenção atual de oito gerações:

   ```bash
   git restore --source=origin/main -- mariabd/backup_mariadb.sh
   git diff -- mariabd/backup_mariadb.sh
   ```

   O segundo comando não deve produzir saída. Confirme também que os arquivos recebidos de `origin/main` não ocupam os quatro caminhos preservados:

   ```bash
   git diff --name-only HEAD..origin/main
   ```

2. Atualize a branch `main` sem criar merge automático e confira o commit final:

   ```bash
   git switch main
   git pull --ff-only origin main
   git rev-parse HEAD
   ```

   O resultado precisa conter `9631ef6cb5e005748036c42ca7f6f6618bafaf5e` ou um descendente aprovado.

3. Confirme o diretório de backup já existente e suas permissões. Não crie, apague nem mova arquivos de backup nesta etapa:

   ```bash
   test -d /data/backup/db
   stat -c '%U:%G %a %n' /data/backup/db
   ```

   O resultado deve indicar diretório pertencente a `root` e permissão `700`. Se o diretório não existir ou tiver permissão diferente, pare e encaminhe ao responsável pela infraestrutura; não corrija permissões nem recrie backups durante este deploy.

4. Depois de concluir a seção **Configuração do ambiente R2**, confirme a presença do uploader e valide o backup mais recente, já gerado pelo processo de backup existente. Não execute `backup_mariadb.sh` neste deploy:

   ```bash
   test -x mariabd/upload_latest_backup_r2.sh
   test -s /data/backup/db/bkp.0.sql.gz
   gzip -t /data/backup/db/bkp.0.sql.gz
   ```

5. Envie o backup validado para R2. Não reinicie containers e não instale cron:

   ```bash
   bash mariabd/upload_latest_backup_r2.sh
   ```

## Validação pós-deploy

1. Peça ao operador para confirmar que os dois comandos manuais terminaram com sucesso, sem exibir credenciais.
2. Confira que existe um arquivo recente em `/data/backup/db/bkp.0.sql.gz` e que a validação `gzip -t` termina sem mensagem de erro.
3. No painel Cloudflare R2, abra o bucket configurado e confirme que o objeto `mariadb/latest.sql.gz` tem data/hora compatível com a execução e tamanho maior que zero.
4. Confirme que a aplicação permanece acessível normalmente e que o container MariaDB não foi reiniciado.
5. Não execute restauração de banco como parte desta validação.

## Rollback

1. Pare de executar `mariabd/upload_latest_backup_r2.sh`; não apague o objeto já enviado ao R2 nem os backups locais existentes.
2. Mantenha `/opt/lowify/data_layer/mariabd/.env-upload-bkp` protegido até a decisão de segurança sobre revogação das credenciais. Não o versione ou copie para o repositório.
3. Para restaurar o código anterior, crie e publique uma reversão revisada do commit `9631ef6…` e dos commits do uploader no repositório de origem; em produção, atualize `main` pelo mesmo procedimento de `git fetch`, `git switch main` e `git pull --ff-only`.
4. Não apague, mova ou regenere arquivos em `/data/backup/db` como parte do rollback.

## Referências

- `data_layer` — commit `9631ef6cb5e005748036c42ca7f6f6618bafaf5e` e seus ancestrais do uploader.
- `docs/plans/mariadb-r2-backup.md` — intenção inicial; o comportamento efetivamente publicado pelos commits prevalece quando houver divergência de caminho.
