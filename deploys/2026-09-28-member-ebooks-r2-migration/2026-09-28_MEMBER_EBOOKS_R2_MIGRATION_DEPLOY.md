# Deploy — Migração de e-books da Área de Membros para R2

## Objetivo

Migrar os PDFs legados das aulas, atualmente referenciados em `/img/members_area/ebooks/`, para o storage R2. Ao concluir a migração e validar os links públicos, mover os PDFs locais para `/backup/pdfs/` na VPS de produção, removendo-os do volume Docker ativo de forma recuperável.

O escopo é somente `dashboard-seller` e a tabela `lowify.tbl_aulas`. Não há alteração de rotas, JWT, filas, serviços externos além do upload já implementado para R2, nem migration estrutural de banco.

## Componentes e referências

| Repositório | Branch | Referência mínima | Papel |
| --- | --- | --- | --- |
| `dashboard-seller` | `main` | `91c793391e688158ec78abc5b44e8b21a406902e` | Disponibiliza `--help` e `--show-urls` no script de migração. |

O commit de referência está contido em `origin/main`. Nenhum outro repositório deve ser atualizado nesta operação.

## Alterações incluídas

- O script `scripts/process/migrate_aulas_ebooks_to_aws.php` processa uma aula pendente por execução (`pdf_migrate = 0`).
- Cada URL local é enviada para R2 e substituída no JSON `ebook_url`; quando a aula conclui, o script marca `pdf_migrate = 1`.
- A opção `--show-urls` registra somente os pares URL local e URL pública gerada.
- O script marca `pdf_migrate = 2` se uma aula falhar. Não repita automaticamente uma falha sem investigar o arquivo e o registro.

## Pré-requisitos

- Acesso administrativo à VPS de produção e ao banco `lowify`.
- Repositório de produção em `/opt/lowify/front/dashboard-seller` e container `front-dashboard-seller`, confirmados pelo operador antes da execução.
- Variáveis `S3_BUCKET`, `S3_ENDPOINT`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` e `PUBLIC_URL` já configuradas no ambiente da aplicação. Nunca imprimir nem copiar seus valores.
- Espaço livre suficiente em `/backup` para receber todos os PDFs locais.
- `screen` e `rsync` disponíveis na VPS.

### Atenção ao registro de teste

A aula `12970` (produto `18311`) possui URLs locais conhecidas e foi classificada como erro durante um teste anterior. O operador autorizou marcá-la como `pdf_migrate = 1` para removê-la da fila. Isso **não migra nem preserva** seus arquivos locais; após a movimentação para `/backup/pdfs/`, esses links antigos deixarão de servir o arquivo. Execute essa atualização apenas se a aula for realmente descartável.

## Banco de dados

Não há DDL ou migration. O script atualiza `tbl_aulas.ebook_url` e `tbl_aulas.pdf_migrate` por aula concluída.

### Pré-checagem

No cliente MariaDB conectado ao banco `lowify`, executar:

```sql
SELECT
  pdf_migrate,
  COUNT(*) AS total
FROM tbl_aulas
WHERE ebook_url IS NOT NULL
  AND TRIM(CAST(ebook_url AS CHAR)) <> ''
GROUP BY pdf_migrate
ORDER BY pdf_migrate;

SELECT id_aula, id_produto, pdf_migrate, ebook_url
FROM tbl_aulas
WHERE pdf_migrate = 0
  AND ebook_url IS NOT NULL
  AND CAST(ebook_url AS CHAR) LIKE '%/img/members_area/ebooks/%'
ORDER BY id_aula;

SELECT id_aula, id_produto, pdf_migrate, ebook_url
FROM tbl_aulas
WHERE pdf_migrate = 2
ORDER BY id_aula;
```

### Normalização autorizada do teste

Executar somente após confirmar que a aula `12970` é descartável:

```sql
UPDATE tbl_aulas
SET pdf_migrate = 1
WHERE id_aula = 12970
  AND pdf_migrate = 2;

SELECT id_aula, id_produto, pdf_migrate, ebook_url
FROM tbl_aulas
WHERE id_aula = 12970;
```

## Sequência de deploy

1. Pré-checar o repositório de produção. Interromper se houver alteração local ou se a origem não for a esperada:

   ```bash
   cd /opt/lowify/front/dashboard-seller
   git status --porcelain=v1
   git branch --show-current
   git remote get-url origin
   ```

2. Atualizar somente `dashboard-seller` para a `main` e confirmar o suporte ao modo informativo. Não é necessário rebuild: o código do host é montado no container em `/var/www/html`.

   ```bash
   git fetch origin --prune
   git switch main
   git pull --ff-only origin main
   git merge-base --is-ancestor 91c793391e688158ec78abc5b44e8b21a406902e HEAD
   docker exec front-dashboard-seller php /var/www/html/scripts/process/migrate_aulas_ebooks_to_aws.php --help
   ```

   O último comando deve mostrar o uso de `--show-urls` e encerrar sem processar nenhuma aula. Se qualquer comando falhar, interromper a operação.

3. Executar as consultas da seção **Banco de dados**. Resolver cada erro diferente do registro de teste antes de iniciar o lote.

4. Criar uma sessão persistente para a migração:

   ```bash
   screen -S migrate-ebooks
   ```

5. Dentro da `screen`, executar o lote. O laço encerra normalmente quando não houver mais aulas pendentes e interrompe na primeira falha; a saída fica em log local.

   ```bash
   sudo mkdir -p /var/log/lowify
   sudo touch /var/log/lowify/member-ebooks-r2-migration.log
   sudo chown "$USER":"$USER" /var/log/lowify/member-ebooks-r2-migration.log

   while true; do
     output="$(docker exec front-dashboard-seller php /var/www/html/scripts/process/migrate_aulas_ebooks_to_aws.php --show-urls 2>&1)"
     exit_code=$?
     printf '%s\n' "$output" | tee -a /var/log/lowify/member-ebooks-r2-migration.log

     if [ "$exit_code" -ne 0 ]; then
       echo "Migração interrompida por erro; investigar a aula indicada no log."
       break
     fi

     if printf '%s\n' "$output" | grep -q 'Nenhuma aula pendente encontrada para migracao.'; then
       echo "Nenhuma aula pendente; lote concluído."
       break
     fi

     sleep 1
   done
   ```

   Para desacoplar a sessão sem interromper o trabalho: `Ctrl+A`, depois `D`. Para retornar: `screen -r migrate-ebooks`.

6. Quando o laço terminar sem erro, repetir as consultas de pré-checagem. Não mover arquivos locais enquanto houver qualquer aula ativa apontando para `/img/members_area/ebooks/`, salvo a exceção de teste `12970` aprovada explicitamente.

7. Confirmar a origem e medir o volume que será movido. O volume de produção foi confirmado como montagem de `/var/www/html/img`:

   ```bash
   SOURCE_DIR='/var/lib/docker/volumes/dashboard-seller_dashboard_seller_images/_data/members_area/ebooks'
   BACKUP_DIR='/backup/pdfs'

   sudo du -sh "$SOURCE_DIR"
   sudo find "$SOURCE_DIR" -type f -iname '*.pdf' | wc -l
   sudo mkdir -p "$BACKUP_DIR"
   sudo chown root:root "$BACKUP_DIR"
   sudo chmod 750 "$BACKUP_DIR"
   ```

8. Simular a movimentação. Conferir a lista de arquivos antes de continuar:

   ```bash
   sudo rsync -aivn \
     --include='*/' \
     --include='*.pdf' \
     --include='*.PDF' \
     --exclude='*' \
     "$SOURCE_DIR/" "$BACKUP_DIR/"
   ```

9. Executar a movimentação real. `--remove-source-files` remove cada origem somente depois de uma cópia bem-sucedida. Não apagar a pasta de origem.

   ```bash
   sudo rsync -aiv \
     --remove-source-files \
     --include='*/' \
     --include='*.pdf' \
     --include='*.PDF' \
     --exclude='*' \
     "$SOURCE_DIR/" "$BACKUP_DIR/"
   ```

10. Validar a cópia e manter o backup em `/backup/pdfs/` até o período de retenção aprovado pela equipe:

    ```bash
    sudo find "$SOURCE_DIR" -type f -iname '*.pdf' | wc -l
    sudo find "$BACKUP_DIR" -type f -iname '*.pdf' | wc -l
    sudo du -sh "$BACKUP_DIR"
    ```

## Validação pós-deploy

1. Abra o dashboard e entre em uma Área de Membros que tinha e-books locais antes da migração. Baixe ou abra um PDF e confirme que ele carrega pela URL de storage, sem erro.
2. Abra uma aula com mais de um PDF e confirme que todos os arquivos aparecem e abrem normalmente.
3. Confira no banco que não restaram pendências ou erros inesperados:

   ```sql
   SELECT pdf_migrate, COUNT(*) AS total
   FROM tbl_aulas
   WHERE ebook_url IS NOT NULL
     AND TRIM(CAST(ebook_url AS CHAR)) <> ''
   GROUP BY pdf_migrate
   ORDER BY pdf_migrate;
   ```

4. Confirme que o contador de PDFs em `SOURCE_DIR` é `0` e que o contador em `/backup/pdfs/` corresponde à quantidade esperada.
5. Se algum PDF não abrir, interrompa a movimentação de novos arquivos e informe o ID da aula, a URL exibida e o trecho correspondente do log. Não remova objetos do R2.

## Rollback

1. Para restaurar PDFs locais após uma movimentação, interrompa novos uploads e copie os arquivos de volta, preservando o backup:

   ```bash
   sudo rsync -aiv /backup/pdfs/ /var/lib/docker/volumes/dashboard-seller_dashboard_seller_images/_data/members_area/ebooks/
   ```

2. Não reverta `ebook_url` de URLs R2 para URLs locais: os uploads já concluídos no R2 permanecem válidos e devem ser preservados.
3. Não apague `/backup/pdfs/`, o volume Docker ou objetos R2 como parte do rollback. A retenção e eventual remoção exigem aprovação posterior.
4. Registros em `pdf_migrate = 2` devem ser corrigidos caso a caso; não zerar o status em massa.
