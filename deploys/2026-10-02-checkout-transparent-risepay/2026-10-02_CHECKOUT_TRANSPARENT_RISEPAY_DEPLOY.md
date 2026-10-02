# Deploy — RisePay no Checkout Transparente

## Objetivo

Disponibilizar Pix da RisePay no Checkout Transparente. A conta do seller é validada com o token privado, o webhook `transaction.updated` é cadastrado automaticamente e o pagamento é acompanhado tanto pelo webhook quanto pela consulta periódica.

O método aceita cobranças a partir de R$ 4,50. Cartão e Pix Automático da RisePay não fazem parte deste deploy.

## Componentes e referências

| Repositório | Diretório na VPS | Branch de deploy | Commit obrigatório | Entrega |
| --- | --- | --- | --- | --- |
| `services-checkout-transparent-api` | `/opt/lowify-ct/services-checkout-transparent-api` | `feat/checkout-transparent-risepay` | `013deca` | Gateway, credencial, fluxo de configuração, disponibilidade Pix e migration. |
| `services-checkout-transparent-worker` | `/opt/lowify-ct/services-checkout-transparent-worker` | `feat/checkout-transparent-risepay` | `c1a57a2` | Validação da conta, cadastro do webhook, criação e consulta da cobrança. |
| `edge-checkout-transparent-webhook` | `/opt/lowify-ct-webhook/edge-checkout-transparent-webhook/edge/edge-checkout-transparent-webhook` | `feat/checkout-transparent-risepay` | `f444392` | Recebimento do evento RisePay e solicitação de consulta pelo identificador da transação. |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `feat/checkout-transparent-risepay` | `b586e4c` | Cadastro da integração, guia e identidade visual do gateway. |
| `edge-public-api` | `/opt/lowify/edge/edge-public-api` | `feat/checkout-transparent-risepay` | mesmo `HEAD` da `main` | O contrato público genérico de Pix já atende a RisePay. |
| `front-checkout` | `/opt/lowify/front/front-checkout` | `feat/checkout-transparent-risepay` | mesmo `HEAD` da `main` | A tela genérica de Pix já atende a RisePay. |

## Pré-requisitos

1. Confirmar que os seis repositórios estão sem alteração local e que o `HEAD` corresponde aos commits da tabela.
2. Confirmar no CT API os valores já usados pelos gateways com webhook: `EDGE_WEBHOOK_BASE_URL` e `CHECKOUT_WEBHOOK_RECEIVER_KEY`. Eles formam a URL exclusiva registrada na RisePay para cada integração.
3. Confirmar que CT API, worker e edge de webhook usam as chaves de cifragem e a conectividade Redis já exigidas pelo Checkout Transparente. O token privado da RisePay não deve aparecer em variáveis de ambiente, logs ou comandos de deploy; ele é informado pelo seller e armazenado pela integração.
4. Confirmar acesso de saída do worker a `https://api.risepay.com.br` e acesso público da RisePay ao host configurado em `EDGE_WEBHOOK_BASE_URL`.
5. Não cadastrar uma integração RisePay antes de CT API, worker e edge de webhook estarem publicados. O cadastro dispara primeiro a validação em `GET /api/External/CompanyDetails` e depois o registro do webhook em `POST /api/External/Webhooks`.

## Banco de dados

A migration `20261001000000_add_risepay_integration_gateway.php` insere ou atualiza o gateway `risepay` em `integration_gateways`, com webhook e polling ativos a cada 60 segundos.

Aplicar a migration uma única vez pelo container do CT API e conferir o resultado antes de liberar o Dashboard:

```bash
cd /opt/lowify-ct/services-checkout-transparent-api
docker compose exec -T app php bin/hyperf.php migrate --force
docker compose exec -T app php bin/hyperf.php migrate:status
```

Não executar o `down` da migration nem remover o gateway depois que houver integrações, cobranças ou eventos RisePay registrados.

## Sequência de deploy

1. Publicar o `services-checkout-transparent-api`, aplicar a migration e confirmar que a API está saudável:

   ```bash
   cd /opt/lowify-ct/services-checkout-transparent-api
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-risepay
   git pull --ff-only origin feat/checkout-transparent-risepay
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose exec -T app php bin/hyperf.php migrate --force
   docker compose ps
   docker compose logs --tail=100 app
   ```

2. Publicar o `services-checkout-transparent-worker` antes de cadastrar qualquer integração. Ele precisa estar disponível para consumir `integration.configure`, registrar o webhook e criar/consultar Pix:

   ```bash
   cd /opt/lowify-ct/services-checkout-transparent-worker
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-risepay
   git pull --ff-only origin feat/checkout-transparent-risepay
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=100
   ```

3. Publicar o `edge-checkout-transparent-webhook` antes de ativar sellers. O webhook não confirma pagamento pelo corpo recebido: ele localiza a transação e pede a consulta autenticada ao worker:

   ```bash
   cd /opt/lowify-ct-webhook/edge-checkout-transparent-webhook/edge/edge-checkout-transparent-webhook
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-risepay
   git pull --ff-only origin feat/checkout-transparent-risepay
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=100
   ```

4. Atualizar `dashboard-seller`:

   ```bash
   cd /opt/lowify/front/dashboard-seller
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-risepay
   git pull --ff-only origin feat/checkout-transparent-risepay
   git rev-parse --short HEAD
   ```

5. Publicar `edge-public-api` e `front-checkout` somente se a operação exigir que todos os repositórios da release estejam na mesma branch. Eles não precisam de build específico da RisePay, pois não possuem alteração exclusiva nesta entrega:

   ```bash
   cd /opt/lowify/edge/edge-public-api
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-risepay
   git pull --ff-only origin feat/checkout-transparent-risepay
   git rev-parse --short HEAD

   cd /opt/lowify/front/front-checkout
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/checkout-transparent-risepay
   git pull --ff-only origin feat/checkout-transparent-risepay
   git rev-parse --short HEAD
   ```

6. Só depois dos serviços saudáveis, cadastrar uma integração de teste pelo Dashboard com o token privado da conta RisePay. A integração deve concluir os dois passos: validação da credencial e cadastro do webhook. Não marcar outra integração RisePay como padrão antes desse resultado.

## Validação pós-deploy

1. Confirmar que existe uma linha ativa em `integration_gateways` com `code = 'risepay'`, `supports_webhook = 1`, `supports_polling = 1` e intervalo de `60` segundos.
2. Salvar uma integração RisePay de teste no Dashboard. Confirmar que ela fica ativa somente após validar a conta e cadastrar o webhook `transaction.updated`.
3. Criar um produto de teste de valor igual ou superior a R$ 4,50, habilitar Checkout Transparente e selecionar a integração RisePay.
4. Abrir o checkout, gerar o Pix e conferir que a transação possui QR Code/copia e cola. Tentar valor abaixo de R$ 4,50 em ambiente de teste e confirmar a recusa antes de criar a cobrança na RisePay.
5. Pagar uma cobrança de teste. Confirmar, pelo identificador da charge, que webhook ou polling levou a mesma charge para `paid` uma única vez e que a venda, a entrega e os efeitos usuais do Commerce V2 foram concluídos sem duplicação.
6. Reenviar o evento de webhook da mesma transação, quando a RisePay permitir. A cobrança, venda e entrega devem permanecer únicas. Como verificação complementar, confirmar nos logs do edge, CT API e worker que o evento resultou em uma consulta de status da transação.
7. Verificar que token privado e resposta bruta da RisePay não aparecem nos logs do Dashboard, edge, CT API ou worker.

## Rollback

1. Interromper novos cadastros e desabilitar a integração RisePay de teste pelo Dashboard.
2. Reverter código em ordem inversa: Dashboard, edge de webhook, worker e CT API. Reconstruir os containers de cada componente retornado.
3. Preservar a migration, o gateway, integrações, cobranças e eventos já criados. Não apagar mensagens Redis, eventos de webhook ou charges pendentes; eles são necessários para localizar e reconciliar pagamentos iniciados antes do rollback.
4. Antes de reabrir o método, verificar as cobranças RisePay pendentes e a situação dos webhooks registrados na conta do seller.

## Referências

- `services-checkout-transparent-api/migrations/20261001000000_add_risepay_integration_gateway.php`
- `services-checkout-transparent-worker/app/Infrastructure/Gateways/RisePay/Client/RisePayIntegrationConfigurator.php`
- `services-checkout-transparent-worker/app/Infrastructure/Gateways/RisePay/Client/RisePayPaymentClient.php`
- `edge-checkout-transparent-webhook/app/Infrastructure/Webhook/Resolver/RisePayWebhookPaymentStatusCheckResolver.php`
- [Documentação da API RisePay](https://docs.risepay.com.br/risepay-api)
