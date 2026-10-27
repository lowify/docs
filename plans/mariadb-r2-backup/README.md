# Backup MariaDB com envio manual para Cloudflare R2

## Escopo mínimo

O backup continua no `data_layer/mariabd`. Não criar projeto, pasta de ferramenta, cron ou segundo fluxo de backup.

As únicas adições são:

- reter três backups locais no script existente;
- criar o uploader manual `data_layer/mariabd/upload_latest_backup_r2.sh`;
- criar o arquivo de configuração separado `data_layer/mariabd/.env-upload-bkp`.

O `.env` do MariaDB não deve ser alterado nem lido pelo uploader.

## Retenção do backup atual

`data_layer/mariabd/backup_mariadb.sh` usa `MAX_INDEX=2`. Como a rotação começa no índice zero, mantém exatamente:

```text
bkp.0.sql.gz  # backup mais recente
bkp.1.sql.gz
bkp.2.sql.gz  # backup mais antigo preservado
```

O cron atual que gera o dump permanece inalterado. Não reiniciar o container MariaDB nem modificar Docker, volumes ou configuração do banco.

## Ferramenta de envio R2

Como solução provisória, a ferramenta é um único arquivo dentro do próprio diretório MariaDB:

```text
data_layer/mariabd/upload_latest_backup_r2.sh
```

Ela é separada do script de geração (`backup_mariadb.sh`) e serve somente ao envio manual. Não criar uma pasta ou projeto adicional enquanto esse serviço estiver ativo.

## Configuração do R2

Criar manualmente, no mesmo diretório dos scripts, o arquivo não versionado:

```text
data_layer/mariabd/.env-upload-bkp
```

Partir de `.env-upload-bkp.example`:

```dotenv
R2_ACCOUNT_ID=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_BUCKET=
R2_OBJECT_KEY=mariadb/latest.sql.gz
```

Em homologação, preencher esse arquivo com as credenciais R2 já usadas pelo serviço de monitoramento na VPS, sem imprimir, alterar ou reiniciar esse serviço. Em produção, preencher pelo procedimento seguro aplicável.

O arquivo `.env-upload-bkp` deve ficar ignorado pelo Git e com acesso restrito ao usuário operacional.

## Envio manual

Após a geração de `bkp.0.sql.gz`, executar:

```bash
bash /caminho/do/data_layer/mariabd/upload_latest_backup_r2.sh
```

O uploader:

- carrega somente `.env-upload-bkp`;
- lê `data_layer/mariabd/db_backups/bkp.0.sql.gz` por padrão;
- valida o gzip antes de acessar a rede;
- envia apenas para `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
- usa `s3://${R2_BUCKET}/${R2_OBJECT_KEY}` como destino;
- usa lock próprio e não altera os arquivos `bkp.*`.

Não criar cron para esse envio. Não colocar credencial do MariaDB no arquivo de R2; o uploader não usa Docker nem se conecta ao banco.
