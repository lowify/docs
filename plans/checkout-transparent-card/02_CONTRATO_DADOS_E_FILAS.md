# Contrato, dados e filas

## Cadastro e disponibilidade

O schema de credenciais e a API do Dashboard devem aceitar apenas os campos abaixo, sempre cifrados em `integration_keys` quando não forem públicos.

| Provedor | Dados do seller necessários |
| --- | --- |
| Mercado Pago | `access_token` e `public_key`. |
| Pagar.me | credencial de servidor e chave/configuração pública de tokenização. |
| Efí | perfil habilitado para cartão, `payee_code` e as credenciais exigidas pela API de cartão, validadas separadamente do perfil Pix. |

`GET /checkout/availability` deve continuar selecionando a integração no servidor. Para `card`, ele retorna somente a configuração pública mínima de tokenização da integração selecionada; nunca retorna `access_token`, secret, certificado ou chave privada.

## Contrato de cobrança proposto

1. `POST /charges` cria a charge local sem token e sem publicar pagamento quando `payment_method=card`.
2. Um endpoint interno de tentativa da charge recebe `payment_token`, bandeira, parcelas, documento, telefone e endereço. Ele aceita somente a charge da mesma venda, pendente ou recusável, e publica `payment.create`.
3. O Edge cria a venda pendente, cria a charge e envia a tentativa. Em reenvio do formulário, localiza a mesma `reference_id` e envia somente uma nova tentativa.
4. O resultado público de charge passa a expor método, parcelas, bandeira mascarada quando retornada pelo provedor e status normalizado. Não expõe token, PAN, CVV ou resposta bruta.

O formato final do endpoint de tentativa deve ser definido antes do código. Ele precisa de uma chave de idempotência por tentativa, distinta da chave de criação da charge.

## Dados e migrations propostas

| Estrutura atual | Alteração |
| --- | --- |
| `charges` | Adicionar `payment_method`; avaliar `card_brand` e `installments` como campos de apresentação. Preservar índices únicos por venda, pedido e transação. |
| `charge_attempts` | Registrar uma tentativa antes do enqueue, com referência/idempotência e status. A resposta sanitizada atual continua aqui; token não entra no JSON. |
| `integration_keys` | Adicionar tipos de chave de cartão ao validador e ao cifrador, sem migrar nem reinterpretar as credenciais Pix existentes. |
| `integrations.settings_json` | Guardar somente capacidades não sensíveis, por exemplo cartão habilitado e ambiente, se necessário. |

As migrations devem ser aditivas. A consulta ao MariaDB confirmou `charges`, `charge_attempts`, `charge_status_checks`, `integrations`, `integration_keys` e `integration_gateways` como tabelas implantadas.

## Fila e confirmação

O envelope atual de `payment.create` já possui `uuid`, `provider`, `correlation_id`, valor, `charge_id`, `sale_id`, integração e idempotência. Para cartão, acrescentar um bloco de pagamento transitório e tipado, com token, bandeira e parcelas, e um identificador de tentativa.

```text
CT API -> gateway:instructions -> GatewayInstructionQueueProcess
-> cliente do provedor -> gateway:results -> GatewayResultQueueProcess
```

- O worker já refaz falhas transitórias e publica resultado na fila de retorno. A sanitização deve ocorrer antes de qualquer `response_json` ou log que possa conter token.
- `payment.create.result` precisa normalizar `approved`, `pending` e `refused`. Para aprovado, ele confirma a charge no mesmo caminho idempotente usado pelo status check; para pendente, agenda consulta/webhook; para recusa, registra a tentativa e permite token novo.
- Webhooks e polling permanecem necessários para estados pendentes. Cada adaptador deve traduzir o identificador e status de cartão para o contrato atual de `payment.status.check`.
- No edge de webhook, Pagar.me já resolve `charge.paid` e `order.paid` por charge, e Mercado Pago já solicita status para eventos `payment`; ambos exigem teste com cartão. O resolver Efí atual lê apenas a coleção `pix` e precisa de tratamento específico de cartão ou de polling até a confirmação.

## Regras de isolamento

- Não chamar `services-banking-v2` para processar a cobrança transparente. Seus clientes de cartão são referência de payload e resposta, não o dono da transação.
- Não usar `gateway_default_checkout_card`, Cielo seller onboarding, Pagar.me PSP, split ou taxa da plataforma para decidir cartão transparente.
- Commerce V2 não recebe token nem dados brutos do cartão; recebe e preserva somente a venda pendente.
