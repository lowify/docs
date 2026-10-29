# Plano — Reflexo de reembolso externo Cielo

> Status: planejamento
>
> Escopo: reembolso total de venda por cartão Cielo E-commerce iniciado no portal Cielo

## Objetivo

Quando uma cobrança Cielo for cancelada ou estornada diretamente no portal da adquirente, refletir o resultado confirmado na Lowify. A operação deve criar ou concluir os registros financeiros necessários no Banking V2, registrar o reembolso em Commerce V2 e disparar os efeitos já associados ao evento de venda reembolsada.

O fluxo não cria uma nova forma de reembolso. Ele estende o mesmo ciclo usado quando o reembolso é solicitado pela Lowify para que a origem externa alcance o mesmo estado final, com rastreabilidade e idempotência.

## Resultado esperado

    Portal Cielo
      -> webhook ChangeType 25
      -> Edge Webhook registra e enfileira
      -> Banking V2 consulta PaymentId e confirma o estado final
      -> refunds_charge, charges_card, evento da cobrança e alocações financeiras
      -> sales:events:refunded
      -> Commerce V2 cria/atualiza sales_refund e processa sale:refunded

Ao término, a mesma venda passa a ter:

- cobrança de cartão marcada como reembolsada;
- evento de cobrança com origem webhook;
- registro aprovado em `refunds_charge`;
- alocações de parcelas refletidas quando aplicáveis;
- registro aprovado em `sales_refund`;
- efeitos comerciais e financeiros já ligados a `sale:refunded`.

## Escopo

- Cielo E-commerce com cartão e venda conhecida pela Lowify.
- Cancelamento ou estorno total confirmado pela consulta da Cielo, com `Payment.Status` 10 ou 11.
- Reembolso realizado fora da Lowify, no portal ou operação da Cielo.
- Reutilização de Edge Webhook, Redis, Banking V2 e Commerce V2 existentes.

## Fora de escopo

- Disparar um novo reembolso para a Cielo; esta entrega apenas reflete um reembolso já feito externamente.
- Pix, boleto, Pagar.me, PagSmile, Woovi ou outros provedores.
- Chargeback, contestação ou cancelamento de assinatura.
- Reembolso parcial. A Cielo pode emitir `ChangeType 25` mantendo `Payment.Status` 2; não é correto publicar `sale:refunded` nessa situação sem identificar o valor e a operação parcial de forma inequívoca.

## Documentos

1. [Decisão e fronteiras](./01_DECISAO_E_FRONTEIRAS.md)
2. [Contrato, dados e eventos](./02_CONTRATO_DADOS_E_EVENTOS.md)
3. [Implementação, rollout e aceite](./03_IMPLEMENTACAO_ROLLOUT_E_ACEITE.md)
