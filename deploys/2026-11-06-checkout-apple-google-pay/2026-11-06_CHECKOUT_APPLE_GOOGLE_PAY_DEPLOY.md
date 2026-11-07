# Deploy — Apple Pay e Google Pay no Checkout

## Objetivo

Publicar de forma controlada o suporte a Apple Pay e Google Pay no Checkout de
vendas avulsas por cartão. A carteira entrega uma autorização/token transitório
ao fluxo já existente de cartão; ela não cria um canal financeiro paralelo e
não altera o cálculo de produto, comissão, split, taxa de serviço, entrega ou
webhook público.

O lançamento de código não autoriza a habilitação global. A publicação deve
começar com as duas chaves globais desligadas e só pode avançar depois do
provisionamento externo, da homologação por PSP e do aceite operacional.

## Componentes e referências

Todos os diretórios abaixo são de produção no host principal `144.126.149.57`.
Não usar caminhos de desenvolvimento ou homologação neste roteiro.

| Repositório | Diretório de produção | Branch de deploy | Commit mínimo | Papel |
| --- | --- | --- | --- | --- |
| `services-banking-v2` | `/opt/lowify/services/services-banking-v2` | `feat/checkout-apple-google-pay` | `3c878af` | Recebe a instrução de cartão com autorização de carteira, preserva a classificação em `charges_card.wallet_card_id` e traduz a cobrança para Cielo ou Pagar.me. |
| `service-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/checkout-apple-google-pay` | `88e6907` | Resolve habilitação, valida a sessão Apple Pay no servidor, prepara Google Pay e encaminha a autorização transitória ao Banking. |
| `front-checkout` | `/opt/lowify/front/front-checkout` | `feat/checkout-apple-google-pay` | `6b03415` | Mostra as carteiras elegíveis, coleta os dados obrigatórios do comprador e envia o token, sem persistir dados de cartão. |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `feat/checkout-apple-google-pay` | `f1308348` | Permite ao seller habilitar Apple Pay/Google Pay por produto, subordinadas ao cartão de crédito. |

`services-wallet` não participa deste deploy: ele é a carteira interna de
saldo/extrato/saque e não é Apple Pay nem Google Pay. Edges não recebem código
nesta entrega; mantêm seu papel normal de borda entre Checkout e Commerce.

## Alterações incluídas

```text
Comprador -> Front Checkout -> Edge -> Commerce V2 -> Banking V2 -> PSP
                                  |                  |
                            regras de carteira   Cielo ou Pagar.me
```

- O meio de pagamento continua sendo cartão; a classificação da autorização é
  `card`, `apple_pay` ou `google_pay`.
- Apple Pay usa validação de sessão no Commerce V2. Em produção ela exige
  Merchant Identifier, certificado e chave de identidade; não existe caminho
  de mock no código publicado.
- Google Pay usa `PAYMENT_GATEWAY`: Cielo usa `gateway=cielo` e Pagar.me usa
  `gateway=pagarme`. Não usar integração Google `DIRECT` nem chave privada
  Google no Checkout.
- A carteira só é oferecida para pagamento à vista e quando cartão, produto,
  chave global, configuração do gateway e navegador/dispositivo forem
  compatíveis.
- A Dashboard impede wallet ligada com cartão desligado e reflete a
  configuração persistida ao reabrir o produto.
- `charges_card.wallet_card_id` é opcional para registros históricos; não há
  backfill. Dados brutos de cartão, CVV, token de carteira e segredos não são
  persistidos nem entram em logs funcionais.

Checkout Transparente, PIX, recorrência, `services-wallet`, billing próprio,
webhooks públicos e regras de split existentes estão fora do escopo.

## Pré-requisitos e bloqueadores

1. Registrar a revisão anterior aprovada dos quatro repositórios. Não usar
   `reset`, `clean`, `stash` nem checkout forçado para contornar árvore suja.
2. Confirmar acesso ao host, Docker e às sessões administrativas aprovadas dos
   bancos do Commerce e Banking. Confirmar backup recuperável antes dos DDLs.
3. Executar os DDLs em janela apropriada: são aditivos, mas podem adquirir
   lock. Não iniciar durante pico de checkout.
4. Não imprimir `.env`, CSR, CER, P12, certificado, chave privada, segredo de
   PSP/webhook, token de carteira, PAN, CVV ou dados pessoais.
5. Não limpar Redis, filas, DLQ, vendas, cobranças, refunds ou logs. Não
   executar migrations automáticas em nenhum dos dois backends.
6. O laboratório e extensões de navegador usados em homologação não fazem
   parte da publicação. Não instalar mock, endpoint HTTP de laboratório ou
   configuração de interceptação em produção.
7. Enquanto faltar qualquer aprovação externa, manter
   `checkout_apple_pay_enabled=0` e `checkout_google_pay_enabled=0`.
8. Antes da ativação, devem estar prontos: domínio HTTPS Apple verificado,
   Merchant Identifier, certificado de identidade e chave privada montados
   fora do Git, certificados/credenciamento PSP, Google Pay Merchant ID,
   `gatewayMerchantId` de Cielo e identificador Pagar.me/Stone aplicável.
   Consultar o [guia de provisionamento](../../plans/checkout-apple-google-pay/05_PROVISIONAMENTO_PRODUCAO_WALLETS.md).

## Pré-checagem obrigatória

Executar em cada diretório antes de qualquer `git switch`. Se houver qualquer
linha em `git status --porcelain=v1`, remoto inesperado ou branch ausente no
remoto, interromper e preservar o estado para avaliação.

```bash
cd /opt/lowify/services/services-banking-v2
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/checkout-apple-google-pay

cd /opt/lowify/services/service-commerce-v2
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/checkout-apple-google-pay

cd /opt/lowify/front/front-checkout
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/checkout-apple-google-pay

cd /opt/lowify/front/dashboard-seller
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/checkout-apple-google-pay
```

Checkout e Dashboard usam o diretório como bind mount em `/var/www/html`.
Confirmar antes da atualização; se a configuração produtiva divergir, parar em
vez de supor que apenas a atualização Git é suficiente.

```bash
cd /opt/lowify/front/front-checkout
docker compose config | grep -F '/var/www/html'

cd /opt/lowify/front/dashboard-seller
docker compose config | grep -F '/var/www/html'
```

## Banco de dados

Executar cada bloco por uma sessão administrativa já aprovada para o banco
correspondente. Não assumir nome de container, usuário, senha ou arquivo de
credencial.

### 1. Commerce V2 — produto e chaves globais

No banco do Commerce, conferir primeiro as colunas de `tbl_produtos`:

```sql
SELECT column_name, column_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'tbl_produtos'
  AND column_name IN ('apple_pay_enabled', 'google_pay_enabled')
ORDER BY FIELD(column_name, 'apple_pay_enabled', 'google_pay_enabled');
```

- **zero linhas:** executar o DDL uma única vez;
- **duas linhas** `TINYINT UNSIGNED NOT NULL DEFAULT 0`: não executar DDL;
- **qualquer outro resultado:** parar. Não adaptar tipo, nulabilidade ou
  posição no improviso.

```sql
ALTER TABLE tbl_produtos
    ADD COLUMN apple_pay_enabled TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER credit_card_enabled,
    ADD COLUMN google_pay_enabled TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER apple_pay_enabled;
```

Reexecutar a consulta e confirmar as duas colunas. Em seguida conferir as
chaves globais:

```sql
SELECT var_key, var_value
FROM system_vars
WHERE var_key IN ('checkout_apple_pay_enabled', 'checkout_google_pay_enabled')
ORDER BY FIELD(var_key, 'checkout_apple_pay_enabled', 'checkout_google_pay_enabled');
```

- **zero linhas:** inserir as duas chaves desligadas;
- **duas linhas:** confirmar que ambas começam com valor `0`;
- **qualquer outro resultado:** parar e corrigir pelo procedimento de dados
  aprovado, nunca pela migration automática.

```sql
INSERT INTO system_vars (var_key, var_value, updated_at)
VALUES
  ('checkout_apple_pay_enabled', '0', NOW()),
  ('checkout_google_pay_enabled', '0', NOW());
```

Não fazer backfill de produtos: ambos os campos permanecem `0` até alteração
explícita do seller no Dashboard.

### 2. Banking V2 — classificação da carteira

No banco do Banking, conferir coluna e índice:

```sql
SELECT column_name, column_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'charges_card'
  AND column_name = 'wallet_card_id';

SELECT index_name, column_name, seq_in_index
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'charges_card'
  AND index_name = 'idx_charges_card_wallet_id';
```

- **coluna e índice ausentes:** executar o DDL uma única vez;
- **coluna** `INT UNSIGNED NULL DEFAULT NULL` **e índice presente:** não
  executar DDL;
- **estado parcial ou divergente:** parar. Não criar índice/coluna isolado nem
  alterar dados existentes no improviso.

```sql
ALTER TABLE charges_card
    ADD COLUMN wallet_card_id INT UNSIGNED NULL DEFAULT NULL AFTER installments,
    ADD INDEX idx_charges_card_wallet_id (wallet_card_id, id);
```

Reexecutar ambas as consultas. Registros históricos devem permanecer com
`wallet_card_id = NULL`; não fazer backfill.

## Configuração segura de produção

Configurar os valores exclusivamente pelo cofre de segredos e pelos volumes
privados aprovados. Não copiar nem exibir os valores no terminal, no Git ou em
evidências.

| Configuração do Commerce V2 | Regra |
| --- | --- |
| `APPLE_PAY_MERCHANT_IDENTIFIER` | Merchant Identifier definitivo da Apple. |
| `APPLE_PAY_MERCHANT_CERTIFICATE_PATH` | Caminho privado, legível pelo processo, do Merchant Identity Certificate. |
| `APPLE_PAY_MERCHANT_PRIVATE_KEY_PATH` | Caminho privado da chave que corresponde ao certificado de identidade. |
| `GOOGLE_PAY_MERCHANT_ID` | Merchant ID aprovado no Google Pay & Wallet Console. |
| `CIELO_GOOGLE_PAY_GATEWAY_MERCHANT_ID` | Identificador fornecido pela Cielo para Google Pay. |
| `PAGARME_GOOGLE_PAY_GATEWAY_MERCHANT_ID` | Identificador Pagar.me/Stone aplicável. |
| `GOOGLE_PAY_TEST_MODE` | Deve ser explicitamente `false` em produção. |

O código final não possui o mock de sessão Apple Pay usado na homologação. Não
adicionar host de mock, permissão HTTP, extensão de navegador ou flag que
desvie validação Apple. Certificado de identidade Apple e certificado de
processamento do PSP têm finalidades diferentes; não os trocar.

Conferir apenas a chave booleana autorizada, sem imprimir o restante do `.env`:

```bash
cd /opt/lowify/services/service-commerce-v2
grep -n '^GOOGLE_PAY_TEST_MODE=false$' .env
```

Se esse comando não retornar exatamente uma linha, interromper a ativação.

## Sequência de deploy

O Banking V2 e Commerce V2 mantêm processos de longa duração: reconstruir e
recriar cada um. `--force-recreate` impede que um processo antigo continue
atendendo com a imagem anterior após o build. Os fronts recebem somente
atualização Git porque o código é montado por bind mount; não adicionar build
ou restart sem evidência operacional.

### 1. Aplicar e validar integralmente o schema

Concluir toda a seção **Banco de dados** antes de atualizar qualquer serviço.
Não executar `php bin/hyperf.php migrate`, `migrate --force`,
`migrate:rollback` ou outra migration automática.

### 2. Atualizar Banking V2

```bash
cd /opt/lowify/services/services-banking-v2
git switch feat/checkout-apple-google-pay
git pull --ff-only origin feat/checkout-apple-google-pay
git merge-base --is-ancestor 3c878af HEAD
git rev-parse --short HEAD
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 services-banking-v2
```

Prosseguir somente se `git merge-base` retornar zero, o commit for `3c878af`
ou descendente aprovado, o serviço estiver `Up` e não houver erro de schema,
conexão ou processo nos logs.

### 3. Atualizar Commerce V2

```bash
cd /opt/lowify/services/service-commerce-v2
git switch feat/checkout-apple-google-pay
git pull --ff-only origin feat/checkout-apple-google-pay
git merge-base --is-ancestor 88e6907 HEAD
git rev-parse --short HEAD
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

Prosseguir somente se `git merge-base` retornar zero, o commit for `88e6907`
ou descendente aprovado, `service-commerce-v2` estiver `Up` e os logs não
apontarem erro de schema, configuração de certificado, conexão ou processo.

### 4. Atualizar Front Checkout

```bash
cd /opt/lowify/front/front-checkout
git switch feat/checkout-apple-google-pay
git pull --ff-only origin feat/checkout-apple-google-pay
git merge-base --is-ancestor 6b03415 HEAD
git rev-parse --short HEAD
docker compose ps
```

Prosseguir somente se `git merge-base` retornar zero e todos os serviços que
já estavam ativos continuarem `Up`. Não reiniciar container só por esta
atualização de código montado.

### 5. Atualizar Dashboard Seller

```bash
cd /opt/lowify/front/dashboard-seller
git switch feat/checkout-apple-google-pay
git pull --ff-only origin feat/checkout-apple-google-pay
git merge-base --is-ancestor f1308348 HEAD
git rev-parse --short HEAD
docker compose ps
```

Prosseguir somente se `git merge-base` retornar zero e os serviços existentes
permanecerem `Up`. Não consumir ou reprocessar filas manualmente.

## Ativação controlada e validação pós-deploy

Publicar código não habilita as carteiras. As chaves globais e os flags dos
produtos devem iniciar desligados.

1. Confirmar que ambos os valores globais seguem em `0` e que produto com
   cartão desligado não oferece wallet.
2. Após os pré-requisitos externos, habilitar **um** método em **um** produto
   piloto pelo Dashboard. O Dashboard deve persistir e refletir os flags ao
   recarregar; não editar flags de produto por SQL.
3. Para liberar globalmente, usar somente a sessão administrativa aprovada:

   ```sql
   UPDATE system_vars
   SET var_value = '1', updated_at = NOW()
   WHERE var_key = 'checkout_apple_pay_enabled';
   ```

   Repetir para Google Pay somente depois de sua aprovação independente. Antes
   de cada comando, conferir a chave exata; depois, reler os dois valores.
4. Executar compra controlada por Cielo/Apple, Cielo/Google, Pagar.me/Apple e
   Pagar.me/Google, usando dispositivos e contas de sandbox/produção aprovados
   para o ambiente. Registrar apenas IDs técnicos, horário, valores e estado.
5. Em cada aprovação, conferir venda, `charges_card.wallet_card_id`, referência
   externa, split, taxa e entrega. O token não pode surgir em banco ou logs.
6. Testar cancelamento de wallet, recusa do PSP e envio duplicado; não deve
   haver venda paga, entrega ou segunda cobrança indevida. Confirmar a mensagem
   amigável no Checkout.
7. Confirmar que produto sem flag, chave global desligada ou dispositivo sem
   suporte não mostra botão quebrado e preserva cartão manual como fallback.
8. Confirmar callbacks autenticados e repetidos: a classificação e os efeitos
   comerciais devem permanecer idempotentes.
9. Só ampliar para outros produtos/sellers após aceite técnico, financeiro,
   jurídico e operacional.

## Rollback

1. Para interromper novas carteiras, primeiro desligar as chaves globais pela
   sessão administrativa aprovada:

   ```sql
   UPDATE system_vars
   SET var_value = '0', updated_at = NOW()
   WHERE var_key IN ('checkout_apple_pay_enabled', 'checkout_google_pay_enabled');
   ```

   Confirmar a leitura posterior. Desligar também os flags de produto pelo
   Dashboard quando aplicável. Isso não altera cobranças já criadas.
2. Manter Banking V2 e Commerce V2 em revisão compatível enquanto existirem
   vendas pendentes, callbacks, retries, refunds, disputas ou conciliação que
   possam consultar `wallet_card_id` ou a classificação da autorização.
3. Depois de estabilizar ou registrar pendências, publicar somente revisão de
   rollback previamente aprovada — branch de release ou `git revert` já no
   remoto — na ordem inversa: Dashboard, Checkout, Commerce V2 e Banking V2.
   Repetir a pré-checagem e usar exclusivamente `git pull --ff-only`.
4. Não remover as colunas, os índices, system vars, vendas, cobranças, filas,
   callbacks ou logs. As estruturas são aditivas e versões anteriores devem
   ignorar os campos novos.
5. Não modificar PSP, `services-wallet`, Redis, Edges ou configuração de
   domínio como tentativa de compensação. Qualquer ajuste financeiro exige
   procedimento aprovado próprio.

## Referências

- [Plano da feature](../../plans/checkout-apple-google-pay/README.md)
- [Contrato e configuração externa](../../plans/checkout-apple-google-pay/02_CONTRATO_E_CONFIGURACAO_EXTERNA.md)
- [Implementação, rollout e aceite](../../plans/checkout-apple-google-pay/03_IMPLEMENTACAO_ROLLOUT_E_ACEITE.md)
- [Contrato técnico de teste](../../plans/checkout-apple-google-pay/04_CONTRATO_TECNICO_DE_TESTE.md)
- [Provisionamento de produção](../../plans/checkout-apple-google-pay/05_PROVISIONAMENTO_PRODUCAO_WALLETS.md)
- [Checklist de execução](../../plans/checkout-apple-google-pay/CHECKLIST_EXECUCAO.txt)
