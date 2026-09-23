# Contrato, dados e eventos

## Disponibilidade e cadastro

`pix_automatic` deve ser selecionado por método, como Pix e cartão:

```text
integration -> integration_payment_methods -> integration_payment_method_keys
```

| Provedor | Requisitos do método |
| --- | --- |
| Woovi | AppID privado, webhook registrado para eventos de Pix Automático e endereço completo da pessoa pagadora. |
| Efí | Client ID, Client Secret, certificado e autorização para `locrec`, `rec` e `cobr`; a integração já precisa de uma chave Pix válida. |

O Dashboard habilita o método após validar os requisitos do provedor. Configurações de Pix avulso permanecem compatíveis, mas a habilitação de Pix Automático precisa ser explícita.

O payload de criação deve levar a frequência normalizada do produto, os dados da pessoa pagadora e os dados de endereço exigidos pela Woovi. A integração que criou o mandato é mantida durante toda a assinatura; uma troca posterior de método padrão do seller não muda cobranças já autorizadas.

## Modelo proposto

Criar uma estrutura recorrente no banco do CT, vinculada a uma única venda inicial:

| Dado | Finalidade |
| --- | --- |
| `reference_id` | Identidade pública e idempotente da assinatura CT. |
| `sale_id` e `order_id` | Ligação com a venda inicial do Commerce V2. |
| `integration_id` e provedor | Mantém a conta do seller que criou o mandato. |
| `gateway_subscription_id` | Correlação do mandato no provedor. |
| `frequency`, `status` e `next_charge_due_at` | Estado recorrente necessário para Woovi e Efí. |
| parcela | Número, valor, vencimento, estado, identificador da cobrança e E2E quando paga. |

Uma parcela paga publica `subscription.charge.paid` com `correlation_id`, `installment_number`, `end_to_end_id` e `paid_at`. O `SubscriptionActionsProcess` do Commerce V2 já possui esse contrato e deve continuar sendo o único ponto que cria ou ativa a venda de cada ciclo. O efeito de faturamento da parcela deve compartilhar a mesma chave idempotente.

## Filas e eventos

```text
CT API -> gateway:instructions -> CT worker -> gateway:results -> CT API
Provedor -> webhook/polling -> CT API -> sales:subscriptions:actions -> Commerce V2
```

| Ação ou evento | Origem | Efeito |
| --- | --- | --- |
| `subscription.create` | CT API e worker | Cria o mandato e guarda a correlação do provedor. |
| `subscription.status.updated` | webhook ou polling | Atualiza `pending`, `active`, `rejected` ou `canceled`. |
| `subscription.charge.schedule` | scheduler CT, somente Efí | Cria a próxima `cobr` com idempotência por assinatura, parcela e vencimento. |
| `subscription.charge.paid` | webhook ou polling | Persiste uma parcela, publica o faturamento e envia o evento ao Commerce V2 uma única vez. |

O estado de uma cobrança não pode confirmar a venda inicial antes de o mandato estar aprovado e a primeira parcela estar paga.

## Isolamento

- O CT não chama `/subscription/pix` do Banking V2: aquele caminho usa a conta da Lowify, enquanto esta feature usa a conta do seller.
- Credenciais, certificado e resposta bruta do provedor permanecem no CT. Commerce V2 recebe somente os identificadores e o evento normalizado.
- A confirmação financeira, a entrega, as notificações e a renovação continuam no Commerce V2.
