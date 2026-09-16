# Plano — cartão de crédito no Checkout Transparente

## Objetivo

Adicionar `card` ao Checkout Transparente para vendas `ONE_TIME`, cobrando diretamente na integração ativa do seller.

## Estado

Base comum pronta e Mercado Pago implementado para cartão: configuração pública por método, tokenização no Front Checkout, tentativa idempotente, criação via Orders e confirmação pelo worker. A validação ponta a ponta cobriu recusa e aprovação. Pagar.me e Efí permanecem como os próximos adaptadores de cartão.

## Documentos

1. [Estado atual e fronteiras](01_ESTADO_ATUAL_E_FRONTEIRAS.md)
2. [Contrato, dados e filas](02_CONTRATO_DADOS_E_FILAS.md)
3. [Implementação, rollout e aceite](03_IMPLEMENTACAO_ROLLOUT_E_ACEITE.md)

## Decisões propostas

| Tema | Proposta |
| --- | --- |
| Provedores | Implementar Mercado Pago, Pagar.me e Efí. Woovi e Kiwify não recebem `card` nesta feature. |
| Métodos da integração | Criar `integration_payment_methods` por `integration_id` e `method`, com habilitação, default e configuração do método. Pix, cartão e Pix Automático não compartilham `settings_json`. |
| Chaves do método | Criar `integration_payment_method_keys`, sempre vinculada ao método da integração. As chaves Pix atuais permanecem legadas até o backfill idempotente copiá-las para o método Pix. |
| Seleção | O CT escolhe a integração ativa cujo método está habilitado e marcado como default para aquele método. A disponibilidade de `card_credit` não depende do gateway padrão da Lowify. |
| Parcelas | Criar `charge_installments` para representar parcelas de cartão e, futuramente, Pix Automático com o mesmo contrato de status, vencimento e pagamento. |
| Venda | Commerce V2 cria somente a venda pendente transparente. A cobrança é criada e confirmada pelo CT. |
| Token | Tokenizar no navegador com a configuração pública da integração escolhida. PAN, CVV e token não são persistidos em MariaDB, auditoria ou logs. |
| Tentativa | Uma venda mantém uma única `charge`; uma recusa permite nova tentativa nessa mesma charge com token novo, sem criar outra venda. |
| Confirmação | Aprovação síncrona e confirmação posterior por polling/webhook convergem no atual `ConfirmChargePaymentUseCase`. |

## Padrões consolidados

| Tema | Padrão aplicado no Mercado Pago |
| --- | --- |
| Configuração | Dados públicos de tokenização ficam em `integration_payment_methods.settings_json`; credenciais privadas nunca retornam ao Dashboard ou checkout. |
| Credencial compartilhada | Quando o cartão reutiliza uma credencial OAuth da integração, a cópia para o método é feita apenas no servidor, cifrada e auditada. |
| Bandeira | A bandeira de interface pode ter nome diferente do identificador exigido pelo gateway. O contrato da tentativa preserva `card_brand` e `payment_method_id` separadamente. |
| Resultado | O worker traduz a resposta do provedor para o estado da charge; a confirmação de venda e entrega continua centralizada no fluxo idempotente existente. |
| Dados sensíveis | Token é transitório na fila. PAN, CVV, token e resposta bruta de tokenização não entram em banco, logs ou resposta HTTP. |

## Fluxo alvo

```text
Front Checkout -> tokenização do provedor -> Edge -> Commerce V2 (venda pendente)
-> CT API (charge e tentativa) -> Redis -> worker do provedor
-> aprovado/pendente/recusado -> polling ou webhook -> Commerce V2 (venda paga)
```

## Fora do escopo

- Recorrência, débito, boleto, Woovi Parcelado e checkout hospedado Kiwify.
- Split, credenciais de plataforma e onboarding do cartão normal da Lowify.
- Alterar credenciais privadas ou habilitar cartão em uma integração existente sem ação explícita do seller.
