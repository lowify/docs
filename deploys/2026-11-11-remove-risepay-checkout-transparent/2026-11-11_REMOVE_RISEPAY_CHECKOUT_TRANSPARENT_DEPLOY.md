# Deploy — remoção da RisePay do Checkout Transparente

## Objetivo

Impedir novos cadastros e novas disponibilizações da RisePay no Checkout
Transparente. As integrações, cobranças, webhooks e filas já existentes são
preservados para conciliação de pagamentos anteriores.

O comando abaixo consulta primeiro as integrações RisePay ativas por seller e
desativa somente o gateway global `integration_gateways.status`. Não use seed,
migration automática, `down`, exclusão de gateway ou limpeza de dados.

## Componentes publicados

| Repositório | Diretório de produção | Branch | Revisão mínima |
| --- | --- | --- | --- |
| `services-checkout-transparent-api` | `/opt/lowify-ct/services/services-checkout-transparent-api` | `fix/quick-fixes-2026-11-09` | substituir pelo SHA aprovado |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `fix/quick-fixes-2026-11-09` | substituir pelo SHA aprovado |

Não publicar Worker, Edge webhook, Edge Public API, Front Checkout ou Commerce
por esta alteração: eles preservam o tratamento de cobranças RisePay existentes.

## Banco de dados

Não há DDL nem migration. A coluna `integration_gateways.status` já existe e o
comando da API faz o DML idempotente necessário. Não executar seed: ele não é
procedimento de deploy e não deve ser usado para alterar estado operacional.

Antes do deploy, em sessão administrativa aprovada do banco da CT API, conferir
somente a estrutura/estado do gateway:

```sql
SELECT id, code, status, supports_webhook, supports_polling, polling_interval_seconds
FROM integration_gateways
WHERE code = 'risepay';
```

Deve haver exatamente uma linha. Não alterar dados por SQL neste roteiro; a
mudança é feita pelo comando versionado após a nova imagem da API iniciar.

## Pré-checagem

Não usar `reset`, `clean`, `stash` ou checkout forçado. Não apagar
integrações, cobranças, webhooks, Redis, filas ou DLQ.

```bash
cd /opt/lowify-ct/services/services-checkout-transparent-api
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/fix/quick-fixes-2026-11-09
docker compose config --quiet

cd /opt/lowify/front/dashboard-seller
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/fix/quick-fixes-2026-11-09
docker compose config --quiet
```

## Deploy

### 1. Checkout Transparente API

```bash
cd /opt/lowify-ct/services/services-checkout-transparent-api
git switch fix/quick-fixes-2026-11-09
git pull --ff-only origin fix/quick-fixes-2026-11-09
git merge-base --is-ancestor <sha-aprovado> HEAD
git rev-parse --short HEAD
docker compose up -d --build --force-recreate app
docker compose ps
docker compose logs --tail=100 app
```

Prosseguir somente com `app` em `Up`, sem erro de inicialização ou banco.

### 2. Desativar e registrar a RisePay

Este é o comando de terminal do host. Ele entra no container correto, consulta
as integrações ativas e desativa o gateway global na mesma execução:

```bash
cd /opt/lowify-ct/services/services-checkout-transparent-api
docker compose exec -T app php bin/hyperf.php integration-gateways:disable-risepay
```

Registrar a saída. O resultado esperado contém:

```text
RisePay active integrations before disable: <quantidade>; seller IDs: <ids ou none>.
RisePay gateway status: active -> inactive.
Existing integration records and charges were preserved.
```

Se a linha do gateway não existir, o comando falha e nenhum dado é alterado.
Uma segunda execução deve informar `inactive -> inactive`.

### 3. Dashboard Seller

```bash
cd /opt/lowify/front/dashboard-seller
git switch fix/quick-fixes-2026-11-09
git pull --ff-only origin fix/quick-fixes-2026-11-09
git merge-base --is-ancestor <sha-aprovado> HEAD
git rev-parse --short HEAD
docker compose ps
```

O Dashboard usa o diretório como bind mount. Não fazer build ou restart apenas
por esta atualização; prosseguir somente se os containers já ativos seguirem
`Up`.

## Validação pós-deploy

1. Reler no banco a mesma consulta da seção **Banco de dados**. Esperado:
   `code = risepay` e `status = inactive`.
2. Reexecutar o comando da etapa 2. Esperado: `inactive -> inactive`; a
   quantidade de integrações ativas pode continuar existindo, pois os registros
   históricos são preservados, mas ficam globalmente indisponíveis.
3. Em homologação, entrar em [Checkout Transparente de teste](https://dashboard.statuslive.site/integracoes_checkout_transparente.php); em produção, usar a mesma rota no domínio produtivo. Clicar em **Nova integração** e confirmar que RisePay não aparece entre os gateways.
4. Confirmar que uma integração RisePay antiga, caso exista, continua apenas
   visível na listagem histórica; não tentar revalidá-la, torná-la principal ou
   criar cobrança nova durante este teste.
5. Confirmar que Mercado Pago, Pagar.me, Woovi, Efibank e Kiwify continuam
   disponíveis para cadastro normal.

## Rollback

1. Reverter somente CT API e Dashboard para revisões aprovadas, seguindo a
   pré-checagem e os rebuilds aplicáveis.
2. Não reativar RisePay por seed, `down`, SQL improvisado ou exclusão de dados.
   Qualquer reativação exige procedimento novo e aprovado, pois pode expor
   integrações e cobranças históricas a novas tentativas.
3. Preservar `integration_gateways`, integrações, charges, webhooks e filas.

## Referências

- [Deploy original da RisePay](../2026-10-02-checkout-transparent-risepay/2026-10-02_CHECKOUT_TRANSPARENT_RISEPAY_DEPLOY.md)
- [Deploy de cartão do Checkout Transparente](../2026-10-29-checkout-transparent-card/2026-10-29_CHECKOUT_TRANSPARENT_CARD_DEPLOY.md)
