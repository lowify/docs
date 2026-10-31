# Deploy — Checkout Transparente: cartão

## Objetivo

Publicar o pagamento por cartão no Checkout Transparente para integrações Mercado Pago, Pagar.me e Efí, sem encaminhar PAN, CVV ou token de cartão ao Commerce V2. O fluxo cria a venda pendente no Commerce, cria e confirma a charge no Checkout Transparente e confirma a venda uma única vez quando o gateway retornar pagamento aprovado.

Esta entrega também publica a consulta de erros da integração no Dashboard, a reconciliação de tentativas Efí cujo retorno foi perdido e a expiração de tentativas de cartão que ficaram pendentes antes de chegar ao gateway.

Fora do escopo: cartão RisePay, Woovi e Kiwify; split; onboarding e regras do cartão convencional; e recorrência de cartão. As regras atuais de cartão e recorrência do Banking V2 permanecem no fluxo convencional e não podem ser substituídas pelo fluxo transparente.

## Componentes e referências

| Repositório | Host | Diretório de produção | Branch | Commit de deploy | Papel |
| --- | --- | --- | --- | --- | --- |
| `services-checkout-transparent-api` | `80.190.72.228` | `/opt/lowify-ct/services/services-checkout-transparent-api` | `feat/checkout-transparent-card` | `2eaf28f` | Contrato de charge/tentativa, schema CT, idempotência, confirmação, erros sanitizados e processos de expiração. |
| `services-checkout-transparent-worker` | `80.190.72.241` | `/opt/lowify-ct/services-checkout-transparent-worker` | `feat/checkout-transparent-card` | `6f06dab` | Cria e consulta pagamentos Mercado Pago, Pagar.me e Efí; reconcilia timeout/5xx Efí por `custom_id`. |
| `edge-checkout-transparent-webhook` | `80.190.72.228` | `/opt/lowify-ct-webhook/edge/edge-checkout-transparent-webhook` | `feat/checkout-transparent-card` | `7a13141` | Recebe eventos dos provedores e solicita a consulta/normalização da charge. |
| `services-commerce-v2` | `144.126.149.57` | `/opt/lowify/services/service-commerce-v2` | `feat/checkout-transparent-card` | `ca837fa` | Cria venda pendente transparente, recebe a confirmação e preserva o fluxo convencional de cartão/recorrência. |
| `edge-webhook` | `144.126.149.57` | `/opt/lowify/edge/edge-webhook` | `feat/checkout-transparent-card` | `6a4d8ed` | Recebe a confirmação autenticada do CT e a encaminha ao Commerce. |
| `edge-public-api` | `144.126.149.57` | `/opt/lowify/edge/edge-public-api` | `feat/checkout-transparent-card` | `01a75ed` | Expõe disponibilidade, cria venda/charge/tentativa e encaminha consulta de erros autenticada. |
| `edge-gateway` | `144.126.149.57` | `/opt/lowify/edge/edge-gateway` | `feat/checkout-transparent-card` | `d375dc2` | Roteia os contratos CT entre Dashboard, Public API e CT API. |
| `front-checkout` | `144.126.149.57` | `/opt/lowify/front/front-checkout` | `feat/checkout-transparent-card` | `55e99cd` | Tokeniza no navegador e envia somente token transitório, endereço e dados permitidos. |
| `dashboard-seller` | `144.126.149.57` | `/opt/lowify/front/dashboard-seller` | `feat/checkout-transparent-card` | `7967c7b0` | Configura cartão por método de integração e apresenta erros sanitizados. |

`services-banking-v2` não é um componente de código desta publicação. Ele é referência do contrato de provedores e continua atendendo apenas o checkout convencional. Não trocar sua branch nem reiniciá-lo por causa desta feature.

`services-checkout-transparent-billing` permanece em `80.190.72.228`, mas não tem alteração nesta entrega e não recebe troca de branch, rebuild ou migration.

## Alterações incluídas

O caminho publicado é:

```text
Front Checkout -> Edge Public API -> Commerce V2 (venda pendente)
-> CT API (charge e tentativa) -> fila checkout-transparent:gateway:instructions
-> CT Worker -> provedor -> fila checkout-transparent:gateway:results
-> CT API -> Edge Webhook -> Commerce V2 (venda paid e entrega)
```

- A disponibilidade seleciona a integração do seller por método. `card_credit` não usa `gateway_default_checkout_card`, Cielo, split, PSP ou onboarding do cartão convencional.
- Mercado Pago e Pagar.me tokenizam no navegador; o worker cria Orders. Efí tokeniza com `payment-token-efi` e o worker cria cobrança One Step.
- A tentativa possui referência/idempotência própria, `nonce` e fingerprint da requisição. Reenvio idêntico é seguro; reutilização de nonce com outro conteúdo é recusada.
- Token, PAN, CVV, segredo e resposta bruta de tokenização não são persistidos nem enviados para o Commerce. Logs e o relatório de integração removem credenciais e dados pessoais sensíveis.
- Falha ou recusa permite nova tentativa na mesma charge, sem nova venda. Resultado confiável tardio pode levar a charge de `failed` para `paid`, sem duplicar confirmação, entrega ou financeiro.
- O worker Efí consulta por `custom_id` após timeout ou `5xx` antes de concluir que uma nova cobrança pode ser criada. O comando `checkout:expire-stale-card-attempts` permite saneamento manual; o processo automático expira tentativas que nunca foram despachadas.
- O Dashboard consulta o relatório pelo caminho autenticado Dashboard -> Gateway -> Public API -> CT API. Nenhum segredo é devolvido à interface.

## Pré-requisitos

1. Confirmar que as nove branches e commits da tabela estão no remoto. Em cada diretório, interromper se `git status --porcelain=v1` retornar qualquer linha antes da troca de branch.
2. CT API, worker e edge de webhook usam o banco e Redis próprios do Checkout Transparente. Não limpar Redis, filas, DLQ, charges, tentativas ou mensagens durante o deploy.
3. Preservar as credenciais privadas já cadastradas por integração. Nunca registrar valores de `access_token`, `secret_key`, Client ID, Client Secret, certificado Efí, token, PAN ou CVV.
4. Confirmar que o domínio `checkout.lowify.com.br` está autorizado na conta Pagar.me do seller piloto e que cada integração possui as credenciais já necessárias ao seu provedor. A ativação de `card_credit` é explícita por integração; publicar código não habilita cartão para sellers.
5. No CT API, manter habilitados os processos padrão de charge e, salvo decisão operacional registrada, `CHECKOUT_CARD_ATTEMPT_EXPIRATION_ENABLED=true`. Os valores padrão são varredura a cada 30 segundos e expiração após 5 minutos; os nomes das variáveis adicionais são `CHECKOUT_CARD_ATTEMPT_EXPIRATION_SCAN_INTERVAL_SECONDS` e `CHECKOUT_CARD_ATTEMPT_PENDING_TIMEOUT_MINUTES`.
6. No worker, confirmar `CHECKOUT_WORKER_ENABLED=true` e os nomes de fila compatíveis: `checkout-transparent:gateway:instructions` e `checkout-transparent:gateway:results`.

## Banco de dados

### CT API — execução pelo serviço

As migrations da CT API são aditivas e devem ser executadas pelo comando do próprio serviço após a imagem nova estar em execução. Não executar `down`, não inserir registros manualmente em `migrations` e não apagar estruturas se houver rollback de código.

As migrations relevantes para cartão incluem `20260916000000_add_payment_methods_and_charge_installments.php`, `20260916000100_add_payment_method_id_to_charge_attempts.php`, `20261012000000_create_integration_errors.php`, `20261016010000_add_card_attempt_nonce_to_charges.php`, `20261022000000_add_rate_limit_keys_to_charge_attempts.php` e `20261029000000_add_request_fingerprint_to_charge_attempts.php`, além das migrations CT anteriores da mesma branch que ainda não estejam aplicadas.

Depois das migrations, executar o backfill idempotente de Pix. Ele cria somente os métodos/chaves faltantes a partir das estruturas legadas; não habilita cartão.

```bash
cd /opt/lowify-ct/services/services-checkout-transparent-api
docker compose exec -T app php bin/hyperf.php migrate --force
docker compose exec -T app php bin/hyperf.php migrate:status
docker compose exec -T app php bin/hyperf.php integration-payment-methods:backfill-pix --dry-run
docker compose exec -T app php bin/hyperf.php integration-payment-methods:backfill-pix
docker compose exec -T app php bin/hyperf.php integration-payment-methods:backfill-pix --dry-run
```

O segundo `--dry-run` deve indicar que não há novos métodos/chaves a criar para os registros já tratados. Se uma migration falhar, não contornar a falha via SQL na tabela `migrations`; parar e corrigir a divergência de schema.

### Banking V2 e banco Lowify — execução manual

As migrations de Banking V2 e do banco Lowify (usado pelo Commerce V2) são operadas manualmente. Não executar `migrate` amplo nesses dois bancos como parte deste deploy.

Esta branch não adiciona migration nova em `services-banking-v2` nem em `services-commerce-v2`; portanto, não há DDL destes dois bancos a aplicar especificamente para o cartão transparente. Antes de liberar o piloto, o operador deve confirmar manualmente que os schemas já publicados contêm as estruturas das versões selecionadas, em especial `sales.checkout_transparent_integration_id` no banco Lowify. Caso exista migration pendente aprovada para Banking V2 ou Lowify no ambiente, ela deve ser aplicada pelo procedimento manual próprio, registrada na evidência do deploy e validada antes de prosseguir. Não misturar migrations de outro deploy neste roteiro sem referência e validação explícitas.

## Sequência de deploy

Modo de rebuild: incremental, com rebuild obrigatório para cada componente empacotado que tiver a revisão atualizada. Em cada etapa, confirme o commit mínimo com `git merge-base --is-ancestor <commit> HEAD`; se o comando falhar, pare. Os comandos abaixo não descartam alterações locais.

### 1. CT Worker — `80.190.72.241`

Publicar o consumidor antes de permitir que a API publique as novas instruções de cartão.

```bash
cd /opt/lowify-ct/services-checkout-transparent-worker
git status --porcelain=v1
git fetch origin --prune
git switch feat/checkout-transparent-card
git pull --ff-only origin feat/checkout-transparent-card
git merge-base --is-ancestor 408a41a HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 app
```

### 2. CT API e migrations — `80.190.72.228`

```bash
cd /opt/lowify-ct/services/services-checkout-transparent-api
git status --porcelain=v1
git fetch origin --prune
git switch feat/checkout-transparent-card
git pull --ff-only origin feat/checkout-transparent-card
git merge-base --is-ancestor e6e2e87 HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose exec -T app php bin/hyperf.php migrate --force
docker compose exec -T app php bin/hyperf.php migrate:status
docker compose exec -T app php bin/hyperf.php integration-payment-methods:backfill-pix
docker compose ps
docker compose logs --tail=100 app
```

Confirmar nos logs o início sem erro do processo `stale_card_attempt_expiration`. Não executar o comando de expiração manual como rotina de deploy: ele é somente recuperação de incidente, quando houver tentativas antigas a tratar.

### 3. Commerce V2 — `144.126.149.57`

```bash
cd /opt/lowify/services/service-commerce-v2
git status --porcelain=v1
git fetch origin --prune
git switch feat/checkout-transparent-card
git pull --ff-only origin feat/checkout-transparent-card
git merge-base --is-ancestor ca837fa HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100
```

### 4. Edges e webhook CT — `80.190.72.228` e `144.126.149.57`

```bash
cd /opt/lowify-ct-webhook/edge/edge-checkout-transparent-webhook
git status --porcelain=v1
git fetch origin --prune
git switch feat/checkout-transparent-card
git pull --ff-only origin feat/checkout-transparent-card
git merge-base --is-ancestor e80026c HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps

cd /opt/lowify/edge/edge-webhook
git status --porcelain=v1
git fetch origin --prune
git switch feat/checkout-transparent-card
git pull --ff-only origin feat/checkout-transparent-card
git merge-base --is-ancestor 6a4d8ed HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps

cd /opt/lowify/edge/edge-public-api
git status --porcelain=v1
git fetch origin --prune
git switch feat/checkout-transparent-card
git pull --ff-only origin feat/checkout-transparent-card
git merge-base --is-ancestor 01a75ed HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps

cd /opt/lowify/edge/edge-gateway
git status --porcelain=v1
git fetch origin --prune
git switch feat/checkout-transparent-card
git pull --ff-only origin feat/checkout-transparent-card
git merge-base --is-ancestor d375dc2 HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

### 5. Front Checkout e Dashboard — `144.126.149.57`

```bash
cd /opt/lowify/front/front-checkout
git status --porcelain=v1
git fetch origin --prune
git switch feat/checkout-transparent-card
git pull --ff-only origin feat/checkout-transparent-card
git merge-base --is-ancestor 55e99cd HEAD
git rev-parse --short HEAD

cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git fetch origin --prune
git switch feat/checkout-transparent-card
git pull --ff-only origin feat/checkout-transparent-card
git merge-base --is-ancestor 1cea1e46 HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

Não ligar `card_credit` em massa. Ativar primeiro uma única integração de seller interno/piloto depois da validação técnica.

## Validação pós-deploy

1. No Dashboard, abra uma integração de teste. Confirme que Pix continua visível e que cartão só pode ser habilitado para um provedor suportado. Salve a Public Key/configuração pública e confirme que nenhum segredo é mostrado na tela.
2. No produto de teste `ONE_TIME`, habilite Checkout Transparente e cartão, com parcelas dentro do limite configurado. Abra o checkout e confira que a opção de cartão aparece sem remover Pix quando ambos estiverem habilitados.
3. Faça uma compra controlada com cartão de teste autorizado. O comprador deve ver sucesso; a venda, charge e entrega devem ficar pagas uma única vez. Recarregar a página ou reenviar o formulário não pode criar segunda venda nem segunda cobrança.
4. Faça uma recusa controlada. A venda deve permanecer pendente e o comprador deve conseguir usar outro token na mesma charge, sem duplicar venda, entrega, item financeiro ou notificação.
5. Para uma tentativa Efí controlada, confira que uma indisponibilidade transitória não resulta imediatamente em segunda cobrança: o worker deve reconciliar por `custom_id` antes de nova criação. Não simular isso com cartão real em produção sem janela controlada.
6. No Dashboard, abra o relatório de erros da mesma integração. Ele deve mostrar mensagem compreensível e detalhes sanitizados; não podem aparecer token, PAN, CVV, segredo, certificado ou Bearer token.
7. Como conferência técnica complementar, confira que CT API e worker estão saudáveis e que as filas `checkout-transparent:gateway:instructions` e `checkout-transparent:gateway:results` estão sendo consumidas. Não consumir, apagar ou mover mensagens manualmente.

Se qualquer resultado visível não corresponder, desligue `card_credit` somente na integração piloto, preserve as evidências e não amplie a liberação para outros sellers.

## Rollback

1. Desabilitar `card_credit` nas integrações piloto pelo Dashboard. Isso impede novas tentativas sem apagar charges já iniciadas.
2. Reverter primeiro Front Checkout e Dashboard, depois Gateway, Public API e os webhooks. Assim a interface deixa de iniciar novas tentativas enquanto os componentes internos ainda conseguem concluir as existentes.
3. Manter CT API, CT Worker e Commerce V2 na revisão compatível até reconciliar charges/tentativas pendentes e mensagens das filas. Commerce V2 é o último componente interno a retornar, porque conclui a venda e a entrega.
4. Não executar `down`, não remover migrations, não apagar `integration_payment_methods`, `integration_payment_method_keys`, `charge_attempts`, `charge_installments`, `integration_errors`, charges, vendas, filas ou DLQ. As estruturas são aditivas e os dados são necessários para auditoria e reconciliação.
5. Banking V2 permanece fora do rollback desta feature. Não alterar suas regras de cartão convencional/recorrência como tentativa de corrigir um problema do Checkout Transparente.

## Referências

- `plans/checkout-transparent-card/README.md`
- `plans/checkout-transparent-card/01_ESTADO_ATUAL_E_FRONTEIRAS.md`
- `plans/checkout-transparent-card/02_CONTRATO_DADOS_E_FILAS.md`
- `plans/checkout-transparent-card/03_IMPLEMENTACAO_ROLLOUT_E_ACEITE.md`
- `features/checkout-transparent-card/README.md`
