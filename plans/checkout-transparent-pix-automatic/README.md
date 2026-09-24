# Plano — Pix Automático no Checkout Transparente

## Objetivo

Adicionar `pix_automatic` a produtos `SUBSCRIPTION`, cobrando diretamente na integração ativa do seller.

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
| Woovi | A Woovi gera as cobranças futuras; o Checkout Transparente recebe e processa os eventos do mandato e das cobranças. |
| Efí | O Checkout Transparente agenda cada `cobr` futura e processa os retornos de recorrência e cobrança. |
| Faturamento | Cada parcela paga deve produzir o efeito de faturamento uma única vez, como acontece hoje na confirmação de uma `charge`. |
| Resiliência Woovi | Os webhooks são o caminho principal. O Checkout Transparente verifica o cadastro periodicamente e reconcilia somente assinaturas elegíveis quando houver atraso ou falha de entrega. |

## Fora do escopo

- Assinatura Pix hospedada do Mercado Pago, assinatura Pix da Pagar.me ou assinatura Pix da Kiwify.
- Reutilizar credenciais ou filas do Banking V2 para cobrar a conta do seller no Checkout Transparente.
- Reembolso de cobranças recorrentes já liquidadas.
