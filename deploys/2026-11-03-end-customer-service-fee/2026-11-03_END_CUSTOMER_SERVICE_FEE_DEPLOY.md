# Deploy — taxa de serviço cobrada do cliente final

## Objetivo

Publicar, de forma reversível e controlada, a composição de cobrança formada por valor dos produtos, taxa de serviço e total cobrado do cliente. A taxa é retida pela Lowify; ela não integra o valor econômico do seller, do afiliado ou de `sale_amount`.

Para uma nova cobrança elegível:

```text
gross_amount       = produtos após desconto e order bump, sem a taxa
service_fee_amount = taxa de serviço cobrada do cliente
charged_amount     = gross_amount + service_fee_amount; valor enviado ao PSP
sale_amount        = liquidação atual do seller; nunca inclui a taxa nova
```

Checkout Transparente está fora da cobrança: nele a taxa deve permanecer `0,00` e `charged_amount` deve ser igual a `gross_amount`. A cobrança de billing própria desse checkout não é alterada.

Esta publicação não altera retrospectivamente vendas, PIX pendentes, assinaturas ou webhooks públicos. Não há migration automática: o ajuste de `lowify.sales` é manual e deve ocorrer antes de iniciar o novo Commerce V2.

## Componentes e referências

Todos os componentes abaixo estão no host principal `144.126.149.57`. Os diretórios são de **produção**; não usar os caminhos de desenvolvimento ou homologação neste roteiro.

| Repositório | Diretório de produção | Branch de deploy | Commit mínimo | Papel |
| --- | --- | --- | --- | --- |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/end-customer-service-fee` | `664748e` | Resolve e persiste a composição, envia o total ao PSP, preserva snapshots, trata upsell, refund, disputa e detalhe administrativo. |
| `front-checkout` | `/opt/lowify/front/front-checkout` | `feat/end-customer-service-fee` | `4e9ae77` | Exibe produtos/taxa/total, atualiza as parcelas pelo total cobrado e mostra a composição no RDC. |
| `front-member-area` | `/opt/lowify/front/front-member-area` | `feat/end-customer-service-fee` | `f152c24` | Cria a compra Pix pelo fluxo canônico e mostra a composição no modal da Área de Membros. |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `feat/end-customer-service-fee` | `cabb114` | Administra override por seller, mostra a composição somente no detalhe administrativo e bloqueia escritores legados de pagamento. |

Os quatro commits estão publicados em `origin/feat/end-customer-service-fee` e foram conferidos localmente antes da elaboração deste roteiro.

## Alterações incluídas

```text
Checkout / Área de Membros
  -> Commerce V2 resolve a taxa no servidor
  -> sales grava gross_amount, service_fee_amount e charged_amount
  -> PSP recebe charged_amount
  -> eventos financeiros preservam a base do seller e afiliado em gross_amount
```

- O valor padrão é lido no Commerce pela variável `CHECKOUT_SERVICE_FEE_AMOUNT`; ausência, valor vazio ou inválido cairia no fallback interno de `0.99`.
- O override por seller é `user_system_vars.checkout_service_fee_fixed`. Zero desabilita a taxa para aquele seller; remover o override volta a usar a variável de ambiente.
- A tela administrativa exibe a composição somente em `admin_sale_detail`. Vendas históricas sem snapshot de `charged_amount` devem exibir `N/A`, sem reconstrução de valor.
- Refund voluntário usa o saldo de produtos; um reembolso obrigatório por lei ou falha usa o total efetivamente cobrado. Disputa pode informar o total do PSP, mas o bloqueio do seller continua limitado à parcela devolvível de produtos.
- Os escritores antigos do Dashboard para compra de cliente respondem `410`. Não reativá-los, não redirecioná-los e não testar pagamentos novos por eles.

## Pré-requisitos e bloqueadores

1. Registrar a referência anterior aprovada dos quatro repositórios. Não usar `reset`, `clean`, `stash` ou checkout forçado para contornar uma árvore suja.
2. Confirmar acesso ao host `144.126.149.57`, ao Docker e ao banco compartilhado `lowify`. Confirmar também uma cópia de segurança recuperável do banco antes do `ALTER TABLE`.
3. A execução do DDL requer janela adequada: `ALTER TABLE` é aditivo, mas pode adquirir lock. Não iniciá-lo durante um pico de checkout.
4. Não imprimir nem registrar `.env`, segredos de PSP, credenciais de banco, código PIX copiável, PAN, CVV, token de cartão ou dados pessoais.
5. Não limpar Redis, filas, DLQ, vendas, refunds ou logs. Não executar migrations automáticas do Commerce neste deploy.
6. A validação controlada interna não substitui a confirmação externa. Antes de ativar a cobrança para qualquer seller, devem estar aprovados: split e extrato em sandbox Cielo/Pagar.me; PIX central, Woovi BaaS e Pinbank; refund voluntário e refund integral obrigatório por PSP; e as decisões de Jurídico/Operação sobre assinaturas existentes, produtores legados e cash flow.

Enquanto houver qualquer bloqueador externo, a publicação técnica só pode iniciar o Commerce com `CHECKOUT_SERVICE_FEE_AMOUNT=0.00`. Não omitir a variável: se ela estiver ausente, o fallback interno é `0.99` e a cobrança seria ativada involuntariamente.

## Pré-checagem obrigatória

Executar em cada diretório da tabela, antes de qualquer `git switch`. Se `git status --porcelain=v1` produzir qualquer linha, se o remoto não for o esperado ou se a branch não existir no remoto, interromper e preservar o estado para avaliação.

```bash
cd /opt/lowify/services/service-commerce-v2
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/end-customer-service-fee

cd /opt/lowify/front/front-checkout
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/end-customer-service-fee

cd /opt/lowify/front/front-member-area
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/end-customer-service-fee

cd /opt/lowify/front/dashboard-seller
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/end-customer-service-fee
```

O Checkout, a Área de Membros e o Dashboard usam o código do diretório como bind mount em `/var/www/html`. Conferir essa premissa antes da atualização; se a configuração produtiva divergir, parar em vez de presumir que somente a atualização Git é suficiente:

```bash
cd /opt/lowify/front/front-checkout
docker compose config | grep -F '/var/www/html'

cd /opt/lowify/front/front-member-area
docker compose config | grep -F '/var/www/html'

cd /opt/lowify/front/dashboard-seller
docker compose config | grep -F '/var/www/html'
```

## Banco de dados

O banco é `lowify`. Executar as consultas por uma sessão administrativa já aprovada para esse banco; não assumir nome de container, usuário, senha ou arquivo de credencial.

### Pré-check

```sql
SELECT column_name, column_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'sales'
  AND column_name IN ('service_fee_amount', 'charged_amount')
ORDER BY FIELD(column_name, 'service_fee_amount', 'charged_amount');
```

Interpretar o resultado antes de prosseguir:

- **zero linhas:** executar o DDL abaixo uma única vez;
- **duas linhas com** `service_fee_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00` e `charged_amount DECIMAL(12,2) NULL`: não executar DDL novamente;
- **qualquer outro resultado:** parar. Não aplicar alteração parcial, não adaptar tipo/nulabilidade no improviso e não marcar migration manualmente.

### DDL manual

Executar somente quando o pré-check retornar zero linhas:

```sql
ALTER TABLE sales
    ADD COLUMN service_fee_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00 AFTER gross_amount,
    ADD COLUMN charged_amount DECIMAL(12,2) NULL AFTER service_fee_amount;
```

Reexecutar imediatamente o pré-check e confirmar as duas colunas, tipo, default e nulabilidade. Não fazer backfill: registros históricos mantêm `service_fee_amount = 0.00` e `charged_amount = NULL`.

As colunas são aditivas. Depois que qualquer escritor novo gravar dados, rollback operacional não remove colunas nem apaga snapshots financeiros.

## Sequência de deploy

Modo de rebuild: o Commerce V2 é reconstruído e reiniciado porque mantém processos de longa duração. Os três fronts recebem apenas atualização Git: seus diretórios são bind mounts e não há mudança de imagem nesta entrega. Não introduzir build ou restart adicional nos fronts sem evidência operacional.

### 1. Aplicar e validar o schema

Concluir integralmente a seção **Banco de dados** antes de atualizar a Área de Membros. Ela consulta os novos campos diretamente e não deve receber código antes de o schema existir.

### 2. Atualizar Front Checkout

```bash
cd /opt/lowify/front/front-checkout
git switch feat/end-customer-service-fee
git pull --ff-only origin feat/end-customer-service-fee
git merge-base --is-ancestor 4e9ae77 HEAD
git rev-parse --short HEAD
docker compose ps
```

Prosseguir somente se `git merge-base` retornar código zero e o commit exibido for `4e9ae77` ou um descendente aprovado. Não reiniciar o container apenas para esta mudança de código montada.

### 3. Atualizar Área de Membros

```bash
cd /opt/lowify/front/front-member-area
git switch feat/end-customer-service-fee
git pull --ff-only origin feat/end-customer-service-fee
git merge-base --is-ancestor f152c24 HEAD
git rev-parse --short HEAD
docker compose ps
```

Prosseguir somente se `git merge-base` retornar código zero. Confirmar que `front-members-area` permanece `Up`; não gerar PIX, não alterar acesso e não criar compra como teste técnico desta etapa.

### 4. Atualizar Dashboard Seller

```bash
cd /opt/lowify/front/dashboard-seller
git switch feat/end-customer-service-fee
git pull --ff-only origin feat/end-customer-service-fee
git merge-base --is-ancestor cabb114 HEAD
git rev-parse --short HEAD
docker compose ps
```

Os workers do Dashboard não receberam alteração nesta entrega. Manter todos os serviços existentes `Up`; não consumir nem reprocessar filas manualmente.

### 5. Configurar e publicar Commerce V2

No arquivo `/opt/lowify/services/service-commerce-v2/.env`, definir explicitamente um dos valores abaixo antes de recriar o container:

```text
# publicação técnica sem ativação global
CHECKOUT_SERVICE_FEE_AMOUNT=0.00

# usar somente após todas as aprovações externas e a expansão aprovada
CHECKOUT_SERVICE_FEE_AMOUNT=0.99
```

Não registrar o restante do `.env`. Conferir apenas a presença e o valor dessa chave autorizada:

```bash
cd /opt/lowify/services/service-commerce-v2
grep -n '^CHECKOUT_SERVICE_FEE_AMOUNT=' .env
git switch feat/end-customer-service-fee
git pull --ff-only origin feat/end-customer-service-fee
git merge-base --is-ancestor 664748e HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

Prosseguir somente se `git merge-base` retornar código zero, `service-commerce-v2` estiver `Up` e não houver erro de schema, conexão ou processo nos logs. Não executar `php bin/hyperf.php migrate`, `migrate --force`, `migrate:rollback` ou qualquer migration automática neste release.

## Ativação controlada e validação pós-deploy

Publicar código não autoriza cobrança global. A ativação deve ser em duas fases.

1. Manter `CHECKOUT_SERVICE_FEE_AMOUNT=0.00` após o deploy técnico. Confirmar que uma venda controlada canônica persiste `service_fee_amount = 0.00` e `charged_amount = gross_amount`.
2. Após todas as confirmações externas da seção **Pré-requisitos e bloqueadores**, selecionar um seller piloto pelo Dashboard administrativo e definir o override `checkout_service_fee_fixed` para o valor aprovado, por exemplo `0.99`. Não criar ou editar essa chave por SQL.
3. Para o piloto, realizar uma venda controlada em cada meio aprovado e registrar somente identificadores técnicos, horário, valores e estado. O esperado é `charged_amount = gross_amount + service_fee_amount`, com seller/afiliado preservados na base de produtos.
4. Conferir no PSP e no extrato que a alocação de seller/afiliado não aumentou e que a Lowify reteve a taxa. Conferir também um refund voluntário e um caso em que o reembolso integral seja obrigatório, segundo a política aprovada.
5. No checkout, validar a composição visual e as parcelas calculadas sobre o total. No RDC, validar que o PIX pendente mostra o snapshot original mesmo após alterar configuração.
6. Na Área de Membros, abrir um produto bloqueado elegível, gerar somente a cobrança controlada autorizada e confirmar que o modal mostra produtos, taxa e total iguais aos snapshots. Não registrar QR ou PIX copiável na evidência.
7. No detalhe administrativo da venda, confirmar produtos, taxa e total; no detalhe do seller, confirmar que a composição administrativa não aparece. Em venda histórica, `charged_amount` deve continuar `N/A`.
8. Criar um checkout Transparente controlado com configuração positiva e confirmar taxa `0.00` e `charged_amount = gross_amount`. Não tocar em billing, integração ou configuração do Checkout Transparente.
9. Confirmar que os endpoints legados de compra do Dashboard não criam cobrança; o comportamento esperado é `410`. O polling de pedidos históricos deve continuar disponível.
10. Somente após aceite técnico, financeiro, jurídico e operacional do piloto, alterar o valor global para `CHECKOUT_SERVICE_FEE_AMOUNT=0.99`, reconstruir apenas o Commerce V2 com `docker compose up -d --build` e remover o override do piloto para que ele herde o padrão. Repetir os itens 3 a 8 antes de ampliar para outros sellers.

Se qualquer verificação falhar, manter o default global em `0.00` ou remover o override do piloto, preservar vendas, snapshots, filas e logs sanitizados, e interromper a expansão.

## Rollback

1. Para interromper novas cobranças com taxa, primeiro definir `CHECKOUT_SERVICE_FEE_AMOUNT=0.00` e reconstruir somente `services-commerce-v2`. Para um seller piloto, remover ou zerar o override pelo Dashboard. Isso não altera cobranças já criadas.
2. Manter o Commerce V2 na revisão compatível enquanto existirem vendas pendentes, refunds, disputas, retries ou callbacks que possam ler os novos snapshots.
3. Após estabilizar ou registrar as pendências, publicar uma revisão de rollback previamente aprovada — branch de release ou commit de `git revert` já enviado ao remoto — na ordem inversa: Dashboard, Área de Membros, Checkout e, por último, Commerce V2. Repetir a pré-checagem e usar somente `git pull --ff-only`; não usar reset ou checkout forçado.
4. Não remover `sales.service_fee_amount` nem `sales.charged_amount`, não apagar vendas, refunds, filas, logs ou configurações de seller. Versões anteriores ignoram as colunas aditivas.
5. Não alterar Checkout Transparente, Banking, Wallet, Edges, Redis ou PSP como tentativa de compensação. Qualquer compensação financeira exige procedimento próprio aprovado.

## Referências

- [Plano da feature](../../plans/end-customer-service-fee/README.md)
- [Documentação da feature](../../features/end-customer-service-fee/README.md)
- [Roteiro manual controlado](../../features/end-customer-service-fee/manual-browser-lab.md)
- [SQL de referência da feature](../../features/end-customer-service-fee/schema.sql)
