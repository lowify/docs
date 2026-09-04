# Feature — relatório de entradas do Billing do Checkout Transparente

> Status: planejada
> Última atualização: 2026-09-04
> Confiança: parcialmente confirmada no código e na VPS de homologação

## Objetivo

Exibir no Relatório Cashflow mensal as entradas já pagas de faturas do Checkout Transparente. O relatório deve permitir aos administradores de permissões `1` e `2` identificar quanto entrou em cada caixa/provedor e por método de pagamento.

O Cash In legado não deve incluir vendas cuja coluna `sales.gateway` seja `checkout_transparent`. Essas entradas passam a aparecer exclusivamente na nova aba **Cash In CT**.

Ficam fora do escopo a criação de cobranças, a confirmação de pagamentos e a alteração do provider usado para gerar Pix ou cartão.

## Regra de apuração

Uma entrada do relatório é um registro de `billing_payments` com:

- `status = 'paid'`;
- `paid_at >= início do período`;
- `paid_at < início do período seguinte`.

O período é apurado pelo pagamento efetivo (`paid_at`), não pela criação nem pelo vencimento da fatura.

O provedor do pagamento é lido de `billing_payments.metadata_json.providerIdentifier`. Para os métodos:

- `pix` e `credit_card`, o fluxo atual do `edge-public-api` grava `providerIdentifier` quando recebe o retorno do Commerce;
- `balance` não tem provider externo e deve ser apresentado como `internal_balance`;
- PIX ou cartão sem `providerIdentifier` devem aparecer separadamente como `unknown`, sem inferência pelo identificador da transação.

O valor da entrada será o `billing_charges.amount_total` associado a cada `billing_payment`. A resposta também deve incluir os pagamentos individuais para auditoria e os agrupamentos usados pela tela.

Para cada combinação de adquirente/provedor e método, o relatório calcula:

- **valor recebido / taxas recebidas**: soma de `billing_charges.amount_total` das contas pagas;
- **taxas cobradas**: custo unitário do adquirente multiplicado pela quantidade de pagamentos quitados;
- **lucro líquido**: taxas recebidas menos taxas cobradas.

O método `balance` não possui taxa de adquirente: `taxas_cobradas = 0`. Para Pix e cartão, o custo é definido pelo mesmo mapa mensal já empregado no Cashflow (`cashflowReportGatewayUnitCost`), incluindo Woovi, Woovi 2 e os demais provedores que possuírem custo configurado. O custo incide por conta paga, não pelo valor da fatura.

## Fluxo planejado

```text
Administrador (permissão 1 ou 2)
  -> Dashboard Seller: Relatório Cashflow
  -> endpoint AJAX local do relatório
  -> Gateway
  -> Edge Public API
  -> CT API
  -> CT Billing
  -> checkout_transparent_billing.billing_payments + billing_charges
```

O Cashflow atual consulta diretamente o banco principal para Cash In (`sales`) e Cash Out (`tbl_saques`). A nova etapa é necessária porque o Billing do Checkout Transparente usa banco isolado.

Na consulta legada de Cash In, o filtro passa a excluir também `LOWER(TRIM(gateway)) = 'checkout_transparent'`, preservando a separação entre o Cash In comum e o Cash In CT.

## Contrato planejado

### Billing interno

```text
GET /internal/reports/billing-payments/paid?start_at=YYYY-MM-DD%20HH:MM:SS&end_at=YYYY-MM-DD%20HH:MM:SS
```

Protegido pelo middleware de autenticação interna já usado entre CT API e CT Billing.

### CT API, Edge Public API e Gateway

```text
GET /checkout-transparent/admin/reports/billing-payments/paid?start_at=...&end_at=...
```

No CT API, a rota externa correspondente recebe o mesmo contrato e o encaminha ao Billing. No Edge Public API, o proxy deve exigir permissões administrativas `1` ou `2`; o Gateway somente roteia ao Public API.

Parâmetros:

| Campo | Regra |
| --- | --- |
| `start_at` | obrigatório; início inclusivo, no formato `Y-m-d H:i:s` |
| `end_at` | obrigatório; fim exclusivo, posterior a `start_at` |

Resposta esperada:

```json
{
  "period": {
    "start_at": "2026-08-01 00:00:00",
    "end_at": "2026-09-01 00:00:00"
  },
  "rows": [
    {
      "provider": "efi_bank",
      "method": "pix",
      "payments_count": 12,
      "amount_total": "1250.00"
    }
  ],
  "summary": {
    "payments_count": 12,
    "amount_total": "1250.00"
  },
  "payments": []
}
```

## Componentes e mudanças planejadas

| Componente | Mudança |
| --- | --- |
| `services-checkout-transparent-billing` | Query, caso de uso, controller e rota interna para pagamentos pagos por período. |
| `services-checkout-transparent-api` | Cliente HTTP para a rota interna do Billing, caso de uso/controller e rota administrativa externa. |
| `edge-public-api` | Proxy administrativo com autorização limitada a permissões `1` e `2`. |
| `edge-gateway` | Rota de encaminhamento para o Public API. |
| `dashboard-seller` | Novo método em `CheckoutTransparentAdminService`; exclusão de `checkout_transparent` do Cash In legado; etapa e aba “Cash In CT” no Cashflow. |

No Dashboard, o endpoint local já existente `api/admin/cashflow_report/step.php` será estendido com a etapa `checkout_transparent_billing`. Ele continua responsável somente por montar o HTML da tabela e por orquestrar a chamada autenticada ao Gateway através de `CheckoutTransparentAdminService`.

A tela passará a ter três abas: **Cash In**, **Cash In CT** e **Cash Out**. A tabela de Cash In CT deve mostrar adquirente, método, contas pagas, valor recebido, taxas cobradas e lucro líquido. `internal_balance` deve ser exibido como **Saldo**; os demais valores identificam o banco/adquirente retornado em `providerIdentifier`.

## Dados e limitações conhecidas

Na VPS, há pagamentos quitados com `providerIdentifier` persistido para Pix (`efi_bank`) e cartão (`cielo_ecommerce`). Pagamentos por saldo possuem apenas a origem operacional em `metadata_json`.

Também há mais de um `billing_payment` pago associado à mesma `billing_charge_id` em dados já existentes. Por isso, a consulta não deve deduplicar automaticamente por fatura: cada `billing_payment` quitado é uma entrada registrada. Como `billing_payments` não possui uma coluna de valor próprio, o valor exibido é o total da fatura associada; a listagem individual permitirá auditar eventuais duplicidades históricas.

## Validação planejada

1. Confirmar que vendas com `sales.gateway = checkout_transparent` não aparecem no Cash In legado.
2. Testar consulta mensal com pagamentos Pix, cartão, saldo e nenhum pagamento.
3. Confirmar que `paid_at` no limite inferior entra e no limite superior não entra.
4. Confirmar agrupamento de `providerIdentifier`, `internal_balance` e `unknown`.
5. Confirmar custo por conta paga para Woovi, Woovi 2 e provedores configurados; confirmar custo zero para Saldo.
6. Confirmar 401/403 para JWT sem permissões 1 ou 2 no Public API.
7. Confirmar que a nova etapa não altera os resultados existentes de Cash Out.
8. Após implementação, executar o teste integrado em homologação somente com aprovação explícita.

## Referências

- `dashboard-seller/admin_cashflow_report.php`
- `dashboard-seller/api/admin/cashflow_report/step.php`
- `dashboard-seller/app/services/checkout_transparent/CheckoutTransparentAdminService.php`
- `edge-public-api/app/UseCases/CheckoutTransparent/AdminCheckoutTransparentProxy.php`
- `services-checkout-transparent/services-checkout-transparent-billing/app/Application/UseCase/Billing/ManageSellerBillingChargePaymentUseCase.php`
- `services-checkout-transparent/services-checkout-transparent-billing/migrations/20260709010000_add_pix_payload_to_billing_payments.php`
