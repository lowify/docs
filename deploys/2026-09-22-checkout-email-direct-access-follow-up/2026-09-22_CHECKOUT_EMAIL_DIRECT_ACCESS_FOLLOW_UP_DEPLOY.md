# Deploy — Acesso web e e-mail de entrega v3

## Objetivo

Preparar a publicação em produção da continuação da feature `feat/checkout-email-direct-access`:

- registrar acessos ao conteúdo feitos pelo link tokenizado e pela Área de Membros;
- apresentar esses acessos como **Acesso web** no detalhe da venda;
- permitir que apenas administradores de nível 1 e 2 ocultem registros;
- enviar a nova versão do e-mail de entrega, com acesso tokenizado para conteúdo e orientação adequada para a Área de Membros;
- proteger a reutilização de sessão por IP, limitar tentativas de login e migrar senhas legadas após login válido;
- publicar páginas 404/500 claras e o hardening Apache nos três fronts.

Ficam fora deste update alterações no provedor de e-mail e em infraestrutura. O Checkout também recebe as páginas 404/500 e o hardening Apache. O e-mail não é enviado durante o deploy; ele será validado com uma venda de teste após a publicação.

## Componentes e referências

| Componente | Repositório | Branch | Papel |
| --- | --- | --- | --- |
| services-commerce-v2 | `services-commerce-v2` | `feat/checkout-email-direct-access` | Dados de acesso, API de registro, URL tokenizada no e-mail e seleção da v3. |
| edge-gateway | `edge-gateway` | `feat/checkout-email-direct-access` | Roteamento assinado da Área de Membros, encaminhamento das rotas de acesso e resolução segura do IP de origem. |
| edge-public-api | `edge-public-api` | `feat/checkout-email-direct-access` | Encaminhamento ao Commerce e autorização JWT para gestão do histórico. |
| front-member-area | `front-member-area` | `feat/checkout-email-direct-access` | Emite o evento de acesso, mantém a sessão de acesso em cookie seguro, limita login, migra senhas legadas e entrega páginas de erro. |
| dashboard-seller | `dashboard-seller` | `feat/checkout-email-direct-access` | Exibe a etapa Acesso web, seus detalhes e páginas de erro Apache. |
| services-notification | `services-notification` | `feat/checkout-email-direct-access` | Template e cadastro da correlação `sale_delivery_email_v3`. |
| front-checkout | `front-checkout` | `feat/checkout-email-direct-access` | Redireciona o comprador pago do PIX/upsell para o acesso direto e entrega páginas de erro Apache. |

Os componentes listados são os únicos participantes deste deploy. Infraestrutura, banco, Redis e demais repositórios não recebem comandos por este documento.

## Alterações incluídas

### Acesso web

1. O link tokenizado e a Área de Membros registram acesso na tabela `sales_delivery` com tipo `content_access`.
2. A origem é `link_access` ou `members_area`; a sessão é armazenada apenas como hash.
3. A chave única evita múltiplos registros para a mesma venda, produto, origem e sessão.
4. A Área de Membros chama a rota assinada do Gateway; o Gateway encaminha ao Public API e o Commerce valida venda paga, acesso não revogado e produto da venda antes de persistir.
5. A tela de detalhes agrupa os registros em **Acesso web**, com data e origem. Admin 1 e 2 podem ocultar/restaurar; vendedores não veem registros ocultos.

### Segurança de acesso e páginas de erro

1. O Gateway determina o IP de origem na borda; a Área de Membros não aceita IP informado pelo navegador.
2. A sessão de acesso direto é mantida em cookie `Secure`, `HttpOnly` e `SameSite=Lax`; o token nunca fica disponível ao JavaScript.
3. O login limita tentativas por e-mail e IP; ao autenticar uma senha legada em texto de `tbl_clientes`, ela é substituída por hash seguro.
4. Área de Membros, Checkout e Dashboard publicam páginas 404 e 500 claras com acesso ao suporte. As imagens Apache dos três fronts aplicam `ServerTokens Prod` e `ServerSignature Off`.

### E-mail de entrega v3

1. A nova correlação é `sale_delivery_email_v3`; a v2 continua preservada no banco e nos arquivos.
2. Para entrega de conteúdo, o e-mail mostra somente o nome do produto e o acesso tokenizado.
3. Para Área de Membros, o e-mail mostra o botão de acesso com token.
4. Para novo acesso, informa a senha temporária; para conta existente, orienta a usar o e-mail que recebeu a mensagem e a senha já cadastrada.
5. A senha temporária é persistida com hash antes de ser enviada ao comprador.

## Banco de dados

### Commerce V2

O operador executa manualmente o SQL do Commerce; não executar migrations automáticas nesse serviço.

1. Rodar [DEPLOY.sql](sql/lowify/DEPLOY.sql) uma única vez, integralmente e em janela controlada.
2. Rodar [VALIDATE.sql](sql/lowify/VALIDATE.sql) e confirmar colunas e índices antes de subir os containers.

### Notification

Executar as migrations normalmente, usando a imagem já construída do serviço Notification, antes do `up` coletivo. A migration da v3 cria/atualiza a correlação `sale_delivery_email_v3` e seu template ativo, sem desativar a v2.

## Sequência de deploy

Modo de rebuild: construir Commerce, Notification, Public API, Gateway, Área de Membros, Checkout e Dashboard. Os fronts usam bind mount de código, mas suas imagens agora incluem configurações Apache; portanto, após o `git pull`, é obrigatório executar `docker compose up --build -d` em cada front alterado.

1. Antes de qualquer alteração, fazer a pré-checagem em cada target operável: `git status --porcelain=v1`, `git branch --show-current` e `git remote get-url origin`. Se qualquer target que será alterado tiver mudança local, parar toda a operação. Targets não participantes usam `main`; targets `hold` não recebem comando.

2. Atualizar e construir o Commerce:

```bash
cd /opt/lowify/services/service-commerce-v2
git fetch origin --prune
git switch feat/checkout-email-direct-access
git pull --ff-only origin feat/checkout-email-direct-access
docker compose build
```

3. Atualizar e construir o Notification:

```bash
cd /opt/lowify/services/services-notifications
git fetch origin --prune
git switch feat/checkout-email-direct-access
git pull --ff-only origin feat/checkout-email-direct-access
docker compose build
```

4. Atualizar e construir o Public API:

```bash
cd /opt/lowify/edge/edge-public-api
git fetch origin --prune
git switch feat/checkout-email-direct-access
git pull --ff-only origin feat/checkout-email-direct-access
docker compose build
```

5. Atualizar e construir o Gateway:

```bash
cd /opt/lowify/edge/edge-gateway
git fetch origin --prune
git switch feat/checkout-email-direct-access
git pull --ff-only origin feat/checkout-email-direct-access
docker compose build
```

6. Só depois que todos os builds terminarem, executar manualmente [DEPLOY.sql](sql/lowify/DEPLOY.sql) e [VALIDATE.sql](sql/lowify/VALIDATE.sql) no banco Commerce. Em seguida rodar a migration do Notification com sua imagem já construída:

```bash
cd /opt/lowify/services/services-notifications
docker compose run --rm services-notifications php bin/hyperf.php migrate --force
```

7. Depois dos ajustes de banco concluírem sem erro, iniciar o Commerce:

```bash
cd /opt/lowify/services/service-commerce-v2
docker compose up -d
```

8. Iniciar o Public API:

```bash
cd /opt/lowify/edge/edge-public-api
docker compose up -d
```

9. Iniciar o Gateway:

```bash
cd /opt/lowify/edge/edge-gateway
docker compose up -d
```

10. Iniciar o Notification:

```bash
cd /opt/lowify/services/services-notifications
docker compose up -d
```

11. Atualizar e reconstruir a Área de Membros. O `git pull` atualiza o código montado; o rebuild é obrigatório para carregar a configuração Apache da imagem:

```bash
cd /opt/lowify/front/front-member-area
git fetch origin --prune
git switch feat/checkout-email-direct-access
git pull --ff-only origin feat/checkout-email-direct-access
docker compose up --build -d
```

12. Atualizar e reconstruir o Checkout. O `git pull` atualiza o código montado; o rebuild é obrigatório para carregar a configuração Apache da imagem:

```bash
cd /opt/lowify/front/front-checkout
git fetch origin --prune
git switch feat/checkout-email-direct-access
git pull --ff-only origin feat/checkout-email-direct-access
docker compose up --build -d
```

13. Atualizar e reconstruir o Dashboard. O `git pull` atualiza o código montado; o rebuild é obrigatório para carregar a configuração Apache da imagem:

```bash
cd /opt/lowify/front/dashboard-seller
git fetch origin --prune
git switch feat/checkout-email-direct-access
git pull --ff-only origin feat/checkout-email-direct-access
docker compose up --build -d
```

14. Executar os rebuilds dos três fronts de forma sequencial, conforme os comandos acima. Eles continuam montando o repositório em `/var/www/html` e validando timestamps do OPcache, mas o `docker compose up --build -d` também é necessário para aplicar as configurações Apache incluídas na imagem.

## Validação pós-deploy

1. Faça uma compra de teste de produto com entrega por conteúdo e conclua o pagamento.
   - Resultado esperado: o e-mail chega com o nome do produto e o botão **Acessar conteúdo**.
2. Clique no botão do e-mail de conteúdo.
   - Resultado esperado: o conteúdo abre; ao atualizar a página na mesma sessão, não aparecem vários acessos iguais no detalhe da venda.
3. Faça uma compra de teste de produto da Área de Membros usando um e-mail sem conta anterior.
   - Resultado esperado: o e-mail mostra **Acessar área de membros** e a senha temporária; o botão abre o produto.
4. Repita para um e-mail que já possui conta.
   - Resultado esperado: o e-mail não mostra senha nem repete o endereço; orienta usar o e-mail que recebeu a mensagem e a senha já cadastrada.
5. No Dashboard, abra o detalhe das duas vendas e clique em **Acesso web**.
   - Resultado esperado: a lista mostra Data e Origem como **Link de acesso** ou **Área de membros**.
6. Com um administrador de nível 1 ou 2, oculte um registro e atualize a página.
   - Resultado esperado: o administrador ainda pode encontrá-lo/gerenciá-lo; o vendedor não o vê.
7. Abra uma URL inexistente em Área de Membros, Checkout e Dashboard.
   - Resultado esperado: a resposta 404 exibe a tela clara com lupa e o botão de suporte.
8. Em uma conta de teste que ainda use senha legada, faça login uma vez.
   - Resultado esperado: o acesso funciona e a senha passa a ser armazenada como hash; não testar nem registrar credenciais de clientes reais.
9. Se algum resultado não ocorrer, parar a aprovação e registrar venda de teste, horário e tela observada. Não apagar registros, sessões, filas ou dados para forçar o resultado.

## Rollback

1. Reverter os sete componentes para o commit/branch anterior, em ordem inversa: Dashboard, Checkout, Área de Membros, Gateway, Public API, Notification e Commerce.
2. A migration do Commerce adiciona colunas e índices; não removê-los durante um rollback operacional. O código anterior ignora os campos novos.
3. A migration do Notification adiciona uma nova correlação/template; mantê-la, pois e-mails já criados podem referenciá-la.
4. Não apagar registros `content_access`, links tokenizados, sessões ou e-mails já gerados.
