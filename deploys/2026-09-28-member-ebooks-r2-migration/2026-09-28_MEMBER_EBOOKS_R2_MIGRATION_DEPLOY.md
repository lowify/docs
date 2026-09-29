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

1. Abrir uma sessão persistente:

   ```bash
   screen -S move-member-pdfs
   ```

2. Dentro da screen, definir os caminhos e conferir o volume:

   ```bash
   SOURCE_DIR=/var/lib/docker/volumes/dashboard-seller_dashboard_seller_images/_data/members_area/ebooks
   BACKUP_DIR=/backup/pdfs

   sudo du -sh "$SOURCE_DIR"
   sudo find "$SOURCE_DIR" -type f -iname "*.pdf" | wc -l
   sudo mkdir -p "$BACKUP_DIR"
   sudo chown root:root "$BACKUP_DIR"
   sudo chmod 750 "$BACKUP_DIR"
   ```

3. Simular a movimentação. Este comando não altera arquivos; revisar a lista retornada:

   ```bash
   sudo rsync -aivn \
     --include="*/" \
     --include="*.pdf" \
     --include="*.PDF" \
     --exclude="*" \
     "$SOURCE_DIR/" "$BACKUP_DIR/"
   ```

4. Executar a movimentação real:

   ```bash
   sudo rsync -aiv \
     --remove-source-files \
     --include="*/" \
     --include="*.pdf" \
     --include="*.PDF" \
     --exclude="*" \
     "$SOURCE_DIR/" "$BACKUP_DIR/"
   ```

5. Validar o resultado:

   ```bash
   echo PDFs restantes no volume:
   sudo find "$SOURCE_DIR" -type f -iname "*.pdf" | wc -l

   echo PDFs arquivados:
   sudo find "$BACKUP_DIR" -type f -iname "*.pdf" | wc -l
   sudo du -sh "$BACKUP_DIR"
   ```

   O contador da origem deve ser `0`. Não apagar a pasta de origem, mesmo vazia.

6. Para desacoplar a screen sem interromper, pressionar `Ctrl+A` e depois `D`. Para retornar:

   ```bash
   screen -r move-member-pdfs
   ```

## Validação pós-operação

1. Abra uma Área de Membros com e-book e confirme que o PDF abre pela URL do storage R2.
2. Abra uma aula com vários PDFs e confirme que todos os downloads continuam funcionando.
3. Confirme que a origem não possui PDFs e que os arquivos estão em `/backup/pdfs/`.
4. Se um download falhar, interrompa novas movimentações e execute o rollback. Não remova objetos do R2.

## Rollback

Para repor os PDFs no volume, mantendo o backup:

```bash
sudo rsync -aiv \
  /backup/pdfs/ \
  /var/lib/docker/volumes/dashboard-seller_dashboard_seller_images/_data/members_area/ebooks/
```

Depois, teste o download que apresentou falha. Não alterar URLs, banco ou remover o backup durante a investigação.
