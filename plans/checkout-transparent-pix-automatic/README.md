# Plano — Pix Automático no Checkout Transparente

## Objetivo

Adicionar `pix_automatic` a produtos `SUBSCRIPTION`, cobrando diretamente na integração ativa do seller.

Neste plano, **autorização do cliente** é o aceite dado no banco para que as próximas cobranças sejam feitas automaticamente. Ela é criada uma vez; cada parcela é uma cobrança posterior vinculada a essa autorização.

## Estado

Woovi e Efí estão implementadas para `SUBSCRIPTION`. Ambas criam a autorização, confirmam a primeira parcela e enviam o evento idempotente para venda, entrega e faturamento no Commerce V2.

Na Efí, a Jornada 3 cria a cobrança inicial e a autorização; o Checkout Transparente agenda cada `cobr` futura e consulta a recorrência por `idRec` e a cobrança por `txid`. Cancelamento e reembolso ainda não estão disponíveis como ação do seller na Lowify.

## Documentos

1. [Estado atual e fronteiras](01_ESTADO_ATUAL_E_FRONTEIRAS.md)
2. [Contrato, dados e eventos](02_CONTRATO_DADOS_E_EVENTOS.md)
3. [Implementação e aceite](03_IMPLEMENTACAO_E_ACEITE.md)

## Decisões propostas

| Tema | Proposta |
| --- | --- |
| Provedores | Woovi e Efí implementadas. Mercado Pago, Pagar.me e Kiwify não recebem `pix_automatic`. |
| Integração | `pix_automatic` é um método próprio em `integration_payment_methods`; sua habilitação é explícita. |
| Assinatura | A venda inicial, a autorização do cliente e as parcelas precisam ter identificadores que permitam localizar o mesmo pagamento em todos os sistemas. |
| Woovi | A Woovi gera as cobranças futuras; o Checkout Transparente recebe e processa os avisos sobre a autorização e os pagamentos. |
| Efí | O Checkout Transparente agenda cada `cobr` futura e processa os retornos de recorrência e cobrança. Quando faltar callback, consulta a autorização por `idRec` e a cobrança por `txid`. |
| Faturamento | Cada parcela paga deve produzir o efeito de faturamento uma única vez, como acontece hoje na confirmação de uma `charge`. |
| Resiliência Woovi | Os webhooks são o caminho principal. O Checkout Transparente confere o cadastro periodicamente e consulta apenas as assinaturas afetadas por atraso ou falha de entrega. |
| Controle da conta | O seller pode alterar webhooks, credenciais, permissões, autorizações ou cobranças no provedor. Monitoramento e consulta ajudam a detectar isso, mas não impedem a alteração externa. |

## Fora do escopo

- Assinatura Pix hospedada do Mercado Pago, assinatura Pix da Pagar.me ou assinatura Pix da Kiwify.
- Reutilizar credenciais ou filas do Banking V2 para cobrar a conta do seller no Checkout Transparente.
- Cancelamento e reembolso de Pix Automático pela interface do seller.
