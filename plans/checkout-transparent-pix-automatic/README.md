# Plano — Pix Automático no Checkout Transparente

## Objetivo

Adicionar `pix_automatic` a produtos `SUBSCRIPTION`, cobrando diretamente na integração ativa do seller e mantendo a confirmação, a entrega e as renovações no fluxo central de assinaturas.

## Estado

Planejamento inicial. Nenhuma alteração de código, migration ou cadastro de método foi iniciada por este plano.

## Documentos

1. [Estado atual e fronteiras](01_ESTADO_ATUAL_E_FRONTEIRAS.md)
2. [Contrato, dados e eventos](02_CONTRATO_DADOS_E_EVENTOS.md)
3. [Implementação e aceite](03_IMPLEMENTACAO_E_ACEITE.md)

## Decisões propostas

| Tema | Proposta |
| --- | --- |
| Provedores | Implementar Woovi e Efí. Mercado Pago, Pagar.me e Kiwify não recebem `pix_automatic`. |
| Integração | `pix_automatic` é um método próprio em `integration_payment_methods`; sua habilitação é explícita. |
| Assinatura | A venda pendente, a assinatura e a recorrência do provedor devem compartilhar uma correlação única. |
| Woovi | A Woovi gera as cobranças futuras; o CT recebe e processa os eventos do mandato e das cobranças. |
| Efí | O CT agenda cada `cobr` futura e processa os retornos de recorrência e cobrança. |
| Commerce V2 | Continua dono da venda, da parcela, da renovação, da entrega e dos efeitos de venda paga. |
| Faturamento | Cada parcela paga deve produzir o efeito de faturamento uma única vez, como acontece hoje na confirmação de uma `charge`. |

## Fluxo alvo

```text
Front Checkout -> Edge / Commerce V2 (venda pendente)
-> CT API (assinatura) -> Redis -> worker do provedor
-> mandato aprovado -> cobrança paga
-> evento do provedor -> Commerce V2 (parcela, venda e entrega)
```

## Fora do escopo

- Assinatura Pix hospedada do Mercado Pago, assinatura Pix da Pagar.me ou assinatura Pix da Kiwify.
- Reutilizar credenciais ou filas do Banking V2 para cobrar a conta do seller no CT.
- Reembolso de cobranças recorrentes já liquidadas.
