# Plano — assinaturas por cartão Cielo Split

> Status: proposta; depende de confirmação comercial e técnica da Cielo
> Última atualização: 2026-10-20
> Público: Direção, Produto, Operações e Engenharia

## Objetivo

Permitir que produtos `SUBSCRIPTION` sejam cobrados por cartão de crédito pela integração **Cielo Split**, com uma adesão inicial e renovações periódicas vinculadas ao mesmo plano de assinatura.

Nesta proposta, a Cielo cria e cobra a recorrência; a Lowify registra a assinatura, distribui o valor de cada cobrança ao seller, confirma cada parcela e aplica uma única vez os efeitos da venda paga.

## Estado

Hoje a Cielo Split está integrada somente para cartão avulso. O checkout aceita cartão para `ONE_TIME`, cria `SplittedCreditCard` em `POST /1/sales` e faz a divisão na própria cobrança. Produto `SUBSCRIPTION` aceita apenas `pix_automatic`.

A Cielo documenta recorrência para o mesmo produto que usamos — **Split de Pagamento com API E-commerce Cielo** — mas exige habilitação comercial da conta Master e informa que o Split de uma cobrança recorrente é pós-transacional. Portanto, recorrência existe no produto contratado, porém ainda não está entregue pela Lowify.

## Documentos

1. [Estado atual e fronteiras](01_ESTADO_ATUAL_E_FRONTEIRAS.md)
2. [Contrato, dados e eventos](02_CONTRATO_DADOS_E_EVENTOS.md)
3. [Implementação, rollout e aceite](03_IMPLEMENTACAO_ROLLOUT_E_ACEITE.md)
4. [Dashboard e travas de configuração](04_DASHBOARD_E_TRAVAS_DE_CONFIGURACAO.md)

## Decisões propostas

| Tema | Proposta |
| --- | --- |
| Produto Cielo | Usar a Recorrência Programada da API E-commerce Cielo autenticada pelo OAuth do Split. |
| Criação das parcelas | A Cielo gera as cobranças futuras; a Lowify não agenda uma nova cobrança de cartão a cada mês. |
| Identificador da assinatura | Persistir o `RecurrentPaymentId` da Cielo como a correlação da assinatura. |
| Identificador da parcela | Persistir o `PaymentId` recebido em cada cobrança recorrente como identificador individual da parcela. |
| Divisão financeira | Após cada `PaymentId` recorrente, solicitar o Split pós-transacional com a mesma composição financeira da venda. |
| Notificação | Receber `ChangeType: 2`, consultar o pagamento por `PaymentId` e processar o resultado de maneira idempotente. |
| Fila | Usar uma fila exclusiva Cielo entre Banking V2 e Commerce V2; não publicar nem consumir as filas de assinatura já usadas pelo Banking V1. |
| Cartão | Não guardar PAN nem CVV. Confirmar com a Cielo a habilitação de Recorrência e Cartão Protegido/tokenização. |
| Elegibilidade do seller | A chave opcional `user_system_vars.cielo_split_card_recurring_enabled` é uma liberação explícita por seller. Ausência é `null` e nega a feature; `1` permite a avaliação; `0` nega explicitamente. Não há fallback global. |
| Produto Lowify | Habilitar `card` para `SUBSCRIPTION` somente depois da homologação completa da Cielo, para seller explicitamente liberado, com Cielo aprovada e somente em `1x`. |

## Fluxo alvo

```text
Admin -> define a elegibilidade por seller (`user_system_vars`)
      -> Dashboard exibe cartão em `SUBSCRIPTION` somente ao seller elegível
Checkout -> Commerce V2 revalida flag, Cielo e `1x`
         -> Banking V2 cria a recorrência Cielo
         -> Lowify grava RecurrentPaymentId e a primeira venda pendente
         -> Cielo cobra cada ciclo
         -> webhook ChangeType 2 -> Edge -> Banking V2 consulta PaymentId
         -> Split pós-transacional -> commerce:cielo:subscriptions:actions -> Commerce V2
         -> venda, acesso, entrega, financeiro e notificações
```

## Condição antes do desenvolvimento

A Cielo precisa confirmar, para a **nova conta Master** em produção:

1. Recorrência Programada na API E-commerce Cielo com Split;
2. Cartão Protegido/tokenização, se necessário ao modelo aprovado;
3. permissão de cobranças recorrentes sem CVV, quando aplicável;
4. endpoint e contrato do Split pós-transacional para cada `PaymentId` gerado pelo motor de recorrência;
5. habilitação e formato do webhook de recorrência (`ChangeType: 2`).

Sem essa confirmação, o plano não deve avançar para código de produção. Um retorno `313` da Cielo significa que recorrência não está habilitada.

## Fora do escopo

- Alterar o checkout de produtos `ONE_TIME` ou o cartão parcelado já existente.
- Cobrança recorrente própria pela Lowify, com disparo mensal de cartão pela nossa infraestrutura.
- Guardar dados brutos de cartão ou CVV.
- Assinatura Pix, Pagar.me, Mercado Pago, Efí, Woovi ou outro provedor.
- Reembolso de uma série inteira de recorrência; reembolso permanece uma operação por `PaymentId`.
