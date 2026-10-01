# Atualização complementar — Comunicações de venda e PIX Automático

## Escopo

Esta atualização reúne correções posteriores ao deploy inicial de Comunicações de Venda. Todos os commits abaixo estão na branch `feat/sale-notifications`.

## Dashboard Seller

Repositório: `front/dashboard-seller`

| Commit | Alteração |
| --- | --- |
| `03b433f8f27af9705cbf1c0141d3075bfd03064c` | Ajusta a apresentação das cobranças pendentes nas telas de créditos e extrato de comunicação. O primeiro e-mail de entrega continua exibido como gratuito; demais envios sem cobrança exibem o valor aplicável como não cobrado. |
| `30ae74e5570b9cad761d8edd121e417dae5aa8d1` | Mantém o contrato esperado pelo app mobile: `saldo_disponivel` e `total_sacado`. A rota `saqueapp.php` passa a usar o cálculo local compatível com a Wallet; `api/balance.php` também expõe `total_sacado` como alias de compatibilidade. |

### Atualização na VPS

```bash
cd /opt/lowify/front/dashboard-seller
git pull
```

O Dashboard Seller é PHP servido diretamente; não requer `docker compose up --build`.

## Commerce V2

Repositório: `services/service-commerce-v2`

Inclui `71f4fd5979fae6e82c1ff5e49540b2e4ad1c9392` e todos os commits posteriores:

| Commit | Alteração |
| --- | --- |
| `71f4fd5979fae6e82c1ff5e49540b2e4ad1c9392` | Registra o envio de e-mail de entrega também quando o WhatsApp retorna resultado, preservando o histórico de comunicação. |
| `73712a6715d12a7f24219494cadca3b4bbf8ffef` | Mantém o bloqueio financeiro do WhatsApp até confirmação `delivered` ou `read`; aceite pelo provedor não consome crédito. |
| `455771992fe8ab6ed34849915a0f4c50336593c5` | Bloqueia o crédito/saldo de recuperação de venda já no agendamento. |
| `b29f670c17cbedf56fcb9c75970cd5fa953a333c` | Libera bloqueios de recuperação quando a venda é paga. |
| `7a90d7f978b34fdc7336e71edbcc48e1797ccf98` | Repara casos já cancelados que ainda permaneciam com bloqueio financeiro. |
| `76e17da4b1c580466c82db13037c7d844ac49613` | Corrige parcelas recorrentes do PIX Automático: novas parcelas nascem pelo valor bruto, recebem `order_id` curto no padrão `ord_...` e adiciona comando idempotente para reparar parcelas históricas afetadas pela taxa descontada duas vezes. |

### Atualização na VPS

```bash
cd /opt/lowify/services/service-commerce-v2
git pull
docker compose up --build -d
```

Confirme que o container permaneceu saudável:

```bash
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

### Reparação das parcelas PIX Automático históricas

O comando abaixo não altera dados sem `--execute`; use-o primeiro para listar as vendas que serão corrigidas:

```bash
docker compose exec service-commerce-v2 \
  php bin/hyperf.php subscriptions:repair-pix-automatic-recurring-sale-amounts
```

Após validar a listagem, aplique a correção:

```bash
docker compose exec service-commerce-v2 \
  php bin/hyperf.php subscriptions:repair-pix-automatic-recurring-sale-amounts --execute
```

Para reparar uma única ordem legada no formato `sub_...`:

```bash
docker compose exec service-commerce-v2 \
  php bin/hyperf.php subscriptions:repair-pix-automatic-recurring-sale-amounts \
  --order-id=sub_1a7ead02140ec1b9859348effa5dbe3b \
  --execute
```

O reparo não altera `order_id` histórico, pois ele pode já estar referenciado por integrações, gateway ou suporte. Ele ajusta somente o `sale_amount` líquido para que o reembolso volte a considerar o valor efetivamente cobrado.
