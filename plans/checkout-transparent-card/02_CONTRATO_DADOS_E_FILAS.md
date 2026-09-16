# Contrato, dados e filas

## Cadastro e disponibilidade

`integrations` continua representando a conta conectada ao provedor. Cada meio de pagamento dela ganha um registro em `integration_payment_methods`:

```text
integration -> integration_payment_methods -> integration_payment_method_keys
```

O método possui `method`, `enabled`, `is_default` e `settings_json`. As chaves ficam em `integration_payment_method_keys`, sempre cifradas e com hash de credencial. Uma integração pode ter Pix e cartão habilitados, com configurações e chaves independentes; o seller pode definir um default diferente por método.

O schema de credenciais e a API do Dashboard devem aceitar apenas os campos abaixo, sempre no método correspondente.

| Provedor | Dados do seller necessários |
| --- | --- |
| Mercado Pago | `access_token` e `public_key`. |
| Pagar.me | credencial de servidor e chave/configuração pública de tokenização. |
| Efí | perfil habilitado para cartão, `payee_code` e as credenciais exigidas pela API de cartão, validadas separadamente do perfil Pix. |

No Mercado Pago, a integração OAuth já possui `access_token` privado. A configuração de `card_credit` recebe somente a `public_key`; ao habilitar o método, o servidor copia a credencial necessária para a chave cifrada do método. O Dashboard e a disponibilidade pública continuam recebendo apenas a `public_key`.

`GET /checkout/availability` deve continuar selecionando a integração no servidor. Para `card_credit`, ele retorna somente a configuração pública mínima de tokenização da integração selecionada; nunca retorna `access_token`, secret, certificado ou chave privada.

O comando `integration-payment-methods:backfill-pix` cria o método Pix habilitado para cada integração existente, copia `settings_json` e as últimas chaves de `integration_keys` para as tabelas novas. Ele deve poder ser executado repetidamente e será obrigatório no deploy antes de trocar a leitura para os métodos novos.

## Contrato de cobrança proposto

1. `POST /charges` cria a charge local sem token e sem publicar pagamento quando `method=card_credit`.
2. Um endpoint interno de tentativa da charge recebe `payment_token`, `card_brand`, `payment_method_id`, parcelas e dados do comprador. Ele aceita somente a charge da mesma venda, pendente ou recusável, e publica `payment.create`.
3. O Edge cria a venda pendente, cria a charge e envia a tentativa. Em reenvio do formulário, localiza a mesma `reference_id` e envia somente uma nova tentativa.
4. O resultado público de charge passa a expor método, parcelas, bandeira mascarada quando retornada pelo provedor e status normalizado. Não expõe token, PAN, CVV ou resposta bruta.

O contrato base usa `POST /charges/{reference_id}/card-attempts`, com `X-Lowify-Idempotency-Key` distinto da criação da charge. A tentativa guarda somente referência, bandeira, identificador do meio de pagamento do gateway, parcelas, estado e resposta sanitizada; o token segue apenas no envelope transitório para o worker.

`card_brand` não deve ser usado como substituto automático de `payment_method_id`. O tokenizador ou adaptador resolve o código que o gateway exige. Para Mercado Pago, o front mantém `mastercard` para a apresentação e envia `master` ao endpoint de Orders.

## Dados e migrations propostas

| Estrutura atual | Alteração |
| --- | --- |
| `charges` | Adicionar `method`; avaliar `card_brand` como campo de apresentação. Preservar índices únicos por venda, pedido e transação. |
| `charge_installments` | Criar parcelas reutilizáveis por `charge_id`, número, valor, vencimento, status, pagamento e identificadores do provedor. |
| `charge_attempts` | Registrar uma tentativa antes do enqueue, com referência/idempotência e status. A resposta sanitizada atual continua aqui; token não entra no JSON. |
| `integration_payment_methods` | Criar método, habilitação, default e configuração por integração. O backfill inicial cria somente Pix. |
| `integration_payment_method_keys` | Criar chaves cifradas e hashes por método. `integration_keys` permanece somente como origem do backfill e compatibilidade temporária. |

As migrations devem ser aditivas. A consulta ao MariaDB confirmou `charges`, `charge_attempts`, `charge_status_checks`, `integrations`, `integration_keys` e `integration_gateways` como tabelas implantadas.

## Fila e confirmação

O envelope atual de `payment.create` já possui `uuid`, `provider`, `correlation_id`, valor, `charge_id`, `sale_id`, integração e idempotência. Para cartão, acrescentar um bloco de pagamento transitório e tipado, com token, bandeira e parcelas, e um identificador de tentativa.

```text
CT API -> gateway:instructions -> GatewayInstructionQueueProcess
-> cliente do provedor -> gateway:results -> GatewayResultQueueProcess
```

- O worker já refaz falhas transitórias e publica resultado na fila de retorno. A sanitização ocorre antes de qualquer `response_json` ou log que possa conter token.
- `payment.create.result` normaliza os estados do provedor. Para aprovado, confirma a charge no mesmo caminho idempotente usado pelo status check; para pendente, agenda consulta/webhook; para recusa, registra a tentativa e permite token novo.
- Webhooks e polling permanecem necessários para estados pendentes. Cada adaptador deve traduzir o identificador e status de cartão para o contrato atual de `payment.status.check`.
- No edge de webhook, Pagar.me já resolve `charge.paid` e `order.paid` por charge, e Mercado Pago já solicita status para eventos `payment`; ambos exigem teste com cartão. O resolver Efí atual lê apenas a coleção `pix` e precisa de tratamento específico de cartão ou de polling até a confirmação.

## Regras de isolamento

- Não chamar `services-banking-v2` para processar a cobrança transparente. Seus clientes de cartão são referência de payload e resposta, não o dono da transação.
- Não usar `gateway_default_checkout_card`, Cielo seller onboarding, Pagar.me PSP, split ou taxa da plataforma para decidir cartão transparente.
- Commerce V2 não recebe token nem dados brutos do cartão; recebe e preserva somente a venda pendente.
