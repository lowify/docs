# Feature — Referência externa da venda

> Status: em evolução
> Última atualização: 2026-09-30
> Confiança: confirmada no código

## Objetivo

Preservar uma referência fornecida na URL pública do checkout para que sistemas externos conciliem a venda e os eventos de webhook correspondentes.

## Fluxo principal

```text
GET ?offer=oferta&external_reference=valor
  -> Front Checkout /go (preserva no redirecionamento)
  -> Front Checkout (campo oculto)
  -> Gateway/Public API
  -> Commerce V2 (validação e sales.external_reference)
  -> evento de integração
  -> services-sale-integrations (webhook externo)
```

## Componentes e responsabilidades

| Componente | Responsabilidade | Entrada/saída relevante |
| --- | --- | --- |
| `front-checkout` | Lê e preserva a referência válida no formulário. | `external_reference` em GET e POST. |
| `services-commerce-v2` | Valida e persiste a referência com a venda. | `sales.external_reference`. |
| `services-sale-integrations` | Inclui a referência no payload do webhook. | `external_reference` no JSON externo. |
| `dashboard-seller` | Exibe o campo quando preenchido. | Detalhes de venda e detalhe administrativo. |

## Contratos e autorização

`external_reference` é opcional, tem até 100 caracteres e deve corresponder a `^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,99}$`. O valor é metadado de conciliação; não é usado para autorização, busca de vendas ou idempotência.

## Dados e processamento assíncrono

Uma migration adiciona `sales.external_reference` como coluna anulável. O `BuildSaleDataUseCase` copia o valor para o bloco `sale` do evento consumido pelas integrações.

## Operação e validação

Validação manual pendente: criar checkout com referência válida, confirmar persistência, conferir a exibição nas duas telas e receber o campo nos webhooks de venda pendente e paga.

## Limitações e pendências

- Não há alias para `external_id`.
- Vendas pendentes duplicadas mantêm o comportamento existente e não têm a referência sobrescrita por nova tentativa.

## Referências

- `front-checkout/views/checkout/index.php`
- `services-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/BuildSaleDataUseCase.php`
- `services-sale-integrations/app/Infrastructure/Integration/Webhook/WebhookSender.php`
