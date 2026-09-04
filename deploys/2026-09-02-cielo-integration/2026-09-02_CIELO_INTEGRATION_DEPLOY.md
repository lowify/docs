# Deploy — integração Cielo

## Objetivo

Preparar e disponibilizar a integração Cielo/Pagar.me para onboarding, cartão, liquidação, disputas e webhooks. A entrega é dividida em duas fases: preparação de configuração e banco de dados, seguida da publicação controlada dos containers.

Esta documentação não libera tráfego automaticamente. A ativação de Cielo, Pagar.me e 3DS depende das credenciais, flags e decisões operacionais descritas abaixo.

## Componentes e referências

| Componente | Branch de deploy | Situação em 02/09/2026 |
| --- | --- | --- |
| `front-checkout` | `feat-cielo-integration` | Atualizado com a `main`. |
| `front-idv` | `main` | Excluído da publicação desta entrega. |
| `dashboard-seller` | `feat-cielo-integration` | Atualizado com a `main`. |
| `edge-gateway` | `feat-cielo-integration` | Atualizado com a `main`. |
| `edge-public-api` | `feat-cielo-integration` | Atualizado com a `main`. |
| `services-account` | `feat-cielo-integration` | Atualizado com a `main`. |
| `services-banking-v2` | `feat-cielo-integration` | Atualizado com a `main`. |
| `services-wallet` | `feat-cielo-integration` | Atualizado com a `main` e incluído nesta entrega. |
| `services-commerce-v2` | `feat-cielo-integration` | Atualizado com a `main`. |
| `edge-webhook` | `feat-cielo-integration` | Atualizado com a `main`. |
| `services-notification` | `main` | A `main` já inclui as migrations e templates Cielo. |

## Alterações incluídas

- `services-account`: suporte ao onboarding e à comprovação bancária, incluindo contas bancárias, casos de revisão e novos tipos de documento.
- `services-banking-v2`: providers Cielo/Pagar.me, contas BaaS, cobranças de cartão, parcelas, alocações, estornos, evidências de disputa e sincronização de recebíveis.
- `services-wallet`: atualização do componente de carteira vinculada ao fluxo da integração, sem migration adicional nesta entrega.
- `services-commerce-v2`: gateways, regras de liquidação, configuração de cartão por produto e gateway prioritário de checkout.
- `edge-webhook`: persistência e deduplicação de webhooks Cielo; o webhook Pagar.me usa HTTP Basic Auth, não o antigo header customizado.
- `edge-public-api` e `edge-gateway`: publicação do fluxo entre os serviços atualizados.
- `dashboard-seller` e `front-checkout`: interfaces de operação e checkout da integração.
- `services-notification`: migrations de correlação e templates de e-mail Cielo já presentes na `main`.

## Pré-requisitos

1. Executar e registrar a validação dos dois bancos antes da publicação dos containers.
2. Aplicar os seeds `cielo_ecommerce` e `pagarme_psp` como ativos. A disponibilidade para uso permanece condicionada à conta aprovada, portanto os gateways não ficam disponíveis para usuários sem aprovação.
3. Configurar os nomes de segredo aplicáveis, sem registrar valores:
   - `CIELO_ECOMMERCE_MERCHANT_ID` e `CIELO_ECOMMERCE_MERCHANT_KEY` para autenticar chamadas da API E-commerce; usar as credenciais de produção do estabelecimento;
   - `CIELO_ECOMMERCE_SPLIT_MERCHANT_ID` e `CIELO_ECOMMERCE_SPLIT_CLIENT_SECRET` para OAuth/onboarding Split;
   - `CIELO_3DS_ENABLED=false` inicialmente; se habilitado, também `CIELO_3DS_CLIENT_ID`, `CIELO_3DS_CLIENT_SECRET`, `CIELO_3DS_ESTABLISHMENT_CODE`, `CIELO_3DS_MERCHANT_NAME` e `CIELO_3DS_MCC` (preservar zeros à esquerda);
   - `PAGARME_PSP_SECRET_KEY` e, quando houver tokenização, `PAGARME_PSP_PUBLIC_KEY`;
   - `CIELO_SPLIT_WEBHOOK_SECRET`, `CIELO_ECOMMERCE_WEBHOOK_SECRET`, `PAGARME_PSP_WEBHOOK_BASIC_USER` e `PAGARME_PSP_WEBHOOK_BASIC_PASSWORD` no `edge-webhook`.
4. Manter `APP_ENV` do `services-banking-v2` como `prod` ou `production`, sem override de endpoint.
5. Usar a `main` nos componentes declarados com essa branch e `feat-cielo-integration` nos componentes da integração. As referências já estão alinhadas para produção.
6. Confirmar que o Nginx do `edge-webhook` inclui `fastcgi_param HTTP_AUTHORIZATION $http_authorization;`, para o PHP receber as credenciais Basic Auth.

## Banco de dados

Executar primeiro os prechecks no schema real do ambiente, aplicar o script e executar sua validação imediatamente após cada banco. Os scripts estão anexos a este deploy:

| Banco | Aplicação | Validação |
| --- | --- | --- |
| `lowify` | [DEPLOY.sql](sql/lowify/DEPLOY.sql) | [VALIDATE.sql](sql/lowify/VALIDATE.sql) |
| `services-banking` | [DEPLOY.sql](sql/services-banking/DEPLOY.sql) | [VALIDATE.sql](sql/services-banking/VALIDATE.sql) |

As alterações são predominantemente aditivas e preservam o comportamento anterior pelos defaults `card_integration_enabled=0`, `settlement_method=wallet` e `should_block_balance=1`. DDL pode bloquear tabelas temporariamente. Não apagar dados, tabelas, registros de provider nem mensagens de fila durante esta etapa.

## Sequência de deploy

Após os bancos estarem validados e aprovados, executar os itens na ordem abaixo. Os caminhos são os registrados no plano de origem e devem ser confirmados pelo operador antes da execução.

1. Em cada repositório, confirmar ausência de alterações locais, atualizar a branch indicada e registrar o commit final:

   ```bash
   git status --porcelain=v1
   git fetch origin --prune
   ```

   Em seguida, usar os comandos específicos do componente nos passos abaixo e registrar o `git rev-parse --short HEAD` resultante.

2. Publicar `services-account`, reconstruir a imagem e confirmar saúde:

   ```bash
   cd /opt/lowify/services/services-account
   git switch feat-cielo-integration
   git pull --ff-only origin feat-cielo-integration
   docker compose up -d --build
   docker compose ps
   ```

3. Publicar `services-banking-v2`:

   ```bash
   cd /opt/lowify/services/services-banking-v2
   git switch feat-cielo-integration
   git pull --ff-only origin feat-cielo-integration
   docker compose up -d --build
   docker compose ps
   ```

4. Publicar `services-commerce-v2`:

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git switch feat-cielo-integration
   git pull --ff-only origin feat-cielo-integration
   docker compose up -d --build
   docker compose ps
   ```

5. Publicar `services-wallet` após Account, Banking e Commerce saudáveis:

   ```bash
   cd /opt/lowify/services/services-wallet
   git switch feat-cielo-integration
   git pull --ff-only origin feat-cielo-integration
   docker compose up -d --build
   docker compose ps
   ```

6. Publicar `edge-public-api` após Account, Banking, Wallet e Commerce saudáveis:

   ```bash
   cd /opt/lowify/edge/edge-public-api
   git switch feat-cielo-integration
   git pull --ff-only origin feat-cielo-integration
   docker compose up -d --build
   docker compose ps
   ```

7. Publicar `edge-gateway` e o worker associado; confirmar também o consumidor Redis:

   ```bash
   cd /opt/lowify/edge/edge-gateway
   git switch feat-cielo-integration
   git pull --ff-only origin feat-cielo-integration
   docker compose up -d --build
   docker compose ps
   ```

8. Publicar `edge-webhook`, aplicar a migration somente depois de o container estar saudável e confirmar as credenciais no Dashboard Pagar.me:

   ```bash
   cd /opt/lowify/edge/edge-webhook
   git switch feat-cielo-integration
   git pull --ff-only origin feat-cielo-integration
   docker compose up -d --build
   docker compose ps
   docker compose exec -T edge-webhook php artisan migrate --force
   ```

9. Publicar `services-notification` a partir da `main` e executar as migrations:

   ```bash
   cd /opt/lowify/services/services-notifications
   git switch main
   git pull --ff-only origin main
   docker compose up -d --build
   docker compose exec -T services-notification php bin/hyperf.php migrate
   ```

10. Atualizar `dashboard-seller`; este componente não requer build nem Docker neste procedimento:

   ```bash
   cd /opt/lowify/front/dashboard-seller
   git switch feat-cielo-integration
   git pull --ff-only origin feat-cielo-integration
   ```

11. Publicar `front-checkout` após Gateway e APIs saudáveis:

   ```bash
   cd /opt/lowify/front/front-checkout
   git switch feat-cielo-integration
   git pull --ff-only origin feat-cielo-integration
   docker compose up -d --build
   docker compose ps
   ```

`front-idv` permanece em `main` e não deve receber troca de branch ou publicação nesta entrega.

## Validação pós-deploy

1. Abra o dashboard com uma conta de teste e inicie o onboarding de seller. Confirme que a conta bancária e os documentos podem ser informados e que o cartão não é habilitado antes da aprovação.
2. No checkout de teste, confirme que os meios de pagamento exibidos respeitam as configurações do produto. Só teste cartão/3DS se as credenciais e a flag tiverem sido explicitamente ativadas.
3. Faça uma venda de teste autorizada e confirme que seu status aparece no dashboard sem erro visível. Em caso de falha, interrompa a liberação de tráfego e registre o ponto do fluxo que falhou.
4. Envie um evento de teste de onboarding e, quando aplicável, um evento transacional Cielo. Confirme que o status é atualizado apenas uma vez; repetir o mesmo evento não deve gerar duplicação.
5. Se o webhook Pagar.me estiver ativado, confirme no Dashboard Pagar.me que o usuário e a senha Basic Auth são exatamente os mesmos configurados no ambiente. Um retorno `401` indica credenciais ausentes/divergentes ou que o header Authorization não chegou ao PHP.
6. Como conferência técnica complementar, verificar health checks, logs dos serviços/consumidores e processamento Redis. Não consumir, limpar ou reprocessar mensagens durante a validação.

## Rollback

Se houver instabilidade confirmada, interromper a ativação de novos fluxos e retornar os componentes publicados à revisão anterior conhecida e aprovada, na ordem inversa: `front-checkout`, `dashboard-seller`, `edge-webhook`, `edge-gateway`, `edge-public-api`, `services-wallet`, `services-commerce-v2`, `services-banking-v2` e `services-account`.

Não reverter ou apagar o DDL/DML aplicado, contas BaaS, cobranças, eventos, evidências de disputa, registros de webhook, seeds de provider/gateway ou mensagens de fila. Esses dados são persistentes e podem ser necessários para auditoria e consistência; qualquer rollback de banco requer plano específico, revisado e aprovado.

Depois da reversão de código, manter Cielo, Pagar.me e 3DS desativados até haver uma correção publicada e a causa estar registrada.
