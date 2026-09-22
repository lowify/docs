# Homologação — Acesso web e e-mail de entrega v3

## Objetivo

Publicar em homologação a continuação da feature `feat/checkout-email-direct-access`:

- registrar acessos ao conteúdo feitos pelo link tokenizado e pela Área de Membros;
- apresentar esses acessos como **Acesso web** no detalhe da venda;
- permitir que apenas administradores de nível 1 e 2 ocultem registros;
- enviar a nova versão do e-mail de entrega, com acesso tokenizado para conteúdo e orientação adequada para a Área de Membros.

Ficam fora deste update alterações no checkout, no provedor de e-mail e em infraestrutura. O e-mail não é enviado durante o deploy; ele será validado com uma venda de teste após a publicação.

## Componentes e referências

| Chave no mapa de homologação | Repositório | Branch | Commit local de referência | Papel |
| --- | --- | --- | --- | --- |
| services-commerce-v2 | `services-commerce-v2` | `feat/checkout-email-direct-access` | `eade67d` | Dados de acesso, API de registro, URL tokenizada no e-mail e seleção da v3. |
| edge-gateway | `edge-gateway` | `feat/checkout-email-direct-access` | `1681224` | Roteamento assinado da Área de Membros e encaminhamento das rotas de acesso. |
| edge-public-api | `edge-public-api` | `feat/checkout-email-direct-access` | `d7d01c0` | Encaminhamento ao Commerce e autorização JWT para gestão do histórico. |
| front-member-area | `front-member-area` | `feat/checkout-email-direct-access` | `d0d5411` | Emite o evento de acesso após validar o acesso ao produto. |
| dashboard-seller | `dashboard-seller` | `feat/checkout-email-direct-access` | `2d00b013` | Exibe a etapa Acesso web e seus detalhes. |
| services-notification | `services-notification` | `feat/checkout-email-direct-access` | `375ba1f` | Template e cadastro da correlação `sale_delivery_email_v3`. |
| front-checkout | `front-checkout` | `feat/checkout-email-direct-access` | branch já publicada | Redireciona o comprador pago do PIX/upsell para o acesso direto. |

Todos os demais targets operáveis de `homologation-map.yaml` devem ser sincronizados em `main`. `data_layer` e `checkout-transparent-infra` permanecem como estão, pois o mapa os protege como infraestrutura. Itens ausentes ou não mapeados no mapa não participam da operação.

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

## Pré-requisitos

1. Publicar as seis branches listadas na tabela para `origin` antes de operar a VPS. Esta documentação não autoriza push.
2. Confirmar que os commits de referência, ou commits descendentes deles, estão nas branches remotas.
3. Manter configurados os valores existentes de `APP_URL_MEMBERS`, `GATEWAY_SIGNATURE_SECRET` e as credenciais atuais de banco/Redis. Não registrar valores no documento nem alterá-los para este deploy.
4. Para ativar a v3, manter `SALE_DELIVERY_EMAIL_CORRELATION_TYPE` vazio ou configurá-lo como `sale_delivery_email_v3`. Para o assunto padrão, manter `SALE_DELIVERY_EMAIL_TITLE` vazio ou usar `Acesso ao seu conteúdo`.
5. Garantir uma venda de homologação paga, com e-mail controlado, para testar entrega por conteúdo e outra para Área de Membros. Não usar dados de compradores reais.

## Banco de dados

### Commerce V2

Aplicar, em ordem e somente as que ainda não constarem no controle de migrations:

```text
migrations/20260901100000_create_sale_notification_product_rules.sql
migrations/20260901150000_add_sale_notification_dispatch_schema.sql
migrations/20260902100000_add_callback_statuses_to_sales_delivery.sql
migrations/20260916120000_add_cookie_to_sales_access_sessions.sql
migrations/20260921120000_add_access_link_sales_delivery_statuses.sql
migrations/20260922120000_add_content_access_to_sales_delivery.sql
```

Precheck: confirmar que `sales_delivery` existe e que ainda não possui a coluna `access_session_hash`.

Validação: confirmar as colunas `product_id`, `access_source`, `access_session_hash`, `accessed_at`, o tipo `content_access` e a chave única `uk_sales_delivery_content_access_session`.

### Notification

Executar, em ordem e somente as que ainda não constarem no controle de migrations:

```text
migrations/2026_08_28_000056_seed_communication_credit_insufficient_email_template.php
migrations/2026_09_02_000057_seed_sale_recovery_dispatch_email_template.php
migrations/2026_09_02_000058_expand_whatsapp_meta_delivery_statuses.php
migrations/2026_09_22_000053_seed_sale_delivery_email_v3_template.php
```

Ela cria/atualiza a correlação `sale_delivery_email_v3` e seu template ativo, sem desativar a v2.

## Sequência de deploy

Modo de rebuild: incremental. Reconstruir apenas um target cujo branch ou commit tenha mudado. O Dashboard também deve ser reconstruído se tiver mudado.

1. Na VPS `root@217.216.87.77`, executar a pré-checagem em todos os targets operáveis antes de qualquer atualização:

```bash
git -C <diretorio> status --porcelain=v1
git -C <diretorio> branch --show-current
git -C <diretorio> remote get-url origin
```

Se houver mudança local em qualquer target que será alterado, parar toda a operação e preservar o estado.

2. Para cada participante da tabela, em ordem de dependência, executar:

```bash
git -C <diretorio> fetch origin --prune
git -C <diretorio> switch feat/checkout-email-direct-access
git -C <diretorio> pull --ff-only origin feat/checkout-email-direct-access
docker compose -C <diretorio> up -d --build
```

Ordem: `services-commerce-v2`, `services-notification`, `edge-public-api`, `edge-gateway`, `front-member-area`, `front-checkout`, `dashboard-seller`.

Usar os diretórios do mapa oficial: `/root/opt/lowify/services/service-commerce-v2`, `/root/opt/lowify/services/services-notifications`, `/root/opt/lowify/edge/edge-public-api`, `/root/opt/lowify/edge/edge-gateway`, `/root/opt/lowify/front/front-member-area`, `/root/opt/lowify/front/front-checkout` e `/root/opt/lowify/front/dashboard-seller`.

3. Em cada target operável não participante, executar os mesmos comandos com `main` no lugar da branch da feature. Não executar comandos nos targets mantidos como estão ou marcados como `hold`.

4. Após o Commerce e Notification estarem saudáveis, aplicar as migrations descritas na seção Banco de dados pelo procedimento já adotado no ambiente. Não executar DDL manual alternativo.

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

## Testes de compatibilidade em homologação

Ainda não há uma suíte automatizada para esse fluxo entre Área de Membros, Gateway, Public API, Commerce e Notification.

O roteiro de validação acima é obrigatório antes de alinhar a feature com `main`. Uma suíte focada deve ser criada posteriormente com dados de teste reversíveis, cobrindo a rota assinada, autorização de ocultação e a deduplicação de sessão.

## Rollback

1. Reverter os sete componentes para o commit/branch anterior, em ordem inversa: Dashboard, Checkout, Área de Membros, Gateway, Public API, Notification e Commerce.
2. A migration do Commerce adiciona colunas e índices; não removê-los durante um rollback operacional. O código anterior ignora os campos novos.
3. A migration do Notification adiciona uma nova correlação/template; mantê-la, pois e-mails já criados podem referenciá-la.
4. Não apagar registros `content_access`, links tokenizados, sessões ou e-mails já gerados.

## Pendências antes da aprovação

- Publicar as branches remotas e alinhar cada uma com a `main` atual conforme o fluxo de deploy.
- Executar a homologação e os cenários de validação descritos neste documento.
- Confirmar o endereço de suporte exibido no rodapé padrão, se aplicável ao provedor de e-mail; a v3 não inclui bloco de suporte genérico.
