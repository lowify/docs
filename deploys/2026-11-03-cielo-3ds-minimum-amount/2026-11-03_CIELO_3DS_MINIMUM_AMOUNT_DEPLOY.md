# Deploy — 3DS Cielo por valor mínimo

## Objetivo

Permitir que um administrador defina, em reais, o valor mínimo a partir do qual o Checkout Lowify deve executar a autenticação 3DS da Cielo. O valor é persistido em `system_vars` como decimal; o Commerce V2 o converte para centavos somente em memória, o expõe no contexto do checkout e aplica a validação autoritativa antes de criar a cobrança.

`R$ 0,00` desativa a exigência para todas as vendas. `R$ 0,01` exige 3DS para qualquer venda Cielo com valor positivo. A entrega não habilita 3DS por si só: a configuração técnica e as credenciais Cielo existentes continuam obrigatórias.

## Componentes e referências

| Componente | Branch de deploy | Commit |
| --- | --- | --- |
| `services-commerce-v2` | `feat/cielo-3ds-minimum-amount` | Registrar antes do deploy. |
| `dashboard-seller` | `feat/cielo-3ds-minimum-amount` | Registrar antes do deploy. |
| `front-checkout` | `feat/cielo-3ds-minimum-amount` | Registrar antes do deploy. |

`edge-gateway`, `edge-public-api` e `services-banking-v2` não recebem alteração nesta entrega. Eles preservam os contratos atuais de encaminhamento, contexto e cobrança.

## Alterações incluídas

- O painel Admin > Configurações > Pagamentos passa a aceitar “Exigir 3DS Cielo a partir de” em BRL e salva `cielo_3ds_minimum_amount` em `system_vars` com duas casas decimais.
- O Commerce V2 inclui `checkout_options.card.security.three_ds.minimum_amount_cents` no contexto quando a Cielo é o gateway de cartão.
- O front compara o total exibido com o limite recebido e só chama o desafio 3DS quando a faixa exige autenticação.
- O Commerce V2 recalcula o total final, incluindo oferta, desconto e order bumps, e recusa a cobrança Cielo sem os campos 3DS necessários acima do limite.
- O Banking V2 continua validando e encaminhando `ExternalAuthentication` quando ele for recebido; não recebe regra de valor nesta entrega.

## Pré-requisitos

1. Confirmar que as credenciais Cielo 3DS já estão configuradas no `services-banking-v2`: `CIELO_3DS_ENABLED`, `CIELO_3DS_CLIENT_ID`, `CIELO_3DS_CLIENT_SECRET`, `CIELO_3DS_ESTABLISHMENT_CODE`, `CIELO_3DS_MERCHANT_NAME` e `CIELO_3DS_MCC`. Não registrar valores no plano ou em logs.
2. Confirmar que `gateway_default_checkout_card` aponta para `cielo_ecommerce` antes do teste funcional.
3. O operador deve registrar o commit final de cada branch na tabela acima antes de publicar.

## Banco de dados

Não há migration, DDL ou seed nesta entrega. A chave `cielo_3ds_minimum_amount` não é criada antecipadamente: ela é criada pelo upsert existente quando o administrador salvar a configuração pela primeira vez.

Enquanto a chave não existir, o Commerce V2 considera o limite como `0` e a exigência seletiva de 3DS permanece desativada.

## Sequência de deploy

1. Publicar o Commerce V2 antes do front, para que o contexto já entregue o limite em centavos.

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git fetch origin --prune
   git switch feat/cielo-3ds-minimum-amount
   git pull --ff-only origin feat/cielo-3ds-minimum-amount
   docker compose up -d --build
   docker compose ps
   ```

2. Publicar o Dashboard Seller para disponibilizar o campo administrativo.

   ```bash
   cd /opt/lowify/front/dashboard-seller
   git fetch origin --prune
   git switch feat/cielo-3ds-minimum-amount
   git pull --ff-only origin feat/cielo-3ds-minimum-amount
   ```

3. Publicar o Front Checkout após o Commerce estar saudável.

   ```bash
   cd /opt/lowify/front/front-checkout
   git fetch origin --prune
   git switch feat/cielo-3ds-minimum-amount
   git pull --ff-only origin feat/cielo-3ds-minimum-amount
   ```

## Validação pós-deploy

1. Faça login como administrador, abra Configurações > Pagamentos e informe um valor de teste, por exemplo `R$ 100,00`. Clique em salvar e confirme a mensagem de sucesso; recarregue a página e confirme que o mesmo valor é exibido.
2. Em um produto de teste com cartão Cielo, faça uma tentativa abaixo de R$ 100,00. O checkout não deve mostrar o desafio 3DS e a tentativa deve seguir o fluxo normal de cartão.
3. Faça uma tentativa de R$ 100,00 ou maior. O checkout deve apresentar o fluxo 3DS antes de processar o pagamento; conclua-o com dados de teste permitidos pela Cielo.
4. Faça uma venda cuja seleção de order bump leve o total de abaixo para acima do limite. Confirme que o 3DS é solicitado pelo valor final exibido.
5. Defina o campo como `R$ 0,00`, salve e abra um novo checkout. Confirme que o desafio deixa de ser solicitado.
6. Como conferência técnica opcional, verificar que uma tentativa acima do limite sem `Cavv`, `Eci` e `Version` recebe `checkout_cielo_3ds_required`. Não limpar filas, Redis ou registros de pagamento durante a validação.

## Rollback

Para interromper imediatamente a exigência seletiva, o administrador pode salvar `R$ 0,00`; isso não remove nem altera cobranças existentes.

Se for necessário reverter código, publicar as revisões anteriores na ordem inversa: `front-checkout`, `dashboard-seller`, `services-commerce-v2`. Não apagar a chave em `system_vars`, transações, logs, mensagens de fila ou dados de cobrança. A chave pode permanecer com `0.00` após o rollback.
