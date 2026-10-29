# Deploy — Cartão e Pix Automático no Checkout Transparente

## Objetivo

Publicar o Checkout Transparente com três meios independentes por integração: Pix, cartão de crédito e Pix Automático. O seller passa a configurar esses meios no modal **Métodos de pagamento**, escolher uma integração padrão para cada meio e consultar os erros da própria integração.

Para produtos de pagamento único, o checkout usa Pix e/ou cartão. Para produtos de assinatura, usa somente Pix Automático. A seleção é feita pelo método padrão ativo do seller, sem reutilizar a configuração do checkout normal da Lowify.

Cartão está disponível para Mercado Pago, Pagar.me e Efí. Pix Automático está disponível para Woovi e Efí. O Pix da RisePay pertence ao deploy próprio já publicado; o cartão da RisePay permanece desabilitado nesta entrega.

## Componentes e referências

Todos os componentes abaixo devem receber a revisão aprovada que contém a entrega. Antes de iniciar, registrar o resultado de `git rev-parse --short HEAD` de cada diretório na evidência do deploy.

| Repositório | Diretório na VPS | Entrega |
| --- | --- | --- |
| `services-checkout-transparent-api` | `/opt/lowify-ct/services/services-checkout-transparent-api` | Schema, métodos por integração, cartão, assinaturas Pix Automático, seleção de disponibilidade, scheduler Efí e relatório de erros. |
| `services-checkout-transparent-worker` | `/opt/lowify-ct/services/services-checkout-transparent-worker` | Configuração dos provedores, criação e consulta de cartão, autorizações e cobranças futuras. |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | Consumo das ações de assinatura e confirmação da venda inicial ou recorrente. |
| `edge-checkout-transparent-webhook` | `/opt/lowify-ct-webhook/edge-checkout-transparent-webhook/edge/edge-checkout-transparent-webhook` | Recebimento dos webhooks de cartão e Pix Automático. |
| `edge-webhook` | `/opt/lowify/edge/edge-webhook` | Recebimento autenticado da confirmação do CT e publicação da ação de assinatura para o Commerce V2. |
| `edge-public-api` | `/opt/lowify/edge/edge-public-api` | Contrato público de disponibilidade, tentativa de cartão, assinatura Pix Automático e métodos da integração. |
| `edge-gateway` | `/opt/lowify/edge/edge-gateway` | Encaminhamento autenticado do Dashboard, inclusive relatório de erros. |
| `front-checkout` | `/opt/lowify/front/front-checkout` | Formulários e tokenização de cartão; fluxo de Pix Automático. |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | Cadastro, modal de métodos, guias e relatório de erros. |

O `services-commerce-v2` e o `edge-webhook` fazem parte desta entrega: o CT encaminha a confirmação de cobrança de assinatura ao edge-webhook principal, que publica a ação consumida pelo Commerce V2. `services-banking-v2` e o checkout normal não possuem código a publicar neste corte.

No Commerce V2, a revisão aprovada deve resultar da integração da feature com a `main` atual. Não publicar uma branch de feature antiga sobre a `main`, pois as correções mais recentes de valor bruto e taxas das vendas recorrentes precisam ser preservadas.

## Pré-requisitos

1. Confirmar que todos os nove diretórios estão sem alteração local. Se `git status --porcelain=v1` mostrar alguma linha, parar e resolver antes do `git switch`.
2. Confirmar que a branch já contém a revisão aprovada e enviada ao remoto. Esta documentação não autoriza publicar arquivos que ainda estejam apenas na máquina de desenvolvimento.
3. Não criar nem alterar segredo por comando de deploy. Credenciais de Pix, cartão e Pix Automático são informadas pelo seller no Dashboard e ficam cifradas pela integração.
4. A infraestrutura já usada pelo Checkout Transparente deve estar saudável: MariaDB, Redis, CT API, worker e edge de webhook. O deploy não cria novo serviço externo.
5. Manter `CHECKOUT_RISEPAY_CARD_ENABLED=false`. A ativação do cartão RisePay exige processo separado de segurança e não faz parte deste corte.

## Banco de dados

Aplicar as migrations somente no container da CT API. Elas são aditivas: não executar `down`, não apagar tabelas e não marcar migration manualmente como executada.

| Migration | Efeito |
| --- | --- |
| `20260916000000_add_payment_methods_and_charge_installments.php` | Cria métodos e chaves por integração, parcelas e os campos de cartão em charges e tentativas. |
| `20260916000100_add_payment_method_id_to_charge_attempts.php` | Vincula cada tentativa ao método de pagamento. |
| `20260925000000_create_pix_automatic_subscriptions.php` | Cria as autorizações de Pix Automático. |
| `20260928110000_add_efi_pix_automatic_fields.php` | Acrescenta os dados de recorrência Efí. |
| `20260928120000_create_checkout_subscription_charges.php` | Cria o registro de cada cobrança futura da assinatura. |
| `20260929170000_add_checkout_subscription_payer.php` | Acrescenta os dados necessários da pessoa pagadora. |
| `20261012000000_create_integration_errors.php` | Cria o relatório de erros sanitizados por integração. |

Depois das migrations, executar o backfill de Pix. Ele cria somente o que falta, copia as chaves legadas para o método Pix e pode ser executado novamente sem duplicar registros.

```bash
cd /opt/lowify-ct/services/services-checkout-transparent-api
docker compose exec -T app php bin/hyperf.php migrate --force
docker compose exec -T app php bin/hyperf.php migrate:status
docker compose exec -T app php bin/hyperf.php integration-payment-methods:backfill-pix --dry-run
docker compose exec -T app php bin/hyperf.php integration-payment-methods:backfill-pix
docker compose exec -T app php bin/hyperf.php integration-payment-methods:backfill-pix --dry-run
```

O último `--dry-run` deve informar zero novos métodos e chaves para as integrações já tratadas. Se uma migration falhar, não continuar para o Dashboard e não contornar o erro inserindo registros na tabela `migrations`: registrar o nome da migration e corrigir a divergência de schema primeiro.

## Sequência de deploy

Em cada bloco, `git rev-parse --short HEAD` deve resultar na revisão aprovada da branch. Os comandos abaixo não descartam alterações locais: se houver divergência, eles param.

**Rebuild obrigatório:** qualquer alteração em serviço empacotado em imagem (CT API, worker, webhooks, Commerce, Edge Public API ou Edge Gateway) só entra em execução após `docker compose up -d --build` no respectivo diretório e a confirmação de `docker compose ps`. Reiniciar um container sem rebuild pode manter o código anterior; não considerar um teste técnico válido antes de confirmar que o arquivo alterado está presente no container em execução.

1. Publicar a CT API, aplicar migrations e executar o backfill antes de expor o novo Dashboard:

   ```bash
   cd /opt/lowify-ct/services/services-checkout-transparent-api
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-card
   git pull --ff-only origin feat/checkout-transparent-card
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose exec -T app php bin/hyperf.php migrate --force
   docker compose exec -T app php bin/hyperf.php migrate:status
   docker compose exec -T app php bin/hyperf.php integration-payment-methods:backfill-pix
   docker compose ps
   docker compose logs --tail=100 app
   ```

2. Publicar o worker. Ele deve estar ativo antes de configurar cartão ou Pix Automático, pois valida credenciais, cria cobranças e agenda as cobranças futuras da Efí:

   ```bash
   cd /opt/lowify-ct/services/services-checkout-transparent-worker
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-card
   git pull --ff-only origin feat/checkout-transparent-card
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=100
   ```

3. Publicar o Commerce V2 antes dos produtores de ações de assinatura. A revisão aprovada já deve conter a feature integrada à `main`:

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git status --porcelain=v1
   git fetch origin --prune
   git switch main
   git pull --ff-only origin main
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=100 service-commerce-v2
   ```

4. Publicar o edge de webhook do Checkout Transparente antes de ativar sellers. Ele recebe eventos de cartão e Pix Automático e pede a confirmação pelo fluxo autenticado:

   ```bash
   cd /opt/lowify-ct-webhook/edge-checkout-transparent-webhook/edge/edge-checkout-transparent-webhook
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-card
   git pull --ff-only origin feat/checkout-transparent-card
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=100
   ```

5. Publicar o edge-webhook principal depois do Commerce V2. Ele recebe a confirmação autenticada da assinatura e a encaminha para a fila consumida pelo Commerce:

   ```bash
   cd /opt/lowify/edge/edge-webhook
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-card
   git pull --ff-only origin feat/checkout-transparent-card
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=100 edge-webhook
   ```

6. Publicar o Edge Public API e o Edge Gateway. Eles precisam estar disponíveis antes da interface, pois expõem os contratos públicos e autenticados dos métodos e dos erros:

   ```bash
   cd /opt/lowify/edge/edge-public-api
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-card
   git pull --ff-only origin feat/checkout-transparent-card
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=100

   cd /opt/lowify/edge/edge-gateway
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-card
   git pull --ff-only origin feat/checkout-transparent-card
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=100
   ```

7. Atualizar o Front Checkout e o Dashboard Seller. Eles não exigem build próprio neste deploy:

   ```bash
   cd /opt/lowify/front/front-checkout
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-card
   git pull --ff-only origin feat/checkout-transparent-card
   git rev-parse --short HEAD

   cd /opt/lowify/front/dashboard-seller
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-card
   git pull --ff-only origin feat/checkout-transparent-card
   git rev-parse --short HEAD
   ```

8. Só após os componentes saudáveis, configurar uma integração interna de teste no Dashboard. Primeiro confirmar Pix; depois habilitar somente o método que será homologado, usando o modal **Métodos de pagamento**.

## Variáveis de ambiente

Além das credenciais dos meios de pagamento, o Commerce V2 precisa conseguir confirmar para a CT API que criou uma venda de parcela recorrente. Declarar no Commerce V2, antes do rebuild:

```text
CHECKOUT_TRANSPARENT_INTERNAL_API_BASE_URL=<URL interna da CT API>
CHECKOUT_TRANSPARENT_INTERNAL_API_TOKEN=<mesmo valor de CHECKOUT_API_INTERNAL_TOKEN da CT API>
CHECKOUT_TRANSPARENT_INTERNAL_API_HMAC_SECRET=<mesmo valor de CHECKOUT_API_HMAC_SECRET da CT API>
CHECKOUT_TRANSPARENT_INTERNAL_API_TIMEOUT_SECONDS=5
```

Não registrar os valores dos segredos neste documento, em logs ou no Git. A URL deve alcançar a rota interna da CT API sem depender de DNS público. A ausência de qualquer uma dessas variáveis mantém a parcela sem billing e a recuperação do CT volta a tentar a entrega; não liberar recorrência enquanto o callback não for validado.

O Pix Automático Efí é iniciado pelos processos da CT API e vem habilitado por padrão. Só verificar `CHECKOUT_EFIBANK_PIX_AUTOMATIC_ENABLED` se esse ambiente já possuir a variável definida como `false`; nesse caso, removê-la ou ajustá-la para `true` antes de reiniciar a CT API. As demais variáveis `CHECKOUT_EFIBANK_PIX_AUTOMATIC_*` são ajustes operacionais opcionais e não devem ser criadas para o deploy padrão.

## Validação pós-deploy

1. Na CT API, confirmar em `migrate:status` que as sete migrations da tabela foram aplicadas e que o segundo `backfill-pix --dry-run` não criaria registros.
2. No Dashboard, abrir uma integração ativa e confirmar que **Métodos de pagamento** mostra somente os métodos suportados pelo gateway. Pix deve continuar ativo; cartão e Pix Automático são opcionais.
3. Escolher uma integração padrão de Pix, outra de cartão e outra de Pix Automático. Confirmar que cada alteração preserva os defaults dos outros dois métodos e que a listagem identifica o método padrão ao lado do provedor.
4. Abrir o relatório de erros de uma integração. A lista deve trazer apenas erros daquele seller, com data, origem, resumo e detalhes sanitizados ao clicar em **Ver mais**.
5. Criar um produto `ONE_TIME` interno com Checkout Transparente, Pix e cartão habilitados. Abrir o checkout e confirmar que Pix e cartão disponíveis vêm das respectivas integrações padrão. Para Pagar.me, conferir que as parcelas respeitam o máximo e o valor mínimo configurados; para Mercado Pago e Efí, confirmar tokenização sem expor dados brutos do cartão.
6. Criar um produto `SUBSCRIPTION` interno com Checkout Transparente. Abrir o checkout e confirmar que ele oferece somente Pix Automático da integração padrão. Homologar uma autorização com Woovi e uma com Efí em conta permitida; confirmar que a primeira parcela é única e que webhook ou consulta atualiza a mesma assinatura.
7. Para Efí, conferir nos logs da CT API, após criar a assinatura, que os processos `efibank_subscription_scheduler` e `efibank_subscription_polling` iniciaram sem erro. Não antecipar uma cobrança futura em produção sem autorização operacional; a validação da parcela futura deve usar a conta de teste autorizada.
8. Para uma assinatura Pix Automático, confirmar que o CT chama o `edge-webhook` principal e que o processo `commerce_subscription_actions_queue` do Commerce V2 consome a ação. A venda, a parcela e a entrega devem ser criadas uma única vez; não publicar nem consumir mensagens Redis manualmente.
9. Repetir um evento de webhook de teste ou consultar novamente a mesma cobrança. Charge, venda, entrega e faturamento devem continuar únicos. Nos logs e no relatório de erros, não podem aparecer token, cartão, documento, endereço, senha, chave ou certificado.

## Rollback

1. Antes de reverter, interromper novas ativações de cartão e Pix Automático pelo Dashboard. Identificar charges de cartão pendentes e assinaturas Pix Automático ativas; esses registros precisam continuar reconciliáveis.
2. Reverter primeiro Dashboard Seller e Front Checkout, depois Edge Gateway, Edge Public API e edge de webhook. Assim nenhuma nova tentativa é iniciada pela interface enquanto os serviços internos ainda conseguem concluir pendências.
3. Manter CT API, worker, os dois webhooks e Commerce V2 na revisão compatível até confirmar que não há tentativa, assinatura, cobrança futura ou ação de assinatura pendente. Só então retornar os produtores à revisão anterior; o Commerce V2 deve ser o último componente interno a voltar, depois de consumir as ações restantes.
4. Não executar `down`, não remover `integration_errors`, métodos, chaves, tentativas, assinaturas, cobranças futuras ou mensagens de fila. As migrations são aditivas e os dados são necessários para auditoria e reconciliação.
5. Antes de reabrir os métodos, conferir o estado dos webhooks no provedor, as cobranças pendentes e os logs de scheduler/polling da Efí.

## Referências

- `plans/checkout-transparent-card/README.md`
- `plans/checkout-transparent-card/02_CONTRATO_DADOS_E_FILAS.md`
- `plans/checkout-transparent-card/03_IMPLEMENTACAO_ROLLOUT_E_ACEITE.md`
- `plans/checkout-transparent-pix-automatic/README.md`
- `services-checkout-transparent-api/migrations/20260916000000_add_payment_methods_and_charge_installments.php`
- `services-checkout-transparent-api/migrations/20260925000000_create_pix_automatic_subscriptions.php`
- `services-checkout-transparent-api/migrations/20261012000000_create_integration_errors.php`
