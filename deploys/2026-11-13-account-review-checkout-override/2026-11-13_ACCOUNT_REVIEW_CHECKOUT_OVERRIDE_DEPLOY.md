# Deploy — override de checkout durante revisão de conversão de conta

> Status: pronto para homologação; aplicar o DDL manual antes de iniciar o novo `services-account`.

## Objetivo

Publicar a continuidade de checkout para sellers previamente aprovados que convertem PF↔PJ. A conversão passa a abrir uma nova review real, enquanto um override específico mantém checkout disponível. Saque, completion de conta, conta bancária e integração de cartão continuam bloqueados pelo status real da review.

## Componentes e referências

| Repositório | Diretório na VPS | Branch de deploy | Commit |
| --- | --- | --- | --- |
| `services-account` | `/opt/lowify/services/services-account` | `feat/account-review-checkout-override` | `e647dee` |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/account-review-checkout-override` | `c3b80cd` |

`dashboard-seller`, `edge-gateway` e `edge-public-api` não recebem alteração nesta entrega: a conversão já chega ao Account e o Commerce V2 consulta o Account diretamente pelo contrato interno existente.

## Alterações incluídas

- `services-account` adiciona `tbl_usuarios.checkout_review_approved_override`.
- Conversões PF↔PJ deixam de gravar `account_review_status = NULL`; passam a gravar `pending` e enfileirar o refresh já existente.
- Quando a review anterior era aprovada, a conversão grava o override em `1`.
- Documentos pessoais completos e aprovados são preservados; documentos ausentes, incompletos, pendentes ou rejeitados seguem exigindo novo IDV/KYC.
- O override é removido apenas quando a nova review é aprovada; ele permanece em reprovação ou solicitação de reenvio.
- `services-commerce-v2` permite checkout de seller na fase 3 quando o review real está aprovado **ou** o override está ativo. As regras de seller ativo, cash-in e checkout transparente permanecem inalteradas.

## Pré-requisitos

1. Confirmar acesso administrativo ao banco `lowify` e backup recuperável antes do DDL.
2. Executar o precheck manual e prosseguir somente com o resultado descrito em [PRECHECK.sql](sql/lowify/PRECHECK.sql).
3. Não imprimir `.env`, credenciais, tokens ou dados pessoais. Não limpar Redis, filas, DLQ ou registros de review.
4. O DDL é manual. Não executar `migrate`, `migrate --force` ou rollback automático deste serviço nesta entrega.

## Banco de dados

Aplicar manualmente os arquivos deste deploy no banco `lowify`:

1. Executar [PRECHECK.sql](sql/lowify/PRECHECK.sql).
2. Se retornar zero linhas, executar [DEPLOY.sql](sql/lowify/DEPLOY.sql) uma única vez.
3. Executar [VALIDATE.sql](sql/lowify/VALIDATE.sql) e confirmar a coluna com tipo `TINYINT(1)`, `NOT NULL` e default `0`.

Se o precheck retornar a coluna já no formato esperado, não executar o DDL. Qualquer formato diferente exige interrupção e análise; não adaptar schema manualmente durante o deploy.

## Sequência de deploy

### 1. Precheck de código

Em cada repositório, confirmar árvore limpa, remoto correto e branch publicada antes de trocar qualquer container:

```bash
cd /opt/lowify/services/services-account
git status --porcelain=v1
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/account-review-checkout-override

cd /opt/lowify/services/service-commerce-v2
git status --porcelain=v1
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/account-review-checkout-override
```

Se qualquer árvore estiver alterada ou a branch remota não existir, parar.

### 2. Aplicar DDL manual

Executar o precheck, DDL quando aplicável e validação da seção Banco de dados antes de iniciar o novo Account. A coluna aditiva com default `0` preserva sellers existentes.

### 3. Publicar Account

```bash
cd /opt/lowify/services/services-account
git switch feat/account-review-checkout-override
git pull --ff-only origin feat/account-review-checkout-override
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

### 4. Publicar Commerce V2

```bash
cd /opt/lowify/services/service-commerce-v2
git switch feat/account-review-checkout-override
git pull --ff-only origin feat/account-review-checkout-override
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
```

## Validação pós-deploy

1. Com uma conta de teste aprovada, faça uma conversão PF→PJ ou PJ→PF pelo painel administrativo. A conta deve exibir nova review pendente.
2. Abra um checkout de produto dessa conta em outro navegador. Ele deve continuar disponível para iniciar uma compra.
3. Tente acessar fluxo de saque, conta bancária ou integração de cartão com a mesma conta. A interface deve informar que o cadastro/review ainda precisa ser concluído.
4. No painel administrativo, conclua a nova review como aprovada. O checkout deve continuar disponível e o override deve ser removido.
5. Em uma conta de teste separada, conclua a nova review como reprovada ou com reenvio solicitado. O checkout deve continuar disponível pelo override, enquanto os fluxos cadastrais seguem pendentes/restritos.

Como conferência técnica opcional, verificar os logs normais dos dois containers para erros de schema, conexão ou consumer. Não consumir ou limpar filas manualmente.

## Rollback

1. Reverter primeiro o Commerce V2 ao commit anterior e reconstruir o container; isso remove a leitura do novo override.
2. Reverter depois o Account ao commit anterior e reconstruir o container.
3. Não remover a coluna durante rollback normal: ela é aditiva, default `0` e pode existir enquanto código anterior opera.
4. Não apagar reviews, documentos, eventos ou mensagens de fila. A remoção de coluna somente pode ser considerada em manutenção posterior, após confirmação de que nenhum código depende dela.

## Referências

- [Plano da feature](../../plans/account-review-checkout-override/README.md)
- [PRECHECK.sql](sql/lowify/PRECHECK.sql)
- [DEPLOY.sql](sql/lowify/DEPLOY.sql)
- [VALIDATE.sql](sql/lowify/VALIDATE.sql)
