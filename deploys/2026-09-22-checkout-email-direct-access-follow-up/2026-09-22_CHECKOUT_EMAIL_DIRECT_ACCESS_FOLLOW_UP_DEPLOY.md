# Deploy — Acesso web e e-mail de entrega v3

## Objetivo

Preparar a publicação em produção da continuação da feature `feat/checkout-email-direct-access`:

- registrar acessos ao conteúdo feitos pelo link tokenizado e pela Área de Membros;
- apresentar esses acessos como **Acesso web** no detalhe da venda;
- permitir que apenas administradores de nível 1 e 2 ocultem registros;
- enviar a nova versão do e-mail de entrega, com acesso tokenizado para conteúdo e orientação adequada para a Área de Membros.

Ficam fora deste update alterações no checkout, no provedor de e-mail e em infraestrutura. O e-mail não é enviado durante o deploy; ele será validado com uma venda de teste após a publicação.

## Componentes e referências

| Componente | Repositório | Branch | Papel |
| --- | --- | --- | --- |
| services-commerce-v2 | `services-commerce-v2` | `feat/checkout-email-direct-access` | Dados de acesso, API de registro, URL tokenizada no e-mail e seleção da v3. |
| edge-gateway | `edge-gateway` | `feat/checkout-email-direct-access` | Roteamento assinado da Área de Membros e encaminhamento das rotas de acesso. |
| edge-public-api | `edge-public-api` | `feat/checkout-email-direct-access` | Encaminhamento ao Commerce e autorização JWT para gestão do histórico. |
| front-member-area | `front-member-area` | `feat/checkout-email-direct-access` | Emite o evento de acesso após validar o acesso ao produto. |
| dashboard-seller | `dashboard-seller` | `feat/checkout-email-direct-access` | Exibe a etapa Acesso web e seus detalhes. |
| services-notification | `services-notification` | `feat/checkout-email-direct-access` | Template e cadastro da correlação `sale_delivery_email_v3`. |
| front-checkout | `front-checkout` | `feat/checkout-email-direct-access` | Redireciona o comprador pago do PIX/upsell para o acesso direto. |

Os componentes listados são os únicos participantes deste deploy. Infraestrutura, banco, Redis e demais repositórios não recebem comandos por este documento.

## Alterações incluídas

### Acesso web

1. O link tokenizado e a Área de Membros registram acesso na tabela `sales_delivery` com tipo `content_access`.
2. A origem é `link_access` ou `members_area`; a sessão é armazenada apenas como hash.
3. A chave única evita múltiplos registros para a mesma venda, produto, origem e sessão.
4. A Área de Membros chama a rota assinada do Gateway; o Gateway encaminha ao Public API e o Commerce valida venda paga, acesso não revogado e produto da venda antes de persistir.
5. A tela de detalhes agrupa os registros em **Acesso web**, com data e origem. Admin 1 e 2 podem ocultar/restaurar; vendedores não veem registros ocultos.

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

Modo de rebuild: construir Commerce, Notification, Public API e Gateway; somente depois iniciar esses serviços. Área de Membros, Checkout e Dashboard usam bind mount de código e recebem apenas o `git pull`.

1. Antes de qualquer alteração, fazer a pré-checagem em cada target operável: `git status --porcelain=v1`, `git branch --show-current` e `git remote get-url origin`. Se qualquer target que será alterado tiver mudança local, parar toda a operação. Targets não participantes usam `main`; targets `hold` não recebem comando.

2. Atualizar e construir o Commerce:

```bash
git -C /opt/lowify/services/service-commerce-v2 fetch origin --prune
git -C /opt/lowify/services/service-commerce-v2 switch feat/checkout-email-direct-access
git -C /opt/lowify/services/service-commerce-v2 pull --ff-only origin feat/checkout-email-direct-access
(cd /opt/lowify/services/service-commerce-v2 && docker compose build)
```

3. Atualizar e construir o Notification:

```bash
git -C /opt/lowify/services/services-notifications fetch origin --prune
git -C /opt/lowify/services/services-notifications switch feat/checkout-email-direct-access
git -C /opt/lowify/services/services-notifications pull --ff-only origin feat/checkout-email-direct-access
(cd /opt/lowify/services/services-notifications && docker compose build)
```

4. Atualizar e construir o Public API:

```bash
git -C /opt/lowify/edge/edge-public-api fetch origin --prune
git -C /opt/lowify/edge/edge-public-api switch feat/checkout-email-direct-access
git -C /opt/lowify/edge/edge-public-api pull --ff-only origin feat/checkout-email-direct-access
(cd /opt/lowify/edge/edge-public-api && docker compose build)
```

5. Atualizar e construir o Gateway:

```bash
git -C /opt/lowify/edge/edge-gateway fetch origin --prune
git -C /opt/lowify/edge/edge-gateway switch feat/checkout-email-direct-access
git -C /opt/lowify/edge/edge-gateway pull --ff-only origin feat/checkout-email-direct-access
(cd /opt/lowify/edge/edge-gateway && docker compose build)
```

6. Só depois que todos os builds terminarem, executar manualmente [DEPLOY.sql](sql/lowify/DEPLOY.sql) e [VALIDATE.sql](sql/lowify/VALIDATE.sql) no banco Commerce. Em seguida rodar a migration do Notification com sua imagem já construída:

```bash
(cd /opt/lowify/services/services-notifications && docker compose run --rm services-notifications php bin/hyperf.php migrate --force)
```

7. Depois dos ajustes de banco concluírem sem erro, iniciar o Commerce:

```bash
(cd /opt/lowify/services/service-commerce-v2 && docker compose up -d)
```

8. Iniciar o Public API:

```bash
(cd /opt/lowify/edge/edge-public-api && docker compose up -d)
```

9. Iniciar o Gateway:

```bash
(cd /opt/lowify/edge/edge-gateway && docker compose up -d)
```

10. Iniciar o Notification:

```bash
(cd /opt/lowify/services/services-notifications && docker compose up -d)
```

11. Atualizar a Área de Membros. O `git pull` coloca o código em produção; não executar build ou up:

```bash
git -C /opt/lowify/front/front-member-area fetch origin --prune
git -C /opt/lowify/front/front-member-area switch feat/checkout-email-direct-access
git -C /opt/lowify/front/front-member-area pull --ff-only origin feat/checkout-email-direct-access
```

12. Atualizar o Checkout. O `git pull` coloca o código em produção; não executar build ou up:

```bash
git -C /opt/lowify/front/front-checkout fetch origin --prune
git -C /opt/lowify/front/front-checkout switch feat/checkout-email-direct-access
git -C /opt/lowify/front/front-checkout pull --ff-only origin feat/checkout-email-direct-access
```

13. Atualizar o Dashboard. O `git pull` coloca o código em produção; não executar build ou up:

```bash
git -C /opt/lowify/front/dashboard-seller fetch origin --prune
git -C /opt/lowify/front/dashboard-seller switch feat/checkout-email-direct-access
git -C /opt/lowify/front/dashboard-seller pull --ff-only origin feat/checkout-email-direct-access
```

14. Não executar `up` para Área de Membros, Checkout ou Dashboard. Produção espelha a composição confirmada em homologação: os três containers montam o repositório em `/var/www/html` e validam timestamps do OPcache. Depois do `git pull`, o código PHP/JS atualizado passa a ser servido sem reinício.

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
7. Se algum resultado não ocorrer, parar a aprovação e registrar venda de teste, horário e tela observada. Não apagar registros, sessões, filas ou dados para forçar o resultado.

## Testes de compatibilidade antes da produção

Ainda não há uma suíte automatizada para esse fluxo entre Área de Membros, Gateway, Public API, Commerce e Notification.

O roteiro de validação acima deve ser executado em homologação antes da publicação em produção. Uma suíte focada deve ser criada posteriormente com dados de teste reversíveis, cobrindo a rota assinada, autorização de ocultação e a deduplicação de sessão.

## Rollback

1. Reverter os sete componentes para o commit/branch anterior, em ordem inversa: Dashboard, Checkout, Área de Membros, Gateway, Public API, Notification e Commerce.
2. A migration do Commerce adiciona colunas e índices; não removê-los durante um rollback operacional. O código anterior ignora os campos novos.
3. A migration do Notification adiciona uma nova correlação/template; mantê-la, pois e-mails já criados podem referenciá-la.
4. Não apagar registros `content_access`, links tokenizados, sessões ou e-mails já gerados.
