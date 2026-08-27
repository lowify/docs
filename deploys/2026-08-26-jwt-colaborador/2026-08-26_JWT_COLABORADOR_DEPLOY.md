# Plano de deploy — JWT para colaborador

## Resumo final

O colaborador continua em tbl_colaboradores e o CRUD permanece no Dashboard Seller. O Auth emite JWT com actor_type, collaborator_id, seller_id e permissões normalizadas. Dashboard e Public API aplicam as permissões existentes e o Public API força o escopo do seller.

- Login de colaborador usa type collaborator; login e tokens legados de usuário continuam compatíveis.
- Navegação sem permissão recebe destino seguro.
- Chamada API sem permissão recebe HTTP 403 e feature_permission_denied.
- Não há novas permissões: dashboard, products, products_edit, sales, sale_detail, balance, membros, order_bumps, upsells, integracoes e disputes.
- O login de colaborador possui limite por IP e e-mail no Dashboard, além de limite por IP e identificador no Auth.

## Serviços

| Serviço | Branch de referência |
| --- | --- |
| services-account | feat/jwt-colaborador |
| services-auth | feat/jwt-colaborador |
| edge-public-api | feat/jwt-colaborador |
| dashboard-seller | feat/jwt-colaborador |

## Banco do Auth

O deploy adiciona as colunas actor_type e actor_id em services-auth.refresh_tokens. Elas registram se o refresh token pertence a um usuário ou a um colaborador e qual é o identificador desse ator.

## Procedimento de deploy

### 1. Pré-check

Confirmar espaço, containers em execução e branch atual dos serviços antes de alterar qualquer checkout:

    df -h
    df -ih
    docker ps
    git status --short --branch

### 2. Services Account

No diretório do services-account:

    git fetch origin feat/jwt-colaborador
    git switch feat/jwt-colaborador
    git pull --ff-only origin feat/jwt-colaborador
    docker compose up -d --build services-account
    docker compose ps
    docker compose logs --tail=200 services-account

### 3. Services Auth

No diretório do services-auth, conferir primeiro o banco conforme a seção Banco do Auth. Depois atualizar e recriar o serviço:

    git fetch origin feat/jwt-colaborador
    git switch feat/jwt-colaborador
    git pull --ff-only origin feat/jwt-colaborador
    docker compose up -d --build services-auth
    docker compose exec services-auth php bin/hyperf.php migrate
    docker compose ps
    docker compose logs --tail=200 services-auth

A migration deve ser executada somente depois de confirmar que o container está conectado ao banco services-auth.

### 4. Edge Public API

No diretório do edge-public-api:

    git fetch origin feat/jwt-colaborador
    git switch feat/jwt-colaborador
    git pull --ff-only origin feat/jwt-colaborador
    docker compose up -d --build edge-public-api
    docker compose ps
    docker compose logs --tail=200 edge-public-api

### 5. Dashboard Seller

No diretório do dashboard-seller:

    git fetch origin feat/jwt-colaborador
    git switch feat/jwt-colaborador
    git pull --ff-only origin feat/jwt-colaborador

O pull atualiza PHP, JS e CSS no container montado.

Não usar reset, force push ou alteração manual de banco como parte do deploy.

## Validação esperada

Usar dois colaboradores de teste: um com as permissões da funcionalidade e outro sem a permissão. A coluna técnica está entre aspas para a IA localizar a página ou rota relacionada.

| Ação para quem testa | Resultado visível esperado | Referência técnica |
| --- | --- | --- |
| Entrar pela tela de colaborador com e-mail e senha válidos. | O acesso é concluído e a pessoa é levada à primeira área que ela pode usar. | "login_colaborador.php e login_colaborador_process.php" |
| Entrar com dados inválidos ou fazer várias tentativas seguidas. | A tela não informa se o e-mail existe; após excesso de tentativas, o acesso continua recusado de forma genérica. | "rate limit por IP/e-mail no Dashboard e por IP/identificador no Auth" |
| Abrir a página inicial com um colaborador que tenha acesso ao Dashboard. | Os indicadores carregam apenas dados do vendedor vinculado ao colaborador. | "index.php e api/dashboard_overview.php" |
| Abrir Produtos com a permissão de produtos. | A lista mostra somente os produtos do vendedor vinculado. | "products.php e api/products_list.php" |
| Criar um produto, abrir um produto existente, editar e salvar. | As ações funcionam somente quando o colaborador possui permissão de edição; o produto fica no vendedor vinculado. | "product_add.php, product_edit.php, product_form.php, product_process.php, checkout_styler.php e APIs de produto" |
| Abrir Vendas, consultar uma venda e usar Reenviar acesso. | As vendas exibidas são apenas do vendedor vinculado e o reenvio funciona para uma venda permitida. | "sales.php, sales_beta.php, sale_detail.php, api/dashboard/sales/list.php e _resend_access_email.php" |
| Abrir Saldo/Recompensas como colaborador. | Não aparecem avisos de cadastro, fatura pendente ou o botão Solicitar Saque. | "balance.php, contas.php, recompensas.php, header.php e views/dashboard/balance/index.php" |
| Tentar abrir uma área sem a permissão correspondente. | A pessoa é direcionada para uma página que pode acessar, sem ver dados restritos. | "guardas em includes/init.php; order bumps, upsells, membros, integrações e disputes" |
| Tentar abrir Colaboradores, Assinaturas, Documentos, MEDS ou Recuperação de carrinho. | O colaborador não consegue acessar essas áreas. | "colaboradores.php, colaboradores_process.php, subscriptions.php, documents.php, reports_meds.php, meds-report.php e cart_recovery.php" |
| Repetir o login e as páginas principais com um owner. | O fluxo normal do vendedor continua funcionando como antes. | "fallback de actor_type user no Auth" |

Para APIs chamadas pelas telas, a IA deve confirmar nos logs ou na aba Network que uma permissão ausente retorna HTTP 403 com código feature_permission_denied e sem dados da funcionalidade.

## Rollback

1. Retornar Dashboard, Public API, Auth e Account para a última referência saudável e recriar somente os containers alterados.
2. Não executar migration rollback; as colunas adicionadas em refresh_tokens são compatíveis com a versão anterior.
3. Se o Public API também for revertido, revogar os refresh tokens de colaborador e aguardar até 15 minutos para os access tokens emitidos expirarem.
4. Validar login de owner, Dashboard, produtos e uma rota de vendas.
