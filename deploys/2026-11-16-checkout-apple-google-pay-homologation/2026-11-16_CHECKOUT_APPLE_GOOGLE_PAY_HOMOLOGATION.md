# Homologação — Apple Pay e Google Pay no Checkout

## Objetivo

Publicar a feature `feat/checkout-apple-google-pay` na VPS de homologação para
validar a renderização, os contratos entre Checkout, edges, Commerce e Banking
e as proteções de elegibilidade. Esta operação usa identificadores fictícios e
certificado autoassinado de laboratório: não autoriza uma transação Apple Pay
ou Google Pay real.

As duas flags globais e as duas flags do seller `pradodolucas3@gmail.com` serão
habilitadas. Os produtos permanecem desligados até uma seleção explícita no
Dashboard Seller.

## VPS e modo de rebuild

- VPS: `root@217.216.87.77`
- Modo: incremental.
- Targets mantidos como estão: `checkout-transparent-infra` e `data_layer`.
- Certificado de laboratório: diretório externo
  `/root/opt/lowify/certs/commerce-v2-wallet-lab`, montado somente pelo
  override externo do Compose. Não criar certificado, chave ou override dentro
  de qualquer repositório Git.

## Componentes e referências

| Target | Branch | Commit mínimo |
| --- | --- | --- |
| `dashboard-seller` | `feat/checkout-apple-google-pay` | `b415022c` |
| `front-checkout` | `feat/checkout-apple-google-pay` | `9c1af9e` |
| `edge-gateway` | `feat/checkout-apple-google-pay` | `acf8481` |
| `edge-public-api` | `feat/checkout-apple-google-pay` | `b88d9fe` |
| `services-commerce-v2` | `feat/checkout-apple-google-pay` | `a4e56bd` |
| `services-banking-v2` | `feat/checkout-apple-google-pay` | `36913f0` |
| `front-chat`, `front-idv`, `front-member-area`, `edge-webhook` | `main` | `origin/main` |
| `services-account`, `services-auth`, `services-banking`, `services-commerce`, `services-notification`, `services-platform`, `services-wallet` | `main` | `origin/main` |
| `checkout-transparent-api`, `checkout-transparent-billing`, `checkout-transparent-worker`, `ct-webhook` | `main` | `origin/main` |

Não executar comandos nos targets mantidos como estão, nos itens ausentes da
VPS ou nos repositórios sem mapeamento oficial.

## Banco de dados

Aplicar somente uma vez, por sessão administrativa aprovada, os DDLs aditivos
da feature: colunas `apple_pay_enabled` e `google_pay_enabled` em
`tbl_produtos`; chaves globais `checkout_apple_pay_enabled` e
`checkout_google_pay_enabled` em `system_vars`; e `wallet_card_id` com índice
em `charges_card` do Banking V2. Confirmar antes se cada coluna/chave/índice já
existe. Não executar migrations automáticas, backfill, limpeza de dados ou
rollback de schema.

## Configuração de laboratório

1. Gerar um par certificado/chave autoassinado no diretório externo indicado,
   com permissão de leitura apenas para o processo necessário.
2. Criar um override externo do Compose que monte esse diretório em modo
   somente leitura no container Commerce V2.
3. Configurar no ambiente do Commerce V2 somente valores fictícios e não
   secretos para `APPLE_PAY_MERCHANT_IDENTIFIER`, `GOOGLE_PAY_MERCHANT_ID`,
   `CIELO_GOOGLE_PAY_GATEWAY_MERCHANT_ID` e
   `PAGARME_GOOGLE_PAY_GATEWAY_MERCHANT_ID`; apontar os caminhos Apple para o
   certificado/chave montados; usar `GOOGLE_PAY_TEST_MODE=true`.
4. Não imprimir os valores do `.env`, certificado ou chave. O erro de sessão
   Apple com esses artefatos é esperado; a validação comprova somente que a
   falha é tratada sem expor material sensível.

## Sequência de integração

1. Executar a pré-checagem de todos os targets operáveis: `git status
   --porcelain=v1`, branch e origin. Parar se houver alteração local.
2. Executar `git fetch origin --prune` em todos; confirmar as seis branches da
   feature e `origin/main` para os demais targets.
3. Atualizar participantes com `git switch feat/checkout-apple-google-pay` e
   `git pull --ff-only origin feat/checkout-apple-google-pay`; atualizar todos
   os demais targets operáveis com `main` e `git pull --ff-only origin main`.
4. Reconstruir somente os edges e serviços cuja branch/commit tenha mudado.
   Para Commerce V2, usar também o override externo do laboratório. Fronts
   recebem apenas atualização Git.
5. Aplicar os DDLs, manter as chaves globais inicialmente em `0`, confirmar
   saúde dos containers e só então ativar as duas chaves globais e as duas
   flags de seller para `pradodolucas3@gmail.com`.

## Validação pós-deploy

1. Fazer login no Dashboard como `pradodolucas3@gmail.com`, abrir um produto
   avulso com cartão habilitado e confirmar os controles Apple Pay e Google
   Pay. Ativar uma wallet no produto piloto e salvar.
2. Abrir o Checkout em navegador/dispositivo compatível. Com as flags e IDs
   de laboratório, confirmar a presença dos controles quando a carteira local
   reportar compatibilidade; cartão digitado deve continuar disponível.
3. Iniciar Apple Pay e confirmar mensagem segura de indisponibilidade de
   sessão; não deve haver venda, cobrança ou token em logs funcionais.
4. Para Google Pay, usar apenas o ambiente de teste; se o Google rejeitar o
   identificador fictício, registrar a mensagem e manter cartão como fallback.
5. Confirmar que assinatura, Checkout Transparente, produto sem flag e seller
   sem flag não mostram wallet.

## Rollback

Desligar primeiro as duas chaves globais e as flags do seller. Isso remove os
botões sem apagar vendas ou estruturas. Para reverter código, voltar interfaces,
edges, Commerce e Banking para referências aprovadas em ordem inversa, sem
remover colunas, índice, chaves globais, filas ou logs. Remover o override e o
certificado de laboratório somente após os containers deixarem de referenciá-los.

## Referências

- `plans/checkout-apple-google-pay/README.md`
- `plans/checkout-apple-google-pay/04_CONTRATO_TECNICO_DE_TESTE.md`
- `.agents/integration/homologation-map.yaml`
