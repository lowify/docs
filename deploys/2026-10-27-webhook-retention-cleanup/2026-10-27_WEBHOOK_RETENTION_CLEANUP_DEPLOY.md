# Deploy — retenção de webhooks processados

## Objetivo

Publicar a limpeza automática de registros antigos em `services-webhook.webhook_raws`, executada diariamente entre 02:00 e 03:00 no fuso `America/Sao_Paulo`.

Somente webhooks com status final `success` ou `fail` e mais de 10 dias serão removidos. Webhooks `pending` e `processing` permanecem preservados. A entrega não altera rotas, contratos HTTP, filas ou o processamento de webhooks novos.

## Componentes e referências

| Repositório | Branch de deploy | Commit | Caminho de produção |
| --- | --- | --- | --- |
| `edge-webhook` | `feat/webhook-retention-cleanup` | `ae5884a` | `/opt/lowify/edge/edge-webhook` |

## Alterações incluídas

- Adiciona o processo supervisionado `webhook:retention-cleanup` ao container `edge-webhook`.
- Remove em lotes de até 1.000 registros, com até cinco lotes consecutivos por turno e pausa de 500 ms entre lotes, durante a janela diária configurada.
- Cria o índice `webhook_raws_retention_lookup_index` em `(status, created_at, id)` para localizar registros elegíveis sem varrer toda a tabela.
- Mantém opções de configuração por ambiente, mas nenhuma variável nova é obrigatória: os defaults habilitam retenção de 10 dias, exclusão real e janela das 02:00 às 03:00.

## Pré-requisitos

1. Confirmar que o MariaDB usado por `edge-webhook` está saudável e que há espaço em disco para criar o índice adicional.
2. Confirmar que o host está no fuso esperado ou que a aplicação respeita `America/Sao_Paulo`; a janela da rotina é avaliada nesse fuso.
3. Não é necessário adicionar variáveis ao `.env` para o comportamento padrão. Caso a operação exija outro período, janela ou limite, definir as variáveis `WEBHOOK_RETENTION_CLEANUP_*` antes do rebuild, sem registrar valores sensíveis.
4. Publicar fora da janela das 02:00 às 03:00 quando possível. Se a publicação ocorrer dentro dela, a rotina poderá iniciar após o container subir e apagar registros elegíveis.

## Ajuste de banco

Aplicar a migration `2026_10_27_000002_add_retention_index_to_webhook_raws_table.php` antes de iniciar o novo container. Ela cria somente o índice `webhook_raws_retention_lookup_index`; não remove nem altera registros.

Precheck opcional antes da publicação:

```sql
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS total_mb,
    ROUND(DATA_FREE / 1024 / 1024, 2) AS livre_interno_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'services-webhook'
  AND TABLE_NAME = 'webhook_raws';
```

## Sequência de deploy

1. No host de produção, abrir o diretório do repositório:

   ```bash
   cd /opt/lowify/edge/edge-webhook
   git fetch origin --prune
   git switch feat/webhook-retention-cleanup
   git pull --ff-only origin feat/webhook-retention-cleanup
   ```

2. Construir a imagem sem iniciar ainda o novo processo de retenção:

   ```bash
   cd /opt/lowify/edge/edge-webhook
   docker compose build edge-webhook
   ```

3. Aplicar a migration usando a imagem recém-construída:

   ```bash
   cd /opt/lowify/edge/edge-webhook
   docker compose run --rm edge-webhook php artisan migrate --force
   ```

4. Iniciar o container com a nova imagem. O Supervisor inicia o worker atual de `webhook-processing`, o consumidor EFI existente e o novo processo de retenção:

   ```bash
   cd /opt/lowify/edge/edge-webhook
   docker compose up -d edge-webhook
   docker compose ps
   ```

## Validação pós-deploy

1. Abra `https://webhook.lowify.com.br/api/health` no navegador. Deve aparecer a confirmação de que o serviço está disponível.
2. Envie um webhook de teste por um provedor já configurado e confirme no respectivo painel que ele foi aceito. O comportamento deve permanecer igual ao anterior; a limpeza não altera endpoints nem respostas.
3. Aguarde a próxima janela entre 02:00 e 03:00. Depois, confirme com a equipe técnica que o volume de registros com mais de 10 dias começou a reduzir gradualmente. Registros recentes e pendentes devem permanecer disponíveis.

Como conferência técnica opcional, verificar os logs do container após a janela:

```bash
cd /opt/lowify/edge/edge-webhook
docker compose logs --since=2h edge-webhook
```

Procurar entradas de `Webhook retention cleanup batch completed` com `dry_run=false`, além de `selected` e `deleted` maiores que zero quando houver registros elegíveis.

## Rollback

1. Interromper novas exclusões retornando o container à `main`:

   ```bash
   cd /opt/lowify/edge/edge-webhook
   git fetch origin --prune
   git switch main
   git pull --ff-only origin main
   docker compose up -d --build edge-webhook
   ```

2. Não remover o índice `webhook_raws_retention_lookup_index` durante o rollback; ele é compatível com a versão anterior e sua remoção acrescentaria carga desnecessária ao banco.
3. Registros que já tenham sido excluídos pela retenção não podem ser restaurados por esse rollback. Recuperação de dados, se necessária, deve usar o backup aprovado do banco e um plano específico; não apagar filas Redis nem outros registros de webhook como parte da reversão.
