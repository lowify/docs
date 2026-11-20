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

## Gate de código — auditoria de 20/11/2026

O destino de publicação é `main`, após revisão e merge aprovados; não publicar
uma combinação improvisada entre `main` e branches de feature.

Na auditoria de 20/11/2026, Commerce V2, Front Checkout e Dashboard Seller
já continham o código de wallet em `main`. O `main` de Banking V2 ainda não
continha o tratamento de autorização de wallet, e os dois Edges ainda não
continham as rotas correspondentes. Portanto, **não é seguro executar este
deploy somente com o estado atual de `main`**.

Antes do deploy, incorporar em `main` por PR/revisão aprovada, no mínimo:

- Banking V2: `f6d4ed23c2cad24ac6a22a703b3bdea53a81f2f9`,
  `7a19ec0a9763ac3fbdbd0cff47614348ba6964d5` e
  `3c878afa7eb7baac931a904cf182aa6dff0e9564`;
- Edge Gateway: `8ba4b321f7f9d9fd0dd33c5c27e88da2fea8e689`;
- Edge Public API: `420deac2130f6c339fc4c74497850c35016c6e2b`.

Atualizar os SHAs aprovados nesta seção se a revisão usar commits equivalentes
ou uma resolução diferente. Enquanto este gate não estiver satisfeito, manter
as duas chaves globais em `0` e não iniciar a etapa de ativação.

## Componentes e referências

Todos os diretórios abaixo são de produção no host principal `144.126.149.57`.
Não usar caminhos de desenvolvimento ou homologação neste roteiro.

| Repositório | Diretório de produção | Branch de deploy | Revisão mínima | Papel |
| --- | --- | --- | --- | --- |
| `services-banking-v2` | `/opt/lowify/services/services-banking-v2` | `main` | Gate de código desta página satisfeito e SHA aprovado | Recebe a instrução de cartão com autorização de carteira, preserva a classificação em `charges_card.wallet_card_id` e traduz a cobrança para Cielo ou Pagar.me. |
| `service-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `main` | SHA aprovado após revisão | Resolve habilitação, valida a sessão Apple Pay no servidor, prepara Google Pay e encaminha a autorização transitória ao Banking. |
| `edge-gateway` | `/opt/lowify/edge/edge-gateway` | `main` | Gate de código desta página satisfeito e SHA aprovado | Encaminha as rotas internas de checkout e wallet para os serviços. |
| `edge-public-api` | `/opt/lowify/edge/edge-public-api` | `main` | Gate de código desta página satisfeito e SHA aprovado | Extrai e propaga JWT nas rotas públicas do fluxo. |
| `front-checkout` | `/opt/lowify/front/front-checkout` | `main` | SHA aprovado após revisão | Mostra as carteiras elegíveis, coleta os dados obrigatórios do comprador e envia o token, sem persistir dados de cartão. |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `main` | SHA aprovado após revisão | Permite ao seller habilitar Apple Pay/Google Pay por produto, subordinadas ao cartão de crédito. Inclui a base de Didit Legacy Sessions. |

`services-wallet` não participa deste deploy: ele é a carteira interna de
saldo/extrato/saque e não é Apple Pay nem Google Pay. Os dois edges participam
para manter as rotas e o contrato de autenticação do fluxo atualizados.

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

1. Registrar a revisão anterior aprovada dos seis repositórios e confirmar que
   Didit Legacy Sessions já foi publicado/aceito antes da etapa do Dashboard.
   Não usar
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
git show-ref --verify --quiet refs/remotes/origin/main

cd /opt/lowify/services/service-commerce-v2
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/main

cd /opt/lowify/edge/edge-gateway
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/main

cd /opt/lowify/edge/edge-public-api
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/main

cd /opt/lowify/front/front-checkout
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/main

cd /opt/lowify/front/dashboard-seller
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/main
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
privados aprovados. A versão de produção usa validação Apple com certificado
de identidade e chave privada, além da configuração oficial de Google Pay.
O roteiro abaixo é a fonte única para obter e posicionar cada variável.

### Preenchimento das novas variáveis — roteiro operacional

As variáveis novas são configuradas no arquivo de produção
`/opt/lowify/services/service-commerce-v2/.env`: o
`docker-compose.yml` desse serviço declara exatamente `env_file: .env`. O cofre
de segredos aprovado deve escrever esses valores nesse arquivo durante o deploy;
os certificados Apple ficam em volume privado e o `.env` guarda apenas os
caminhos internos. Esta seção segue a ordem real de obtenção e já informa onde
cada valor deve ser colocado.

#### 1. Google Pay — Merchant ID, domínio e modo de produção

1. Abrir [Google Pay & Wallet Console](https://pay.google.com/) usando a conta
   corporativa proprietária da Lowify.
2. No menu esquerdo, abrir **Google Pay API**. Se o Console mostrar
   **Get started**, clicar nele; completar o **Business Profile** com tipo
   **Merchant** e aceitar os termos apresentados.
3. Na página **Google Pay API**, localizar o **Merchant ID** no canto superior
   direito. Copiar esse valor e gravar no cofre como
   `GOOGLE_PAY_MERCHANT_ID`. No arquivo final do Commerce V2, a linha fica:

   ```dotenv
   GOOGLE_PAY_MERCHANT_ID=<Merchant ID copiado do Console>
   ```

4. Ainda em **Google Pay API**, abrir **Integrations** e, na área
   **Integrate with your website**, clicar em **Add website**. Informar
   `pay.statuslive.site` se ele exibirá o botão em produção; repetir para
   `checkout.statuslive.site` somente se esse host também servir o Checkout.
5. Na tela seguinte, selecionar **Gateway**, escolher o provedor aplicável,
   anexar capturas reais do Checkout e clicar em **Save**; depois clicar em
   **Submit for approval**. A página de integrações deve mostrar o status de
   aprovação do domínio antes da ativação produtiva.
6. Depois da aprovação do domínio e da ativação do PSP correspondente, gravar
   a linha abaixo no mesmo `.env` do Commerce V2:

   ```dotenv
   GOOGLE_PAY_TEST_MODE=false
   ```

   Esse valor faz o Checkout usar `PaymentsClient` com ambiente `PRODUCTION`.
   O request já envia `currencyCode=BRL` e `countryCode=BR`; essas duas
   propriedades são de código e não exigem variável adicional.

#### 2. Google Pay com Cielo — identificador do gateway

1. Confirmar qual EC/loja Cielo será usado pelos checkouts produtivos.
2. Pelo canal de suporte ou gerente Cielo da conta, solicitar o
   **`gatewayMerchantId` de Google Pay da loja/EC produtivo**. A documentação
   pública da Cielo informa que esse dado é fornecido pelo gateway e aparece no
   formato GUID de 36 caracteres, como
   `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`.
3. No portal Cielo da mesma loja/EC, confirmar com o suporte que Google Pay foi
   habilitado para produção. O caminho público de ativação não é documentado
   pela Cielo; por isso, a confirmação deve vir do canal Cielo responsável pela
   conta.
4. Com o GUID recebido, adicionar ao cofre e ao `.env` do Commerce V2:

   ```dotenv
   CIELO_GOOGLE_PAY_GATEWAY_MERCHANT_ID=<GUID produtivo informado pela Cielo>
   ```

   Quando o checkout selecionar Cielo, o código envia `gateway=cielo` e usa
   precisamente esse valor como `gatewayMerchantId` para o Google Pay.

#### 3. Google Pay com Pagar.me/Stone — identificador do gateway

1. Confirmar a conta Pagar.me/Stone que receberá as vendas produtivas.
2. Pelo suporte ou gerente dessa conta, solicitar o valor que deve ser enviado
   como **`gatewayMerchantId` para Google Pay com `gateway=pagarme`**. A
   documentação pública da Pagar.me descreve a ativação da conta Stone e a
   aprovação prévia do Merchant ID Google, mas não publica uma tela universal
   para extrair esse valor; o suporte da conta é a fonte correta.
3. Após a confirmação da ativação produtiva, adicionar ao cofre e ao `.env` do
   Commerce V2:

   ```dotenv
   PAGARME_GOOGLE_PAY_GATEWAY_MERCHANT_ID=<identificador produtivo confirmado pela Pagar.me/Stone>
   ```

   Quando o checkout selecionar Pagar.me, o código envia `gateway=pagarme` e
   usa essa linha como `gatewayMerchantId`.

#### 4. Apple Pay — Merchant ID, domínio, certificado e chave

1. Abrir [Apple Developer — Certificates, Identifiers & Profiles](https://developer.apple.com/account/)
   com usuário **Account Holder** ou **Admin**.
2. No menu lateral, abrir **Identifiers**. No seletor superior direito, escolher
   **Merchant IDs**; criar o Merchant ID definitivo ou abrir o que já existe.
   Copiar o campo **Identifier** e gravar no cofre e no `.env`:

   ```dotenv
   APPLE_PAY_MERCHANT_IDENTIFIER=<Identifier do Merchant ID Apple>
   ```

3. Na página desse Merchant ID, localizar **Merchant Domains**, clicar em
   **Add Domain**, digitar o host do Checkout e salvar. Baixar o arquivo de
   associação oferecido pela Apple, publicá-lo no caminho `.well-known` que a
   própria tela indicar e clicar em **Verify**. Repetir para cada host que
   mostre o botão; o resultado precisa exibir **Verified**.
4. Na mesma página, localizar **Apple Pay Merchant Identity Certificate** e
   clicar em **Create Certificate**. Enviar o CSR solicitado e baixar o
   certificado gerado. Exportar o certificado e sua chave correspondente em
   PEM separado, usando o procedimento seguro aprovado pela infraestrutura.
5. Montar esses dois arquivos em volume privado do container Commerce V2. Após
   definir os caminhos internos reais, gravar no `.env`:

   ```dotenv
   APPLE_PAY_MERCHANT_CERTIFICATE_PATH=/caminho/interno/merchant-identity.pem
   APPLE_PAY_MERCHANT_PRIVATE_KEY_PATH=/caminho/interno/merchant-identity-key.pem
   ```

   Esses dois caminhos são usados na validação mTLS da sessão Apple Pay.
6. Na área **Payment Processing Certificate** do mesmo Merchant ID, criar ou
   manter o certificado de processamento acordado com o PSP. Esse certificado
   atende ao processamento do token; a identidade de merchant criada no passo
   anterior atende à validação da sessão web.

#### 5. Conferência segura antes de liberar sellers

Após a injeção, recriar o Commerce V2 conforme a seção **Sequência de deploy**
e executar, dentro dele, a verificação abaixo. Ela confere os caminhos Apple e
o modo Google sem exibir IDs, certificados, chaves ou tokens:

```bash
cd /opt/lowify/services/service-commerce-v2
docker compose exec -T service-commerce-v2 sh -lc '\
  test -r "$APPLE_PAY_MERCHANT_CERTIFICATE_PATH" && \
  test -r "$APPLE_PAY_MERCHANT_PRIVATE_KEY_PATH" && \
  test "$GOOGLE_PAY_TEST_MODE" = false'
```

O comando retorna zero sem exibir IDs, certificados, chaves ou tokens. Se
falhar, corrigir o segredo, o volume ou a permissão antes de disponibilizar
Apple Pay/Google Pay para qualquer seller.

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
git switch main
git pull --ff-only origin main
git merge-base --is-ancestor f6d4ed23c2cad24ac6a22a703b3bdea53a81f2f9 HEAD
git merge-base --is-ancestor 7a19ec0a9763ac3fbdbd0cff47614348ba6964d5 HEAD
git merge-base --is-ancestor 3c878afa7eb7baac931a904cf182aa6dff0e9564 HEAD
git rev-parse --short HEAD
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 services-banking-v2
```

Prosseguir somente se os três `git merge-base` retornarem zero, o SHA de
`main` for o aprovado, o serviço estiver `Up` e não houver erro de schema,
conexão ou processo nos logs.

### 3. Atualizar Commerce V2

```bash
cd /opt/lowify/services/service-commerce-v2
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

Prosseguir somente se o SHA de `main` for o aprovado,
`service-commerce-v2` estiver `Up` e os logs não
apontarem erro de schema, configuração de certificado, conexão ou processo.

### 4. Atualizar Edge Gateway

```bash
cd /opt/lowify/edge/edge-gateway
git switch main
git pull --ff-only origin main
git merge-base --is-ancestor 8ba4b321f7f9d9fd0dd33c5c27e88da2fea8e689 HEAD
git rev-parse --short HEAD
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 edge-gateway edge-gateway-worker
```

Prosseguir somente se `git merge-base` retornar zero, o SHA de `main` for o
aprovado e os dois processos estiverem `Up` sem erro de rota,
autenticação ou processo nos logs.

### 5. Atualizar Edge Public API

```bash
cd /opt/lowify/edge/edge-public-api
git switch main
git pull --ff-only origin main
git merge-base --is-ancestor 420deac2130f6c339fc4c74497850c35016c6e2b HEAD
git rev-parse --short HEAD
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 edge-public-api
```

Prosseguir somente se `git merge-base` retornar zero, o SHA de `main` for o
aprovado e o processo estiver `Up` sem erro de rota ou JWT nos
logs.

### 6. Atualizar Front Checkout

```bash
cd /opt/lowify/front/front-checkout
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD
docker compose ps
```

Prosseguir somente se o SHA de `main` for o aprovado e todos os serviços que
já estavam ativos continuarem `Up`. Não reiniciar container só por esta
atualização de código montado.

### 7. Atualizar Dashboard Seller

```bash
cd /opt/lowify/front/dashboard-seller
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD
docker compose ps
```

Prosseguir somente se o SHA de `main` for o aprovado e os serviços existentes
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
   para o ambiente. Para Google em produção, executar somente depois de a
   aprovação do domínio constar no Console; registrar apenas IDs técnicos,
   horário, valores e estado.
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
- [Google Pay — publicar uma integração web](https://developers.google.com/pay/api/web/guides/test-and-deploy/publish-your-integration)
- [Google Pay — checklist de integração](https://developers.google.com/pay/api/web/guides/test-and-deploy/integration-checklist)
- [Cielo — Google Pay e dados produtivos](https://docs.cielo.com.br/gateway/docs/google-pay)
- [Pagar.me — guia Google Pay](https://docs.pagar.me/docs/google-pay-tm-guide)
- [Apple — configurar Apple Pay na web](https://developer.apple.com/help/account/capabilities/configure-apple-pay-on-the-web)
