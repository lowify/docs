# Contrato, dados e eventos

## Disponibilidade e cadastro

`pix_automatic` deve ser selecionado por método, como Pix e cartão:

```text
integration -> integration_payment_methods -> integration_payment_method_keys
```

| Provedor | Requisitos do método |
| --- | --- |
| Woovi | AppID privado, webhook registrado para eventos de Pix Automático e o mesmo contrato de endereço já enviado pelo Pix Automático atual. |
| Efí | Client ID, Client Secret, certificado, chave Pix e escopos de `locrec`, `rec`, `cobr`, `webhookrec` e `webhookcobr`; a conta precisa ser Efí Empresas e o endpoint público precisa aceitar mTLS. |

O Dashboard habilita o método após validar os requisitos do provedor. Configurações de Pix avulso permanecem compatíveis, mas a habilitação de Pix Automático precisa ser explícita.

O payload de criação deve levar a frequência normalizada do produto e os dados da pessoa pagadora. Para Woovi, inclui o endereço no mesmo formato já usado pelo Pix Automático atual; para Efí, os dados de vínculo e devedor exigidos pela recorrência. A integração que criou o mandato é mantida durante toda a assinatura; uma troca posterior de método padrão do seller não muda cobranças já autorizadas.

Para Woovi, o cadastro do método cria os sete `integration_webhooks` necessários: aprovação e recusa do mandato; criação, aprovação, falha de tentativa, recusa final e conclusão da cobrança. Cada registro possui URL, segredo e `external_webhook_id` próprios. A ativação só é concluída quando todos os registros necessários estiverem confirmados no provedor. A listagem de webhooks da Woovi deve ser comparada periodicamente aos registros locais para detectar remoção, desativação ou alteração feita pela conta do seller.

Para Efí, o cadastro do método registra e confirma `webhookrec` e `webhookcobr`. As URLs devem preservar a rota local quando a Efí acrescentar `/rec` e `/cobr`; `?ignorar=` é a alternativa documentada. A configuração remota dos dois callbacks deve ser comparada periodicamente ao cadastro local. A criação de `cobr` fica a cargo do scheduler idempotente do Checkout Transparente, e a consulta de recorrências e cobranças conhecidas recupera atrasos de callback.

## Modelo proposto

Criar uma estrutura recorrente no banco do Checkout Transparente, vinculada a uma única venda inicial:

| Dado | Finalidade |
| --- | --- |
| `reference_id` | Identidade pública e idempotente da assinatura do Checkout Transparente. |
| `sale_id` e `order_id` | Ligação com a venda inicial do Commerce V2. |
| `integration_id` e provedor | Mantém a conta do seller que criou o mandato. |
| `gateway_subscription_id` | Correlação do mandato no provedor. |
| `frequency`, `status` e `next_charge_due_at` | Estado recorrente necessário para Woovi e Efí. |
| parcela | Número, valor, vencimento, estado, identificador da cobrança e E2E quando paga. |

O registro do mandato começa em estado provisório, antes da chamada externa, com chave de idempotência própria. Após a resposta, ele recebe `gateway_subscription_id` e só então vincula a venda e a assinatura do Commerce V2 pela mesma correlação. A `charge` avulsa atual, que expira em uma hora, não representa esse mandato.

Uma parcela paga publica `subscription.charge.paid` com `correlation_id`, `installment_number`, `end_to_end_id` e `paid_at`. O `SubscriptionActionsProcess` do Commerce V2 já possui esse contrato e deve continuar sendo o único ponto que cria ou ativa a venda de cada ciclo. O efeito de faturamento da parcela deve compartilhar a mesma chave idempotente.

Antes da autorização, a composição recorrente precisa ser resolvida e persistida: preço principal, oferta, desconto e bump. O valor do mandato não pode mudar por reprocessamento do checkout. A decisão sobre bump e desconto ser recorrente ou somente inicial precisa ser aplicada tanto no valor enviado ao provedor quanto nas vendas clonadas pelo Commerce V2.

## Filas e eventos

```text
API do Checkout Transparente -> gateway:instructions -> worker do Checkout Transparente -> gateway:results -> API do Checkout Transparente
Provedor -> webhook/polling -> API do Checkout Transparente -> sales:subscriptions:actions -> Commerce V2
```

| Ação ou evento | Origem | Efeito |
| --- | --- | --- |
| `subscription.create` | API e worker do Checkout Transparente | Cria o mandato e guarda a correlação do provedor. |
| `subscription.status.updated` | webhook ou polling | Atualiza `pending`, `active`, `rejected` ou `canceled`. |
| `subscription.charge.schedule` | scheduler do Checkout Transparente, somente Efí | Cria a próxima `cobr` com idempotência por assinatura, parcela e vencimento. |
| `subscription.charge.paid` | webhook ou polling | Persiste uma parcela, publica o faturamento e envia o evento ao Commerce V2 uma única vez. |

O estado de uma cobrança não pode confirmar a venda inicial antes de o mandato estar aprovado e a primeira parcela estar paga.

Na Woovi, `COBR_TRY_REJECTED` não encerra a parcela quando a política permite novas tentativas; somente o estado terminal normalizado pode impedir a renovação. Na Efí, o scheduler só avança `next_charge_due_at` depois de a `cobr` idempotente estar confirmada pelo provedor.

## Reconciliação Woovi

Webhooks atualizam o estado no fluxo normal. A reconciliação da Woovi serve para recuperar atraso de entrega, indisponibilidade temporária e remoção de webhook:

1. Verificar os sete webhooks de cada integração Woovi ativa com `GET /api/v1/webhook`.
2. Recriar somente os registros ausentes ou divergentes, preservando o histórico local e a idempotência do cadastro.
3. Consultar `GET /api/v1/subscriptions/{id}` e `GET /api/v1/subscriptions/{id}/installments` para assinaturas ativas dentro da janela de vencimento ou sem atualização recente.
4. Normalizar cada parcela terminal com chave de idempotência por integração, assinatura, número da parcela e identificador da cobrança.

O processo não consulta continuamente cada parcela. Atraso de reconciliação é esperado quando o webhook falta; entrega, renovação e faturamento só ocorrem após o estado pago ser confirmado.

## Isolamento

- O Checkout Transparente não chama `/subscription/pix` do Banking V2: aquele caminho usa a conta da Lowify, enquanto esta feature usa a conta do seller.
- Credenciais, certificado e resposta bruta do provedor permanecem no Checkout Transparente. Commerce V2 recebe somente os identificadores e o evento normalizado.
