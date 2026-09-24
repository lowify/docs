# Contrato, dados e eventos

Neste documento, **autorização recorrente** é a entidade do provedor criada a partir do aceite do cliente. `idRec` é seu identificador na Efí; `txid` identifica uma cobrança da Efí.

## Disponibilidade e cadastro

`pix_automatic` deve ser selecionado por método, como Pix e cartão:

```text
integration -> integration_payment_methods -> integration_payment_method_keys
```

| Provedor | Requisitos do método |
| --- | --- |
| Woovi | AppID privado, webhook registrado para eventos de Pix Automático e o mesmo contrato de endereço já enviado pelo Pix Automático atual. |
| Efí | Client ID, Client Secret, certificado, chave Pix e escopos de `locrec`, `rec`, `cobr`, `webhookrec` e `webhookcobr`; a conta precisa ser Efí Empresas e o endpoint público precisa aceitar mTLS. |

O Dashboard só habilita o método depois de validar os requisitos do provedor. O Pix avulso continua como está; Pix Automático precisa ser habilitado separadamente.

O pedido de criação deve levar a frequência normalizada do produto e os dados da pessoa pagadora. Para Woovi, inclui o endereço no mesmo formato já usado pelo Pix Automático atual; para Efí, os dados de vínculo e devedor exigidos pela recorrência. A integração que criou a autorização continua sendo usada durante toda a assinatura; trocar o método padrão do seller depois disso não muda cobranças já autorizadas.

Para Woovi, o cadastro do método cria os sete `integration_webhooks` necessários: aprovação e recusa da autorização; criação, aprovação, falha de tentativa, recusa final e conclusão da cobrança. Cada registro possui URL, segredo e `external_webhook_id` próprios. A ativação só termina quando todos estiverem confirmados no provedor. A lista de webhooks da Woovi deve ser comparada periodicamente aos registros locais para detectar remoção, desativação ou alteração feita pela conta do seller.

Para Efí, o cadastro do método registra e confirma `webhookrec` e `webhookcobr`. As URLs devem preservar a rota local quando a Efí acrescentar `/rec` e `/cobr`; `?ignorar=` é a alternativa documentada. A configuração remota dos dois callbacks deve ser comparada periodicamente ao cadastro local. O Checkout Transparente agenda e cria cada `cobr` sem repetir a mesma cobrança, e consulta autorizações e cobranças conhecidas quando um callback atrasar.

## Modelo proposto

Criar um agregado de assinatura no banco do Checkout Transparente, vinculado à venda inicial:

| Dado | Finalidade |
| --- | --- |
| `reference_id` | Identidade pública e chave de idempotência da assinatura no Checkout Transparente. |
| `sale_id` e `order_id` | Ligação com a venda inicial do Commerce V2. |
| `integration_id` e provedor | Mantém a conta do seller que criou a autorização recorrente. |
| `gateway_subscription_id` | Identificador da autorização recorrente no provedor. |
| `frequency`, `status` e `next_charge_due_at` | Estado recorrente necessário para Woovi e Efí. |
| parcela | Número, valor, vencimento, estado, identificador da cobrança e E2E quando paga. |

O registro da autorização recorrente começa em estado provisório, antes da chamada externa, com chave de idempotência própria. Depois da resposta, recebe `gateway_subscription_id` e só então vincula a venda à assinatura do Commerce V2 pela mesma correlação. A `charge` avulsa atual, que expira em uma hora, não representa uma autorização que pode durar meses.

Uma parcela paga publica `subscription.charge.paid` com `correlation_id`, `installment_number`, `end_to_end_id` e `paid_at`. O `SubscriptionActionsProcess` do Commerce V2 continua sendo o único ponto que cria ou ativa a venda daquele ciclo. Webhook e poll compartilham a mesma chave de idempotência para que os efeitos ocorram uma única vez.

Antes de criar a autorização, a composição recorrente precisa ser resolvida e persistida: preço principal, oferta, desconto e bump. O valor não pode mudar por reprocessamento do checkout. A regra para bump e desconto, recorrente ou somente inicial, precisa ser aplicada tanto no valor enviado ao provedor quanto nas vendas clonadas pelo Commerce V2.

## Filas e eventos

```text
API do Checkout Transparente -> gateway:instructions -> worker do Checkout Transparente -> gateway:results -> API do Checkout Transparente
Provedor -> webhook/polling -> API do Checkout Transparente -> sales:subscriptions:actions -> Commerce V2
```

| Ação ou evento | Origem | Efeito |
| --- | --- | --- |
| `subscription.create` | API e worker do Checkout Transparente | Cria a autorização recorrente e guarda o identificador devolvido pelo provedor. |
| `subscription.status.updated` | webhook ou polling | Atualiza `pending`, `active`, `rejected` ou `canceled`. |
| `subscription.charge.schedule` | scheduler do Checkout Transparente, somente Efí | Cria a próxima `cobr` uma única vez para a mesma assinatura, parcela e vencimento. |
| `subscription.charge.paid` | webhook ou polling | Persiste uma parcela, publica o faturamento e envia o evento ao Commerce V2 uma única vez. |

Uma cobrança não pode confirmar a venda inicial antes de a autorização recorrente estar aprovada e a primeira parcela estar paga.

Na Woovi, `COBR_TRY_REJECTED` não encerra a parcela quando a política permite novas tentativas; somente o estado final pode impedir a renovação. Na Efí, o scheduler só avança `next_charge_due_at` depois de o provedor confirmar que a `cobr` foi criada.

## Verificação e recuperação na Woovi

No fluxo normal, a Woovi avisa cada mudança por webhook. Esta verificação serve para recuperar atraso de entrega, indisponibilidade temporária e remoção de webhook:

1. Verificar os sete webhooks de cada integração Woovi ativa com `GET /api/v1/webhook`.
2. Recriar somente os registros ausentes ou alterados, preservando histórico e idempotência do cadastro local.
3. Consultar `GET /api/v1/subscriptions/{id}` e `GET /api/v1/subscriptions/{id}/installments` para assinaturas ativas dentro da janela de vencimento ou sem atualização recente.
4. Normalizar cada parcela terminal com chave de idempotência por integração, assinatura, número da parcela e identificador da cobrança.

O processo não consulta continuamente cada parcela. Se o webhook faltar, haverá atraso até a verificação encontrar o pagamento. Venda, entrega e faturamento só acontecem depois de confirmar que a parcela foi paga.

## Verificação e recuperação na Efí

A Efí precisa de dois polls (consultas programadas) quando os callbacks falharem, além da verificação periódica de `webhookrec` e `webhookcobr`:

1. **Autorização:** consultar `GET /v2/rec/:idRec` para cada autorização recorrente local pendente ou ativa, em intervalo de até uma hora. A consulta normaliza aprovação, recusa, cancelamento e alterações externas.
2. **Cobrança:** consultar `GET /v2/cobr/:txid` somente para cada cobrança local não terminal, em janela compatível com vencimento e retentativas. A confirmação paga publica uma única vez o evento para o Commerce V2.

Os dois polls usam identificadores persistidos pelo Checkout Transparente: `idRec` para a autorização recorrente e `txid` para a cobrança. A API também oferece `GET /v2/rec` e `GET /v2/cobr` com filtros e paginação, mas a documentação não define ordenação. Essas listas não podem decidir o estado de uma assinatura nem selecionar a cobrança a processar; servem apenas para investigação e recuperação excepcional com paginação completa.

## Isolamento

- O Checkout Transparente não chama `/subscription/pix` do Banking V2: aquele caminho usa a conta da Lowify, enquanto esta feature usa a conta do seller.
- Credenciais, certificado e resposta bruta do provedor permanecem no Checkout Transparente. Commerce V2 recebe somente os identificadores e o evento normalizado.
