# Operação — Arquivamento de PDFs locais já migrados

## Objetivo

Os PDFs da Área de Membros já foram migrados e validados no storage R2. Esta operação move os PDFs locais do volume Docker ativo para `/backup/pdfs/`. Cada PDF é removido da origem somente após uma cópia bem-sucedida.

Não há atualização de branch, deploy de código, Docker build, alteração de banco, rota, JWT ou fila nesta etapa.

## Escopo confirmado

| Item | Caminho |
| --- | --- |
| Origem no host | `/var/lib/docker/volumes/dashboard-seller_dashboard_seller_images/_data/members_area/ebooks` |
| Caminho no container | `/var/www/html/img/members_area/ebooks` |
| Backup | `/backup/pdfs` |

A operação move somente arquivos `.pdf` e `.PDF`.

## Pré-requisitos

- A migração para R2 e os downloads já foram validados.
- A VPS possui `screen`, `rsync`, `find` e espaço livre suficiente em `/backup`.
- O operador possui acesso `sudo`.
- Manter `/backup/pdfs/` até aprovação posterior; não apagar o backup nesta operação.

## Sequência de execução

1. Fora de uma `screen`, definir os caminhos, medir a origem e selecionar um PDF para o teste inicial:

   ```bash
   SOURCE_DIR=/var/lib/docker/volumes/dashboard-seller_dashboard_seller_images/_data/members_area/ebooks
   BACKUP_DIR=/backup/pdfs

   sudo du -sh "$SOURCE_DIR"
   sudo find "$SOURCE_DIR" -type f -iname "*.pdf" | wc -l
   sudo mkdir -p "$BACKUP_DIR"
   sudo chown root:root "$BACKUP_DIR"
   sudo chmod 750 "$BACKUP_DIR"

   TEST_FILE="$(sudo find "$SOURCE_DIR" -type f -iname "*.pdf" -print -quit)"
   test -n "$TEST_FILE" || { echo Nenhum PDF encontrado na origem; exit 1; }
   TEST_RELATIVE_PATH="${TEST_FILE#"$SOURCE_DIR/"}"
   ```

2. Mover somente o PDF de teste. Esta etapa não usa `screen`:

   ```bash
   sudo mkdir -p "$BACKUP_DIR/$(dirname "$TEST_RELATIVE_PATH")"
   sudo rsync -aiv --remove-source-files \
     "$TEST_FILE" "$BACKUP_DIR/$TEST_RELATIVE_PATH"

   sudo test ! -f "$TEST_FILE"
   sudo test -f "$BACKUP_DIR/$TEST_RELATIVE_PATH"
   ```

3. Abra a Área de Membros e confirme que o PDF de teste continua abrindo pela URL do R2. Se não abrir, execute o rollback e não mova os demais arquivos.

4. Somente após esse sucesso, criar uma sessão persistente para o lote restante:

   ```bash
   screen -S move-member-pdfs
   ```

5. Dentro da `screen`, simular a movimentação dos PDFs restantes. Este comando não altera arquivos; revisar a lista:

   ```bash
   sudo rsync -aivn \
     --include="*/" \
     --include="*.pdf" \
     --include="*.PDF" \
     --exclude="*" \
     "$SOURCE_DIR/" "$BACKUP_DIR/"
   ```

6. Executar a movimentação real dos PDFs restantes:

   ```bash
   sudo rsync -aiv \
     --remove-source-files \
     --include="*/" \
     --include="*.pdf" \
     --include="*.PDF" \
     --exclude="*" \
     "$SOURCE_DIR/" "$BACKUP_DIR/"
   ```

7. Validar o resultado:

   ```bash
   echo PDFs restantes no volume:
   sudo find "$SOURCE_DIR" -type f -iname "*.pdf" | wc -l

   echo PDFs arquivados:
   sudo find "$BACKUP_DIR" -type f -iname "*.pdf" | wc -l
   sudo du -sh "$BACKUP_DIR"
   ```

   O contador da origem deve ser `0`. Não apagar a pasta de origem, mesmo vazia.

8. Para desacoplar a screen sem interromper, pressionar `Ctrl+A` e depois `D`. Para retornar:

   ```bash
   screen -r move-member-pdfs
   ```

## Rollback

Se o PDF de teste não abrir ou ocorrer falha posterior, repor os PDFs no volume sem apagar o backup:

```bash
sudo rsync -aiv \
  /backup/pdfs/ \
  /var/lib/docker/volumes/dashboard-seller_dashboard_seller_images/_data/members_area/ebooks/
```

Depois, testar o download afetado. Não alterar URLs, banco ou remover o backup durante a investigação.
