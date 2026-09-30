# Deploy — Administração de comunicações e Cashflow do Checkout Transparente

## Objetivo

Publicar a administração de templates de e-mail e fluxos WhatsApp Meta, o relatório de volumes de comunicação e a etapa **Cash In CT** do Relatório Cashflow. Esta entrega é exclusivamente administrativa; não altera o checkout, a criação de cobranças nem o processamento de pagamentos.

## Componentes e referências

| Repositório | Branch de deploy | Commit de referência | Escopo |
| --- | --- | --- | --- |
| `services-checkout-transparent-billing` | `feat/checkout-transparent-billing-whatsapp-audit` | `f0599ae` | Consulta interna de pagamentos quitados por período e índice de banco. |
| `services-checkout-transparent-api` | `feat/checkout-transparent-billing-whatsapp-audit` | `f4976c8` | Proxy administrativo para o Billing. |
| `edge-public-api` | `feat/checkout-transparent-billing-whatsapp-audit` | `8ade30d` | Autorização e proxy do relatório CT. |
| `edge-gateway` | `feat/checkout-transparent-billing-whatsapp-audit` | `07d624f` | Roteamento administrativo ao Public API. |
| `services-notification` | `feat/checkout-transparent-billing-whatsapp-audit` | `3c74278` | Configuração de providers, relatório de volumes e agregação por envio. |
| `services-account` | `feat/checkout-transparent-billing-whatsapp-audit` | `93d26fc` | Configurações de fluxo WhatsApp Meta ativas por padrão. |
| `dashboard-seller` | `feat/checkout-transparent-billing-whatsapp-audit` | `ef00e32` | Telas administrativas, relatório de comunicações e Cash In CT. |

## Alterações incluídas

- A aba administrativa de e-mail permite escolher provider por correlação ou manter `null`, que usa o provider padrão configurado.
- O relatório de comunicações exibe volumes diários de e-mail e WhatsApp, providers, templates e falhas; dias encerrados usam cache temporário.
- O Cashflow busca pagamentos quitados do Billing CT por `paid_at`, separa-os em **Cash In CT** e incorpora seu lucro líquido aos cards consolidados.
- O fluxo administrativo é: Dashboard Seller → Gateway → Public API → CT API → CT Billing. O JWT é validado no Public API, que limita o relatório a permissões administrativas 1 e 2.

## Pré-requisitos

- As sete branches e commits da tabela devem existir no remoto e estar aprovados para produção.
- No `edge-public-api`, declarar `CHECKOUT_TRANSPARENT_API_URL` com o host alcançável da API CT. Em ambientes sem rede Docker compartilhada, usar o hostname público aprovado; não usar `checkout-transparent-api` sem que o edge participe da rede privada.
- Manter configurados os nomes e valores já existentes de `CHECKOUT_TRANSPARENT_API_SERVICE_TOKEN`, HMAC e credenciais Cloudflare Access, quando usados pelo ambiente.
- Providers de e-mail já configurados no serviço de notificações; provider vazio em template significa provider padrão.

## Banco de dados

1. Em `services-checkout-transparent-billing`, executar migrations pendentes antes de expor a rota. A migration `20260925000000_add_paid_period_index_to_billing_payments` cria o índice `idx_billing_payments_status_paid_at`.
2. Em `services-notification`, executar migrations pendentes antes de habilitar a tela. Elas criam/atualizam tabelas e seeds de e-mail, WhatsApp Meta, tracking de entrega e providers por template quando ainda não existirem.
3. Não executar rollback automático. O índice do Billing pode permanecer caso seja necessário reverter apenas a aplicação.

## Sequência de deploy

Use os diretórios oficiais do ambiente de produção. Para cada componente, executar `git status --porcelain=v1` antes de alterar a branch; se houver mudanças locais, interromper e preservar o estado.

1. No Billing CT, atualizar a branch e executar migrations:

   ```bash
   git fetch origin --prune
   git switch feat/checkout-transparent-billing-whatsapp-audit
   git pull --ff-only origin feat/checkout-transparent-billing-whatsapp-audit
   docker compose up -d --build
   docker compose exec -T app php bin/hyperf.php migrate --force
   ```

2. Na API CT, atualizar e reconstruir:

   ```bash
   git fetch origin --prune
   git switch feat/checkout-transparent-billing-whatsapp-audit
   git pull --ff-only origin feat/checkout-transparent-billing-whatsapp-audit
   docker compose up -d --build
   ```

3. No Public API, confirmar a URL CT, atualizar e reconstruir para carregar a configuração incorporada à imagem:

   ```bash
   git fetch origin --prune
   git switch feat/checkout-transparent-billing-whatsapp-audit
   git pull --ff-only origin feat/checkout-transparent-billing-whatsapp-audit
   docker compose up -d --build
   ```

4. No Gateway, atualizar e reconstruir:

   ```bash
   git fetch origin --prune
   git switch feat/checkout-transparent-billing-whatsapp-audit
   git pull --ff-only origin feat/checkout-transparent-billing-whatsapp-audit
   docker compose up -d --build
   ```

5. No serviço de notificações, atualizar, executar migrations pendentes e reconstruir:

   ```bash
   git fetch origin --prune
   git switch feat/checkout-transparent-billing-whatsapp-audit
   git pull --ff-only origin feat/checkout-transparent-billing-whatsapp-audit
   docker compose up -d --build
   docker compose exec -T services-notifications php bin/hyperf.php migrate --force
   ```

6. No serviço de contas, atualizar e reconstruir:

   ```bash
   git fetch origin --prune
   git switch feat/checkout-transparent-billing-whatsapp-audit
   git pull --ff-only origin feat/checkout-transparent-billing-whatsapp-audit
   docker compose up -d --build
   ```

7. No Dashboard Seller, atualizar e reconstruir conforme a política do ambiente:

   ```bash
   git fetch origin --prune
   git switch feat/checkout-transparent-billing-whatsapp-audit
   git pull --ff-only origin feat/checkout-transparent-billing-whatsapp-audit
   docker compose up -d --build
   ```

## Validação pós-deploy

1. Faça login com um administrador e abra **Configurações → E-mail**. Confirme que a lista mostra apenas Correlação, provider e ação de salvar; selecione “Padrão configurado”, salve e recarregue a página.
2. Abra **Relatório de comunicações**, selecione um período já encerrado e confirme cards, gráfico diário, provider padrão, templates e falhas sem erro de período.
3. Abra **Relatório Cashflow**, pesquise um mês que tenha faturas CT quitadas e confirme a aba **Cash In CT**, com provider, método, quantidade, valor, taxas e lucro líquido.
4. Confirme que o card **Lucro líquido** inclui Cash In, Cash In CT e Cash Out; o Cash In legado não deve duplicar entradas CT.
5. Caso a tela mostre erro, interrompa a validação e registre horário, URL e resposta apresentada; não limpe filas, cache ou dados para forçar o resultado.

## Rollback

1. Reverter em ordem de borda para origem: Dashboard, Gateway, Public API, CT API, Billing, Notifications e Account.
2. Em cada repositório, selecionar o commit/branch de produção anterior aprovado e reconstruir o respectivo container.
3. Não fazer rollback das migrations de Notifications nem remover o índice do Billing durante uma reversão de aplicação. Dados de envio, cache e filas devem ser preservados.

## Pendências e riscos

- Validar em produção o hostname de `CHECKOUT_TRANSPARENT_API_URL` antes do deploy; o edge precisa alcançá-lo com as credenciais Cloudflare existentes.
- A primeira consulta de um intervalo histórico grande no relatório de comunicações pode demandar mais tempo até preencher o cache; otimização adicional está fora deste deploy.
