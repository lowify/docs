# Deploy — correções de PIX Automático e reprocessamento de extrato

## Objetivo

Corrigir o processamento de cobranças PIX Automático para que a data de confirmação não seja deslocada para o futuro e para que o lançamento de saldo do seller seja aceito pelo Wallet.

Também disponibilizar um comando de reprocessamento de extratos para vendas PIX Automático já confirmadas que não receberam o crédito.

## Componentes e commits

| Componente | Branch | Commit | Correção |
| --- | --- | --- | --- |
| `services-banking` | `feat/pix-automatic-commerce-v2` | `5a1bc5b` | Interpreta o `updated_at` da cobrança em UTC e serializa o `paid_at` em `America/Sao_Paulo`. |
| `service-commerce-v2` | `feat/pix-automatic-commerce-v2` | `87ec420` | Normaliza timestamps ISO 8601 para `Y-m-d H:i:s` antes de enviar o lançamento ao Wallet. |
| `service-commerce-v2` | `feat/pix-automatic-commerce-v2` | `15284c7` | Adiciona o comando de reprocessamento de extrato para PIX Automático. |

O fluxo corrigido é:

```text
Banking (paid_at correto)
  -> sales:subscriptions:actions
  -> Commerce V2 (venda paga)
  -> wallet:extract:events (created_at em Y-m-d H:i:s)
  -> Wallet (extrato e saldo do seller)
```

## Atualização dos serviços

Antes de executar, confirmar que ambos os repositórios estão na branch `feat/pix-automatic-commerce-v2` e sem alterações locais.

### Banking

```bash
cd /opt/lowify/services/services-banking/
git pull
docker compose up -d --build --force-recreate \
  services-banking-app services-banking
```

### Commerce V2

```bash
cd /opt/lowify/services/service-commerce-v2/
git pull
docker compose up -d --build
```

## Reprocessamento de extratos PIX Automático

O comando seleciona somente vendas com:

- `status = paid`;
- `payment_method = pix_automatic`;
- `confirmed_at` dentro do intervalo informado.

Ele recalcula o valor líquido do seller com base nos itens, taxa do seller, order bump e comissão de afiliado. O reenvio produz o mesmo identificador de evento normal: `sale-approved:seller:<sale_id>`.

A constraint única já existente no banco do Wallet impede a duplicação do lançamento quando uma venda já possuir o crédito correspondente.

Primeiro, executar sem `--execute` para conferir a quantidade afetada:

```bash
cd /opt/lowify/services/service-commerce-v2/
docker compose exec -T service-commerce-v2 php bin/hyperf.php \
  woovi:backfill-pix-automatic-wallet-extract \
  "2026-09-09 22:30:00" "2026-09-10 23:59:59"
```

Para reenfileirar os créditos após conferir a saída:

```bash
cd /opt/lowify/services/service-commerce-v2/
docker compose exec -T service-commerce-v2 php bin/hyperf.php \
  woovi:backfill-pix-automatic-wallet-extract \
  "2026-09-09 22:30:00" "2026-09-10 23:59:59" \
  --execute
```

## Validação

1. Confirmar que o resumo final do comando possui `failed=0`.
2. Para cada venda reenfileirada, confirmar no Wallet os lançamentos esperados da venda e a atualização do saldo do seller.
3. Confirmar que uma nova venda PIX Automático cria o extrato sem ir para DLQ.
4. Consultar os logs caso haja falha:

   ```bash
   cd /opt/lowify/services/service-commerce-v2/
   docker compose logs --tail=200 service-commerce-v2
   ```

## Rollback

Não há migration nem alteração de dados estrutural neste deploy. Se for necessário interromper o reprocessamento, não execute novas chamadas com `--execute`.

Para voltar o código, retornar cada serviço à revisão anterior aprovada e reconstruir o respectivo container. Não limpar filas Redis nem apagar extratos já criados.
