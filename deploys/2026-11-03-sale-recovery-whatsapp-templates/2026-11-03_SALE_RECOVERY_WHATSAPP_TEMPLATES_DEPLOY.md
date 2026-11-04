# Deploy — Templates WhatsApp da recuperação de vendas

## Objetivo

Publicar o novo fluxo de WhatsApp Meta para recuperação de vendas com PIX. O Commerce V2 publica somente a ação e o contexto da recuperação; o Notifications escolhe o template internamente, conforme o estágio e o vínculo configurado.

O painel administrativo passa a configurar, para cada cenário Recuperação 1 — com PIX e Recuperação 2 — com PIX, um template principal e um reserva. Os oito templates elegíveis são sale_recovering_ct_pix e sale_recovering_ct_pix_2 até _8; todos podem ser usados nos dois estágios.

Fora do escopo desta entrega: entrega de vendas, recuperação por e-mail e templates WhatsApp que não pertencem à família PIX acima.

## Componentes e referências

| Repositório | Diretório em produção | Branch de deploy | Commit | Papel na entrega |
| --- | --- | --- | --- | --- |
| services-notification | /opt/lowify/services/services-notifications | feat/sale-recovery-whatsapp-templates | 8010a90 | Migration, resolução interna de template, CTA PIX, rotação e endpoints administrativos. |
| services-commerce-v2 | /opt/lowify/services/service-commerce-v2 | feat/sale-recovery-whatsapp-templates | 28ed8f7 | Publica o contrato v2 e libera a reserva financeira nos skips. |
| edge-public-api | /opt/lowify/edge/edge-public-api | feat/sale-recovery-whatsapp-templates | 8d77e29 | Autoriza e encaminha a administração dos vínculos. |
| edge-gateway | /opt/lowify/edge/edge-gateway | feat/sale-recovery-whatsapp-templates | bf341d9 | Encaminha as rotas administrativas para o Public API. |
| dashboard-seller | /opt/lowify/front/dashboard-seller | feat/sale-recovery-whatsapp-templates | c74c245a | Interface para configurar principal e reserva por estágio PIX. |

## Alterações incluídas

- A fila permanece stream:notifications:whatsapp_meta; o novo contrato usa version: 2 e action: sale_recovery, sem nome de template no payload.
- Para payment_method pix ou pix_automatic sem pix_code, o Commerce V2 não publica a recuperação e a marca como ignorada.
- Para outros meios sem pix_code, o Notifications não chama a Meta: publica skipped e o Commerce V2 libera a reserva financeira.
- O Notifications injeta internamente until como “e sua oferta pode expirar em breve.” e preenche o CTA de URL dinâmica no índice 0 e o botão de pagamento PIX no índice 1.
- A migration cria whatsapp_meta_template_bindings, semeia os oito templates elegíveis e cria os vínculos iniciais:
  - estágio 1: principal sale_recovering_ct_pix, reserva _2;
  - estágio 2: principal _3, reserva _4.
- Em falha qualificada do template principal, a reserva do mesmo vínculo passa a ser principal e a reserva fica vazia. Sem reserva, o principal não é alterado.
- Os novos endpoints administrativos exigem a autorização administrativa já aplicada pelo Public API; a identidade continua sendo extraída do JWT nessa camada.

## Pré-requisitos

1. Confirmar no Meta Business Manager que os oito templates elegíveis existem, estão aprovados e têm a mesma estrutura: parâmetros first_name, product_name e until; CTA de URL dinâmica; e CTA Solicitar pagamento com código PIX.
2. Confirmar que as credenciais já existentes do WhatsApp Meta no services-notification estão configuradas. Não registrar valores de segredos neste documento.
3. Confirmar que a funcionalidade de recuperação de vendas e a precificação/crédito de comunicação já estão configuradas para o seller de teste.
4. Antes de qualquer atualização, verificar que cada diretório de produção está limpo com git status --porcelain=v1. Se houver saída, interromper e preservar as alterações.
5. Confirmar que a migration histórica 2026_10_08_000061 já aparece como aplicada antes de executar a migration desta entrega.
6. Antes do deploy em produção, preparar as cinco branches de feature incorporando a main remota, pelo fluxo de preparação de deploy. Depois dessa preparação, atualizar nesta tabela os commits de referência para os novos HEADs publicados; não implantar uma branch local não publicada.

## Banco de dados

Há uma migration no banco do Notifications: migrations/2026_11_03_000062_create_sale_recovery_template_bindings.php.

Ela cria a tabela de vínculos e executa a seed inicial. Não editar manualmente os IDs nem apagar templates, vínculos, mensagens whatsapp_meta, dispatches, créditos ou mensagens de fila.

Precheck, antes da aplicação:

~~~bash
cd /opt/lowify/services/services-notifications
docker compose exec -T services-notifications php bin/hyperf.php migrate:status
~~~

Confirmar que a migration 2026_10_08_000061 está aplicada e que a 2026_11_03_000062 ainda está pendente. Se a nova já estiver aplicada, não a execute novamente; apenas valide os vínculos no painel após a publicação.

## Sequência de deploy

Modo de rebuild: completo para os quatro componentes Docker. Primeiro atualizar os cinco repositórios, depois construir todas as quatro imagens e somente então subir os containers na ordem segura. O Dashboard Seller recebe somente pull.

O Notifications deve subir e aplicar a migration antes do Commerce V2, pois o Commerce passará a produzir o contrato v2.

### Pré-checagem completa

Antes de trocar a branch de qualquer componente, execute em todos os cinco diretórios:

~~~bash
git status --porcelain=v1
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/main
git show-ref --verify --quiet refs/remotes/origin/feat/sale-recovery-whatsapp-templates
~~~

Se qualquer comando falhar ou o status tiver saída, interrompa toda a operação. Não faça stash, reset, limpeza ou troca de branch para contornar o estado encontrado.

### 1. Atualizar services-notification

~~~bash
cd /opt/lowify/services/services-notifications
git status --porcelain=v1
git fetch origin --prune
git switch feat/sale-recovery-whatsapp-templates
git pull --ff-only origin feat/sale-recovery-whatsapp-templates
git rev-parse --short HEAD
~~~

O commit deve ser 8010a90.

### 2. Atualizar services-commerce-v2

~~~bash
cd /opt/lowify/services/service-commerce-v2
git status --porcelain=v1
git fetch origin --prune
git switch feat/sale-recovery-whatsapp-templates
git pull --ff-only origin feat/sale-recovery-whatsapp-templates
git rev-parse --short HEAD
~~~

O commit deve ser 28ed8f7.

### 3. Atualizar edge-public-api

~~~bash
cd /opt/lowify/edge/edge-public-api
git status --porcelain=v1
git fetch origin --prune
git switch feat/sale-recovery-whatsapp-templates
git pull --ff-only origin feat/sale-recovery-whatsapp-templates
git rev-parse --short HEAD
~~~

O commit deve ser 8d77e29.

### 4. Atualizar edge-gateway

~~~bash
cd /opt/lowify/edge/edge-gateway
git status --porcelain=v1
git fetch origin --prune
git switch feat/sale-recovery-whatsapp-templates
git pull --ff-only origin feat/sale-recovery-whatsapp-templates
git rev-parse --short HEAD
~~~

O commit deve ser bf341d9.

### 5. Atualizar dashboard-seller

~~~bash
cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git fetch origin --prune
git switch feat/sale-recovery-whatsapp-templates
git pull --ff-only origin feat/sale-recovery-whatsapp-templates
git rev-parse --short HEAD
~~~

O commit deve ser c74c245a. Não há build de frontend novo nesta entrega; aplicar o procedimento usual de reload do PHP-FPM/opcache do ambiente, se ele existir.

### 6. Construir todas as imagens Docker

Execute todos os builds antes de subir qualquer container. Se qualquer build falhar, interrompa; nenhum dos quatro containers deve ser iniciado com a nova versão.

~~~bash
cd /opt/lowify/services/services-notifications
docker compose build

cd /opt/lowify/services/service-commerce-v2
docker compose build

cd /opt/lowify/edge/edge-public-api
docker compose build

cd /opt/lowify/edge/edge-gateway
docker compose build
~~~

### 7. Subir os componentes e aplicar a migration

~~~bash
cd /opt/lowify/services/services-notifications
docker compose up -d
docker compose exec -T services-notifications php bin/hyperf.php migrate --force --path=migrations/2026_11_03_000062_create_sale_recovery_template_bindings.php
docker compose exec -T services-notifications php bin/hyperf.php migrate:status
docker compose ps
docker compose logs --tail=100 services-notifications

cd /opt/lowify/services/service-commerce-v2
docker compose up -d
docker compose ps
docker compose logs --tail=100 service-commerce-v2

cd /opt/lowify/edge/edge-public-api
docker compose up -d
docker compose ps
docker compose logs --tail=100 edge-public-api

cd /opt/lowify/edge/edge-gateway
docker compose up -d
docker compose ps
docker compose logs --tail=100 edge-gateway
~~~

Não prossiga se a migration ou qualquer container falhar.

## Validação pós-deploy

1. Faça login no Dashboard Seller com um administrador e abra Configurações > Notificações WhatsApp.
2. Confirme que aparecem exatamente dois cenários: Recuperação 1 — com PIX e Recuperação 2 — com PIX.
3. Em cada cenário, escolha um template principal e, opcionalmente, um reserva dentre os oito templates PIX. Salve e recarregue a página; a seleção deve permanecer.
4. Use uma venda pendente de teste por PIX, com código PIX e recuperação de estágio 1 habilitada. No horário do disparo, confirme que o comprador recebe a mensagem com nome, produto, a frase de urgência, link de finalização e botão Copiar código Pix.
5. Repita com uma venda de estágio 2. Confirme que a seleção configurada para o estágio 2 é a utilizada; ela pode ser igual à do estágio 1.
6. Em uma venda por PIX sem código, confirme que nenhuma recuperação é enviada e que não há cobrança de comunicação.
7. Em uma venda sem código PIX de outro meio de pagamento, confirme que também não há chamada à Meta e que a comunicação é exibida como ignorada, sem cobrança.
8. Como conferência técnica opcional, confirme nos logs do Notifications que a ação recebida é sale_recovery com version: 2. Não limpar filas, Redis ou registros para validar.

Se algum resultado não ocorrer, interrompa novos testes de recuperação e execute o rollback antes de investigar.

## Rollback

1. Pare primeiro a administração nova retornando dashboard-seller, edge-gateway e edge-public-api para main, na ordem inversa da publicação. Reconstrua cada componente somente se a operação local exigir.
2. Retorne services-commerce-v2 para main antes do Notifications, para que nenhuma nova mensagem do contrato v2 seja publicada.
3. Antes de retornar o Notifications, aguarde o consumo das mensagens sale_recovery já publicadas no stream. Não apagar, mover ou limpar mensagens da fila.
4. Retorne services-notification para main e reconstrua o container. Não execute o down da migration: a tabela de vínculos e os templates seed podem permanecer sem afetar o código anterior.
5. Após o rollback, valide uma recuperação de venda de teste no fluxo anterior antes de reabrir campanhas.

O rollback restaura o código anterior, mas não desfaz mensagens já enviadas, outcomes, créditos consumidos/liberados, eventos de dispatch ou alterações feitas manualmente nos vínculos.
