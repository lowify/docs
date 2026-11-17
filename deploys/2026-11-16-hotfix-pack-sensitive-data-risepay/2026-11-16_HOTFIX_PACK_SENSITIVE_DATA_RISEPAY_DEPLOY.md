# Deploy — pacote de hotfixes: privacidade, Vendas, WhatsApp e RisePay

**Status:** pronto para os componentes Dashboard Seller e Notifications; bloqueado para a CT API até aprovação explícita da revisão descrita em [Decisão pendente da CT API](#decisão-pendente-da-ct-api).

## Objetivo

Publicar um pacote que reúne quatro correções independentes:

- botão de olho para ocultar dados sensíveis no Dashboard e em Vendas;
- correção do filtro de vendas por Cartão, mantendo compatibilidade com URLs antigas que usam `gateway=cartao`;
- correção do salvamento de vínculos de template de recuperação no WhatsApp Meta;
- remoção da RisePay dos novos cadastros do Checkout Transparente, preservando integrações, cobranças, webhooks e filas históricas.

Os hosts são separados: a CT API fica em `80.190.72.228`; Dashboard Seller e Notifications ficam em `144.126.149.57`.

## Componentes e referências

| Repositório | Host | Diretório | Branch | Revisão | Ação |
| --- | --- | --- | --- | --- | --- |
| `dashboard-seller` | `144.126.149.57` | `/opt/lowify/front/dashboard-seller` | `fix/hotfix-pack-2026-11-16` | `0944fc96` | atualizar arquivos via bind mount; sem build/restart |
| `services-notifications` | `144.126.149.57` | `/opt/lowify/services/services-notifications` | `fix/hotfix-pack-2026-11-16` | `0dabab3` | rebuild e recreate do serviço |
| `services-checkout-transparent-api` | `80.190.72.228` | `/opt/lowify-ct/services/services-checkout-transparent-api` | `fix/quick-fixes-2026-11-09` | `bbcf1b1` | **não executar sem aprovação da decisão pendente** |

Não publicar Worker, CT Webhook, Edge Public API, Front Checkout, Commerce, banco, Redis ou filas como efeito colateral deste pacote.

## Alterações incluídas

### Dashboard Seller

- Oculta valores, pedidos, nomes, e-mails, produtos, progresso e detalhes de vendas ao usar o ícone de olho em Dashboard e Vendas.
- Mantém os gráficos com dados reais; no gráfico e filtro de produtos, o nome passa a ser exibido como estrelas quando a ocultação está ativa.
- Corrige o valor enviado pelo filtro Cartão para `card` e aceita `cartao` em URLs antigas.
- Remove a RisePay das opções de nova integração do Checkout Transparente no Dashboard.

### Notifications

- Associa corretamente o código de cenário da rota ao parâmetro do controller responsável por salvar os templates de recuperação WhatsApp.

### CT API

- A revisão `bbcf1b1` fornece o comando `integration-gateways:disable-risepay`, que registra a quantidade de integrações RisePay ativas e desativa somente o gateway global de novos usos.
- O comando é idempotente e não exclui integrações, cobranças, webhooks, Redis ou filas históricas.

## Decisão pendente da CT API

`fix/quick-fixes-2026-11-09` na CT API não é uma revisão isolada de RisePay: ela está 95 arquivos à frente de `main`, incluindo mudanças anteriores de checkout, assinatura, cartão, filas, migrations e dependências.

Não publicar a CT API com este documento até uma pessoa responsável aprovar explicitamente essa revisão completa ou fornecer uma branch/SHA dedicado somente à remoção da RisePay. O Dashboard e Notifications podem ser publicados sem a CT API, mas a RisePay continuará globalmente ativa até a etapa da CT API ser aprovada e concluída.

## Pré-requisitos

- Acesso SSH aos dois hosts e permissão de leitura/escrita nos três repositórios.
- Cada repositório deve estar limpo, ter `origin` apontando para o repositório oficial e possuir a branch remota declarada acima.
- Registrar o commit atual de cada repositório antes de trocar de branch; ele será a referência de rollback.
- Para a CT API, acesso a uma sessão administrativa aprovada do banco, somente para consulta prévia do gateway RisePay.
- Não usar `reset`, `clean`, `stash`, checkout forçado, seed, migration automática, exclusão de dados ou limpeza de Redis/filas.

## Banco de dados

Não há DDL ou migration neste pacote.

Após a aprovação da CT API e antes do deploy, executar somente a consulta abaixo em sessão administrativa aprovada. Ela não altera dados:

```sql
SELECT id, code, status, supports_webhook, supports_polling, polling_interval_seconds
FROM integration_gateways
WHERE code = 'risepay';
```

O resultado esperado é exatamente uma linha. A alteração de status deve ser feita exclusivamente pelo comando versionado da CT API, nunca por SQL manual.

## Sequência de deploy

### 1. Pré-checagem do Dashboard Seller — `144.126.149.57`

```bash
ssh root@144.126.149.57
cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git branch --show-current
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/fix/hotfix-pack-2026-11-16
```

Se `git status --porcelain=v1` retornar qualquer linha, interromper este componente e preservar o estado local.

### 2. Publicar Dashboard Seller — `144.126.149.57`

```bash
cd /opt/lowify/front/dashboard-seller
git switch fix/hotfix-pack-2026-11-16
git pull --ff-only origin fix/hotfix-pack-2026-11-16
git merge-base --is-ancestor 0944fc96 HEAD
git rev-parse --short HEAD
docker compose ps
```

O Dashboard usa bind mount: não executar build, restart ou recriação de container nesta etapa.

### 3. Pré-checagem do Notifications — `144.126.149.57`

```bash
cd /opt/lowify/services/services-notifications
git status --porcelain=v1
git branch --show-current
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/fix/hotfix-pack-2026-11-16
docker compose config --quiet
```

Se houver mudança local, interromper este componente. Não descarte nem armazene alterações automaticamente.

### 4. Publicar Notifications — `144.126.149.57`

```bash
cd /opt/lowify/services/services-notifications
git switch fix/hotfix-pack-2026-11-16
git pull --ff-only origin fix/hotfix-pack-2026-11-16
git merge-base --is-ancestor 0dabab3 HEAD
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 services-notifications
```

Prosseguir somente se o serviço estiver ativo e não houver erro de inicialização, rota ou conexão.

### 5. CT API — `80.190.72.228` — executar somente após aprovação explícita

```bash
ssh root@80.190.72.228
cd /opt/lowify-ct/services/services-checkout-transparent-api
git status --porcelain=v1
git branch --show-current
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/fix/quick-fixes-2026-11-09
docker compose config --quiet
git switch fix/quick-fixes-2026-11-09
git pull --ff-only origin fix/quick-fixes-2026-11-09
git merge-base --is-ancestor bbcf1b1 HEAD
docker compose up -d --build --force-recreate app
docker compose ps
docker compose logs --tail=100 app
docker compose exec -T app php bin/hyperf.php integration-gateways:disable-risepay
```

O resultado do último comando deve informar a transição `active -> inactive` ou `inactive -> inactive`, além de registrar a quantidade de integrações ativas preservadas. Se a linha do gateway não existir, interromper: nenhum dado deve ser alterado manualmente.

## Validação pós-deploy

### Dashboard Seller

1. Abra Dashboard e clique no ícone de olho. Confirme que valores, progresso, pedidos, clientes e e-mails ficam ocultos; os gráficos continuam preenchidos e os nomes de produto aparecem como estrelas.
2. Abra Vendas, escolha um período com uma venda de cartão, selecione Cartão e clique em Filtrar. A venda deve aparecer.
3. Abra uma URL antiga com `gateway=cartao`. O mesmo filtro de Cartão deve funcionar.
4. Abra Checkout Transparente, clique em Nova integração e confirme que RisePay não aparece entre as opções.

### Notifications

1. Como administrador, abra Configurações do sistema > WhatsApp Meta.
2. Altere um template principal ou reserva de recuperação, clique em Salvar e recarregue a página.
3. Confirme que a seleção permanece e que não aparece a mensagem `1` nem erro de resposta inválida.

### CT API — somente após aprovação

1. Confirme que a consulta de banco mostra a RisePay com `status = inactive`.
2. Execute novamente o comando de desativação; o resultado deve informar `inactive -> inactive`.
3. Confirme que integrações RisePay antigas, se existirem, permanecem apenas para consulta histórica e que não é possível criar nova integração ou nova cobrança RisePay.
4. Confirme que Mercado Pago, Pagar.me, Woovi, Efibank e Kiwify continuam disponíveis para cadastro normal.

## Rollback

1. Para Dashboard Seller e Notifications, retornar cada repositório ao commit registrado na pré-checagem, usando uma revisão de rollback previamente aprovada; não usar reset forçado.
2. Para Notifications, reconstruir e recriar somente o serviço após publicar a revisão de rollback.
3. Para a CT API, publicar somente uma revisão de rollback aprovada. Não reativar RisePay por SQL, seed, `down`, exclusão de dados ou limpeza de infraestrutura.
4. Não apagar integrações, cobranças, webhooks, Redis, filas ou DLQ. O comando de desativação preserva os dados históricos.

## Referências

- [Filtro Cartão e templates WhatsApp](../2026-11-11-sales-card-and-whatsapp-template-fixes/2026-11-11_SALES_CARD_AND_WHATSAPP_TEMPLATE_FIXES_DEPLOY.md)
- [Remoção da RisePay](../2026-11-11-remove-risepay-checkout-transparent/2026-11-11_REMOVE_RISEPAY_CHECKOUT_TRANSPARENT_DEPLOY.md)
