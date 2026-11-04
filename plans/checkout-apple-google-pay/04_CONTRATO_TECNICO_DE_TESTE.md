# Apple Pay e Google Pay — contrato técnico de teste

## Fluxo

`front-checkout` mantém `payment_method=card` e envia `authorization_type`
(`card`, `apple_pay` ou `google_pay`). O payload da carteira é efêmero:
Checkout → Edge Gateway → Edge Public API → Commerce V2 → Banking V2.

Commerce só anuncia carteira para compra `ONE_TIME`, cartão ativo, produto ativo,
seller elegível e chave global correspondente ativa. Checkout Transparente e
assinaturas continuam sem carteira. Banking grava apenas `charges_card.wallet_card_id`:
`NULL` para cartão, `1` para Apple Pay e `2` para Google Pay. O payload não é
gravado em cobrança, eventos, filas ou logs.

Apple Pay valida a sessão pelo caminho Checkout → Public API → Gateway →
Commerce V2. A URL de validação é aceita somente para os hosts Apple permitidos
ou, no laboratório, para o host de mock explicitamente habilitado. Google Pay
usa o `PAYMENT_GATEWAY` anunciado pelo Commerce: `cielo` para Cielo E-commerce
e `pagarme` para Pagar.me. Cada um exige seu próprio `gatewayMerchantId`, e a
capacidade fica desabilitada se ele estiver ausente. Nenhuma carteira cria um
`payment_method` novo, uma tabela nova ou uma rota financeira paralela.

## Schema e ciclo financeiro

As migrations manuais desta entrega são:

- `service-commerce-v2/migrations/20261104120000_add_checkout_wallet_payment_methods.php`
- `services-banking-v2/migrations/20261104120000_add_wallet_card_id_to_charges_card.php`

`charges_card.wallet_card_id` classifica a origem da autorização, mas o ciclo
continua pelo mesmo `provider_transaction_id`: webhook, reembolso, disputa e
conciliação localizam a mesma cobrança. O webhook Cielo usa uma chave
determinística de evento para `PaymentId`, `ChangeType` e, quando aplicável,
`DisputeId`; a repetição idêntica não agenda processamento adicional.

## Variáveis por ambiente

As variáveis abaixo não possuem valores de produção no repositório:

- `APPLE_PAY_MERCHANT_IDENTIFIER`
- `APPLE_PAY_MERCHANT_CERTIFICATE_PATH`
- `APPLE_PAY_MERCHANT_PRIVATE_KEY_PATH`
- `GOOGLE_PAY_MERCHANT_ID`
- `CIELO_GOOGLE_PAY_GATEWAY_MERCHANT_ID`
- `PAGARME_GOOGLE_PAY_GATEWAY_MERCHANT_ID`
- `APPLE_PAY_MERCHANT_VALIDATION_MOCK_ENABLED`
- `APPLE_PAY_MERCHANT_VALIDATION_MOCK_HOST`
- `GOOGLE_PAY_TEST_MODE`

O laboratório local habilita somente `APPLE_PAY_MERCHANT_VALIDATION_MOCK_*` e
endpoints de mock temporários. Em produção, o mock permanece desligado, a
validação Apple usa mTLS e os valores vêm do cofre do ambiente.

## Laboratório manual

O diretório isolado `/root/lowify-wallet-mock-lab` contém o interceptador de
saída e o emissor de webhook. Ele responde aos cenários `success`, `refused`,
`technical_error` e `invalid_response`. Não faz parte de nenhum repositório de
produto e não deve permanecer em execução após a sessão de teste.

Para verificar uma alteração: iniciar o mock, configurar os endpoints de teste,
reconstruir apenas Commerce V2 e Banking V2, abrir checkout em navegador,
confirmar botão oficial quando houver capacidade, escolher a carteira e observar
a mesma cobrança de cartão/classificação. Em seguida, enviar webhook mock e
conferir que refund, disputa e conciliação continuam no mesmo `charges_card`.

O emissor usa somente a rede local e o formato autenticado do webhook Cielo.
O cenário `payment` deve retornar aceito; a segunda emissão, `duplicate`, deve
retornar `duplicate=true`. Para a disputa, usar a rota interna existente de
atualização de disputa contra uma cobrança fixture e confirmar que
`wallet_card_id` não mudou; restaurar o marcador de disputa ao final. Não usar
credencial, merchant, certificado, domínio ou autorização reais durante essa
verificação.
