# Deploy — Backup manual do MariaDB para Cloudflare R2

## Objetivo

Disponibilizar no `data_layer` um fluxo manual para gerar o backup compactado do MariaDB e enviá-lo ao Cloudflare R2. O envio não é agendado: cada execução depende de uma ação explícita do operador.

O escopo também limita a retenção local a três arquivos de backup (`bkp.0.sql.gz`, `bkp.1.sql.gz` e `bkp.2.sql.gz`) e mantém os arquivos gerados fora do repositório Git.

Não há alteração em front, edge, JWT, filas, Docker Compose, banco de dados, Redis ou cron.

## Componentes e referências

| Repositório | Diretório de produção | Branch | Commit de referência | Entrega |
| --- | --- | --- | --- | --- |
| `data_layer` | `/opt/lowify/data_layer` | `main` | `d6cd2d0d21fa2ba89e751753c1035fea6c5ea1db` | Uploader manual para R2, configuração externa no diretório do repositório e retenção de três backups. |

O commit inclui `60aba3bd8fa5e3726b9ecdca65cd31b071610165` como sua dependência imediata.

## Alterações incluídas

- `mariabd/backup_mariadb.sh` passa a gravar backups em `/var/lib/lowify/mariadb-backups` e mantém três gerações.
- `mariabd/upload_latest_backup_r2.sh` valida o arquivo gzip e faz upload para R2 via AWS CLI, usando região `auto`.
- A configuração R2 é lida exclusivamente de `/opt/lowify/data_layer/.env-upload-bkp`; o arquivo é ignorado pelo Git.
- `.env-upload-bkp.example` documenta somente os nomes das variáveis; não contém valores secretos.

## Pré-requisitos

- Execute **todos os comandos deste roteiro como `root`** na VPS de produção. Isso é necessário para acessar `/opt/lowify/data_layer`, `/var/lib/lowify/mariadb-backups` e o Docker sem criar arquivos com proprietário ou permissões incorretos.
- Acesso administrativo à VPS de produção e ao repositório `/opt/lowify/data_layer`.
- `aws`, `docker`, `gzip`, `mkdir` e `rmdir` disponíveis no host.
- O container MariaDB em execução com o nome `data-layer-mariadb`.
- Bucket R2 existente e uma credencial S3 com permissão limitada de leitura/escrita ao bucket necessário.
- Definição segura dos valores de `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` e, opcionalmente, `R2_OBJECT_KEY` em `/opt/lowify/data_layer/.env-upload-bkp`. Nunca registrar os valores em terminal compartilhado, Git, ticket ou este documento.

## Banco de dados

Não há migration, DDL ou DML.

O script executa um dump consistente de todos os bancos com `mariadb-dump --single-transaction`; ele não altera tabelas nem reinicia o container. O backup local anterior somente é rotacionado depois que um novo gzip íntegro é gerado.

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

   Se o único arquivo rastreado modificado for `mariabd/backup_mariadb.sh` com a mudança manual de `MAX_INDEX=7` para `MAX_INDEX=2`, descarte somente essa cópia local, pois a mesma retenção já está publicada:

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

   O resultado precisa conter `d6cd2d0d21fa2ba89e751753c1035fea6c5ea1db` ou um descendente aprovado.

3. Confirme o diretório externo de backups já existente e suas permissões. Não crie, apague nem mova arquivos de backup nesta etapa:

   ```bash
   test -d /var/lib/lowify/mariadb-backups
   stat -c '%U:%G %a %n' /var/lib/lowify/mariadb-backups
   ```

   O resultado deve indicar diretório pertencente a `root` e permissão `700`. Se o diretório não existir ou tiver permissão diferente, pare e encaminhe ao responsável pela infraestrutura; não corrija permissões nem recrie backups durante este deploy.

4. Crie, se ainda não existir, `/opt/lowify/data_layer/.env-upload-bkp` com permissão `600` e preencha apenas as variáveis R2 previstas. Não copie valores para o histórico do shell:

   ```bash
   test -e /opt/lowify/data_layer/.env-upload-bkp || install -m 600 /dev/null /opt/lowify/data_layer/.env-upload-bkp
   chmod 600 /opt/lowify/data_layer/.env-upload-bkp
   editor /opt/lowify/data_layer/.env-upload-bkp
   ```

5. Confirme a presença dos scripts e faça a primeira geração manual do backup. Esse comando pode levar alguns minutos, conforme o tamanho do banco:

   ```bash
   test -x mariabd/backup_mariadb.sh
   test -x mariabd/upload_latest_backup_r2.sh
   bash mariabd/backup_mariadb.sh
   gzip -t /var/lib/lowify/mariadb-backups/bkp.0.sql.gz
   ```

6. Envie o backup validado para R2. Não reinicie containers e não instale cron:

   ```bash
   bash mariabd/upload_latest_backup_r2.sh
   ```

## Validação pós-deploy

1. Peça ao operador para confirmar que os dois comandos manuais terminaram com sucesso, sem exibir credenciais.
2. Confira que existe um arquivo recente em `/var/lib/lowify/mariadb-backups/bkp.0.sql.gz` e que a validação `gzip -t` termina sem mensagem de erro.
3. No painel Cloudflare R2, abra o bucket configurado e confirme que o objeto `mariadb/latest.sql.gz` tem data/hora compatível com a execução e tamanho maior que zero.
4. Confirme que a aplicação permanece acessível normalmente e que o container MariaDB não foi reiniciado.
5. Não execute restauração de banco como parte desta validação.

## Rollback

1. Pare de executar `mariabd/upload_latest_backup_r2.sh`; não apague o objeto já enviado ao R2 nem os backups locais existentes.
2. Mantenha `/opt/lowify/data_layer/.env-upload-bkp` protegido até a decisão de segurança sobre revogação das credenciais. Não o versione ou copie para o repositório.
3. Para restaurar o código anterior, crie e publique uma reversão revisada dos commits `d6cd2d0…`, `b07254e…` e `60aba3b…` no repositório de origem; em produção, atualize `main` pelo mesmo procedimento de `git fetch`, `git switch main` e `git pull --ff-only`.
4. Antes de voltar a gerar backups após a reversão, confirme o diretório de destino do script restaurado. Não apague `/var/lib/lowify/mariadb-backups` como parte do rollback.

## Referências

- `data_layer` — commits `60aba3bd8fa5e3726b9ecdca65cd31b071610165` e `b07254eb8a202ba8118b13aa632f0c626b853866`.
- `docs/plans/mariadb-r2-backup.md` — intenção inicial; o comportamento efetivamente publicado pelos commits prevalece quando houver divergência de caminho.
