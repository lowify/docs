# Deploy — CPF opcional para Pix Pagar.me

## Objetivo

Permitir a criação de vendas Pix avulsas sem CPF quando o produto não o exige explicitamente. A mudança se aplica ao Pix Pagar.me PSP do checkout padrão e ao Pix Pagar.me do Checkout Transparente (CT).

Quando o CPF não vier no fluxo Pagar.me, o Banking V2 ou o worker do CT fornece um CPF válido antes de enviar a cobrança ao gateway. A configuração explícita do produto (`checkout_campo_cpf`) continua exigindo CPF. Pix Automático não faz parte desta entrega.

## Componentes e referências

| Repositório | Host | Diretório de produção | Branch de deploy | Commit obrigatório | Alteração |
| --- | --- | --- | --- | --- | --- |
| `services-banking-v2` | `144.126.149.57` | `/opt/lowify/services/services-banking-v2` | `feat/optional-cpf-pagarme-pix` | `29cdb32` | Fallback de CPF no adaptador de Pix Pagar.me PSP. |
| `services-commerce-v2` | `144.126.149.57` | `/opt/lowify/services/service-commerce-v2` | `feat/optional-cpf-pagarme-pix` | `d149dda` | Contexto do Pix deixa de exigir documento por provider e a validação respeita somente o flag explícito do produto. |
| `services-checkout-transparent-worker` | `80.190.72.241` | `/opt/lowify-ct/services/services-checkout-transparent-worker` | `feat/optional-cpf-pagarme-pix` | `2a8dbc8` | Fallback de CPF antes de criar pedido Pix Pagar.me no CT. |
| `services-checkout-transparent-api` | `80.190.72.228` | `/opt/lowify-ct/services/services-checkout-transparent-api` | `feat/optional-cpf-pagarme-pix` | `a4c4767` | Pagar.me deixa de anunciar `document` como campo obrigatório no contexto do CT. |

Os commits acima partem de `main`. As branches devem ser enviadas ao `origin` antes deste deploy; este roteiro não autoriza `push` no servidor.

## Alterações incluídas

- No checkout padrão, `checkout_options.pix.requires_customer_document` passa a ser `false`; o front já interpreta esse contrato e não força o campo CPF por provider.
- O Commerce V2 continua obrigando CPF somente quando o produto tiver `checkout_campo_cpf = 1`.
- O Banking V2 normaliza o documento do comprador e usa `DocumentGenerator::cpf()` apenas se ele estiver vazio antes de chamar Pagar.me PSP.
- No CT, a lista genérica de campos obrigatórios é preservada, mas Pagar.me não inclui mais `document` nela.
- O CT API publica a instrução sem documento quando ele não foi informado; o worker Pagar.me aplica `DocumentGenerator::cpf()` antes do `POST /orders` ao gateway.
- Não há alteração de rota, JWT, schema de banco, migration, variável de ambiente, credencial, nem nome de fila. O CT continua usando `checkout-transparent:gateway:instructions` com a ação `payment.create`.

## Pré-requisitos

1. Confirmar que cada repositório de produção está limpo (`git status --porcelain=v1` sem saída) e que `origin` aponta ao remoto esperado.
2. Confirmar que as quatro branches e commits da tabela estão disponíveis no remoto.
3. Preservar as credenciais Pagar.me existentes; este deploy não altera chaves, endpoint ou integração cadastrada.
4. Escolher um produto de teste Pix avulso com `checkout_campo_cpf` desligado e uma integração Pagar.me ativa para cada fluxo a validar.

## Banco de dados

Não há migration, DDL, DML nem alteração de dados a aplicar.

## Sequência de deploy

Modo de rebuild: incremental. Execute as etapas na ordem dos hosts abaixo e não retorne a um host já concluído. Antes de cada etapa, interrompa a operação se o repositório estiver sujo, se a branch remota não existir ou se o commit final não corresponder à tabela.

### Host `144.126.149.57`

1. Publicar o `services-banking-v2` primeiro. Isso garante o fallback antes de o Commerce aceitar venda padrão sem CPF.

   ```bash
   cd /opt/lowify/services/services-banking-v2
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/optional-cpf-pagarme-pix
   git pull --ff-only origin feat/optional-cpf-pagarme-pix
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   ```

2. Ainda no mesmo host, publicar o `services-commerce-v2`. A partir deste ponto o checkout padrão deixa de exigir CPF por ser Pagar.me PSP.

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/optional-cpf-pagarme-pix
   git pull --ff-only origin feat/optional-cpf-pagarme-pix
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   ```

### Host `80.190.72.241`

3. Publicar o `services-checkout-transparent-worker` antes de remover a exigência de documento no CT API.

   ```bash
   cd /opt/lowify-ct/services/services-checkout-transparent-worker
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/optional-cpf-pagarme-pix
   git pull --ff-only origin feat/optional-cpf-pagarme-pix
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   ```

### Host `80.190.72.228`

4. Publicar o `services-checkout-transparent-api` por último. A partir deste ponto Pagar.me deixa de anunciar `document` como obrigatório no CT.

   ```bash
   cd /opt/lowify-ct/services/services-checkout-transparent-api
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/optional-cpf-pagarme-pix
   git pull --ff-only origin feat/optional-cpf-pagarme-pix
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   ```

5. Compare cada `git rev-parse --short HEAD` com a tabela. Não há mudança a publicar em `front-checkout` nem em `edge-public-api` neste corte.

## Validação pós-deploy

1. Abra um checkout Pix padrão de produto de teste com coleta de CPF desligada e seller configurado para Pagar.me PSP. Confirme que o campo CPF não aparece. Preencha nome, e-mail e telefone, gere o Pix e confirme que o QR Code/copia e cola aparece sem erro.
2. Abra um checkout CT com integração Pagar.me e o mesmo tipo de produto. Confirme que o campo CPF não aparece, gere o Pix e confirme que o QR Code/copia e cola aparece.
3. Em ambos os fluxos, abra um produto com coleta explícita de CPF ligada. Confirme que o campo ainda aparece e que não é possível concluir sem CPF válido.
4. Confirme uma cobrança Pix de teste por fluxo. A venda deve avançar pelo fluxo normal de confirmação e entrega, sem duplicação.
5. Como conferência técnica opcional, verifique logs recentes do Banking V2 e do worker CT para confirmar ausência de falha de documento. Não reproduza, apague ou consuma manualmente mensagens da fila.

## Rollback

1. Não apagar vendas, clientes, cobranças, mensagens da fila ou integrações Pagar.me criadas durante a validação.
2. Retornar primeiro o Commerce V2 para a referência `main` previamente aprovada e reconstruir o container; isso volta a impedir CPF ausente quando o fluxo padrão Pagar.me for selecionado.
3. Retornar o CT API para a referência `main` previamente aprovada e reconstruir o container; Pagar.me volta a anunciar `document` como obrigatório no contexto CT.
4. Depois de registrar ou concluir cobranças CT pendentes, retornar o worker CT e o Banking V2 para a referência `main` previamente aprovada, reconstruindo cada container.
5. Repetir uma compra Pix de teste com CPF informado antes de reabrir o fluxo ao público.

## Referências

- `services-commerce-v2/app/Http/Controller/ProductController.php`
- `services-commerce-v2/app/Http/Request/ProcessProductCheckoutRequest.php`
- `services-banking-v2/app/Application/UseCase/PagarmePsp/ChargePix/CreateChargePixUseCase.php`
- `services-banking-v2/app/Shared/Support/DocumentGenerator.php`
- `services-checkout-transparent-api/app/Application/UseCase/Checkout/ResolveCheckoutAvailabilityUseCase.php`
- `services-checkout-transparent-worker/app/Infrastructure/Gateways/PagarMe/Client/PagarMePaymentClient.php`
