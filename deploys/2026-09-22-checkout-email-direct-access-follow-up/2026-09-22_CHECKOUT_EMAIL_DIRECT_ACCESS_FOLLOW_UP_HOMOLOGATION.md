# Homologação — Acesso web e e-mail de entrega v3

## Objetivo

Publicar em homologação a continuação da feature `feat/checkout-email-direct-access`:

- registrar acessos ao conteúdo feitos pelo link tokenizado e pela Área de Membros;
- apresentar esses acessos como **Acesso web** no detalhe da venda;
- permitir que apenas administradores de nível 1 e 2 ocultem registros;
- enviar a nova versão do e-mail de entrega, com acesso tokenizado para conteúdo e orientação adequada para a Área de Membros.

Ficam fora deste update alterações no checkout, no provedor de e-mail e em infraestrutura. O e-mail não é enviado durante o deploy; ele será validado com uma venda de teste após a publicação.

## Componentes e referências

| Chave no mapa de homologação | Repositório | Branch | Papel |
| --- | --- | --- | --- |
| services-commerce-v2 | `services-commerce-v2` | `feat/checkout-email-direct-access` | Dados de acesso, API de registro, URL tokenizada no e-mail e seleção da v3. |
| edge-gateway | `edge-gateway` | `feat/checkout-email-direct-access` | Roteamento assinado da Área de Membros e encaminhamento das rotas de acesso. |
| edge-public-api | `edge-public-api` | `feat/checkout-email-direct-access` | Encaminhamento ao Commerce e autorização JWT para gestão do histórico. |
| front-member-area | `front-member-area` | `feat/checkout-email-direct-access` | Emite o evento de acesso após validar o acesso ao produto. |
| dashboard-seller | `dashboard-seller` | `feat/checkout-email-direct-access` | Exibe a etapa Acesso web e seus detalhes. |
| services-notification | `services-notification` | `feat/checkout-email-direct-access` | Template e cadastro da correlação `sale_delivery_email_v3`. |
| front-checkout | `front-checkout` | `feat/checkout-email-direct-access` | Redireciona o comprador pago do PIX/upsell para o acesso direto. |

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

## Banco de dados

### Commerce V2

O operador executa manualmente o SQL do Commerce; não executar migrations automáticas nesse serviço.

1. Rodar [DEPLOY.sql](sql/lowify/DEPLOY.sql) uma única vez, integralmente e em janela controlada.
2. Rodar [VALIDATE.sql](sql/lowify/VALIDATE.sql) e confirmar colunas e índices antes de subir os containers.

### Notification

Executar as migrations normalmente, usando a imagem já construída do serviço Notification, antes do `up` coletivo. A migration da v3 cria/atualiza a correlação `sale_delivery_email_v3` e seu template ativo, sem desativar a v2.

## Sequência de deploy

Modo de rebuild: completo. Primeiro concluir o build de todos os containers; somente depois iniciar os containers em conjunto.

1. Na VPS `root@217.216.87.77`, executar a pré-checagem em todos os targets operáveis antes de qualquer atualização:

```bash
git -C <diretorio> status --porcelain=v1
git -C <diretorio> branch --show-current
git -C <diretorio> remote get-url origin
```

Se houver mudança local em qualquer target que será alterado, parar toda a operação e preservar o estado.

2. Atualizar os participantes, em ordem de dependência, com `git fetch origin --prune`, `git switch feat/checkout-email-direct-access` e `git pull --ff-only origin feat/checkout-email-direct-access`. Atualizar cada target não participante para `main` com os mesmos comandos, substituindo a branch. Não executar comandos nos targets mantidos como estão ou marcados como `hold`.

3. Com todos os repositórios já atualizados, executar primeiro o build de todos os participantes:

```bash
docker compose -C /root/opt/lowify/services/service-commerce-v2 build
docker compose -C /root/opt/lowify/services/services-notifications build
docker compose -C /root/opt/lowify/edge/edge-public-api build
docker compose -C /root/opt/lowify/edge/edge-gateway build
docker compose -C /root/opt/lowify/front/front-member-area build
docker compose -C /root/opt/lowify/front/front-checkout build
docker compose -C /root/opt/lowify/front/dashboard-seller build
```

Ordem: `services-commerce-v2`, `services-notification`, `edge-public-api`, `edge-gateway`, `front-member-area`, `front-checkout`, `dashboard-seller`.

Usar os diretórios do mapa oficial: `/root/opt/lowify/services/service-commerce-v2`, `/root/opt/lowify/services/services-notifications`, `/root/opt/lowify/edge/edge-public-api`, `/root/opt/lowify/edge/edge-gateway`, `/root/opt/lowify/front/front-member-area`, `/root/opt/lowify/front/front-checkout` e `/root/opt/lowify/front/dashboard-seller`.

Aplicar também o build aos targets não participantes que tiveram branch ou commit alterado para `main`.

4. Antes do `up`, executar o SQL manual do Commerce e rodar as migrations do Notification com a imagem já construída:

```bash
docker compose -C /root/opt/lowify/services/services-notifications run --rm services-notifications php bin/hyperf.php migrate
```

5. Somente após todos os builds e os ajustes de banco concluírem sem erro, iniciar os containers:

```bash
docker compose -C /root/opt/lowify/services/service-commerce-v2 up -d
docker compose -C /root/opt/lowify/services/services-notifications up -d
docker compose -C /root/opt/lowify/edge/edge-public-api up -d
docker compose -C /root/opt/lowify/edge/edge-gateway up -d
docker compose -C /root/opt/lowify/front/front-member-area up -d
docker compose -C /root/opt/lowify/front/front-checkout up -d
docker compose -C /root/opt/lowify/front/dashboard-seller up -d
```

Iniciar também os targets não participantes que foram construídos para voltar a `main`.

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
