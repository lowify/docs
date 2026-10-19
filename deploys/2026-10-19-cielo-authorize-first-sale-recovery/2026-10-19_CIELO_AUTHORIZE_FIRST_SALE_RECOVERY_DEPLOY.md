# Deploy — Autorização Cielo antes do antifraude e recuperação de vendas

## Objetivo

Publicar duas correções no checkout e na recuperação de vendas:

1. Nas vendas por cartão Cielo com Cybersource, autorizar antes da análise de fraude e deixar a Cielo capturar automaticamente somente quando o risco for baixo, ou cancelar a autorização quando o risco for alto.
2. Não reservar crédito de comunicação para recuperação de venda pendente que não possui código Pix válido.

O escopo não cria rotas, migrations, variáveis de ambiente, bancos ou filas. O comprador pode ver a compra de cartão permanecer pendente enquanto a Cielo conclui a análise manual; a venda só é liberada quando o fluxo já existente receber o status `Paid`.

## Componentes e referências

| Repositório | Diretório em produção | Branch de deploy | Entrega |
| --- | --- | --- | --- |
| `services-banking-v2` | `/opt/lowify/services/services-banking-v2` | `fix/cielo-authorize-first` | Envia `Capture: false` para o fluxo Cielo gerenciado pelo antifraude e valida os flags de captura/void. |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `fix/cielo-authorize-first` | Envia a nova política de antifraude e inclui a correção de recuperação sem código Pix. |

`bb2bfa3` inclui a `main` do Commerce V2 até `3a4a259`, incluindo o commit `a4c1bc77e2518377632444803ca5b76afd582f59` (`fix(recovery): skip sales without PIX`). Não publicar `main` diretamente nesta entrega: a referência de deploy do Commerce é a branch acima.

## Alterações incluídas

### Cartão Cielo com Cybersource

- O Commerce V2 passa a enviar `Sequence: AuthorizeFirst`, `SequenceCriteria: OnSuccess`, `CaptureOnLowRisk: true` e `VoidOnHighRisk: true`.
- Quando recebe essa combinação, o Banking V2 envia `Payment.Capture: false` à Cielo. A Cielo captura a autorização em caso de baixo risco (`Accept`) e faz void em caso de alto risco (`Reject`). Em revisão (`Review`), a autorização permanece pendente até a decisão manual da Cielo.
- O Banking V2 recusa flags de captura/void fora de `AuthorizeFirst` ou com tipo diferente de booleano. Pagamentos Cielo sem essa política preservam a captura automática atual.
- O webhook transacional já existente da Cielo (`ChangeType: 1`) consulta a transação e atualiza a cobrança. Somente o status `Paid` libera a venda no Commerce; `Voided` permanece recusado.

### Recuperação de vendas

- Antes de criar ou executar um disparo de recuperação, o Commerce V2 verifica se a venda tem `pix_code` não vazio.
- Se não houver código Pix, o dispatch é registrado como ignorado (`missing_pix_code`). Caso algum crédito já esteja reservado, ele é liberado; não há envio de WhatsApp ou e-mail para uma cobrança sem código de pagamento.

## Sequência de deploy

Modo de rebuild: incremental. Publicar primeiro o Banking V2, que aceita e transforma o novo contrato, e depois o Commerce V2, que passa a produzi-lo.

### 1. Publicar `services-banking-v2`

```bash
cd /opt/lowify/services/services-banking-v2
git status --porcelain=v1
git fetch origin --prune
git switch fix/cielo-authorize-first
git pull --ff-only origin fix/cielo-authorize-first
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100
```

Confirmar que o container permanece em execução antes de seguir.

### 2. Publicar `services-commerce-v2`

```bash
cd /opt/lowify/services/service-commerce-v2
git status --porcelain=v1
git fetch origin --prune
git switch fix/cielo-authorize-first
git pull --ff-only origin fix/cielo-authorize-first
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100
```

Confirmar que o container permanece em execução. Não executar migration: esta entrega não possui alteração de banco.

## Validação pós-deploy

### Compra por cartão Cielo

1. Abra um checkout de teste com Cielo e compre com um cartão de teste autorizado para o antifraude.
2. Confirme que, quando a análise retornar baixo risco, a compra é concluída normalmente e o comprador vê a confirmação de pagamento.
3. Em um cenário Cielo controlado de alto risco, confirme que a compra não é aprovada nem libera o produto. Não repetir tentativas reais em produção para forçar rejeição.
4. Se houver uma transação em revisão, informe ao gestor que ela pode aparecer temporariamente como pendente. Após a decisão da Cielo, confirme que uma aprovação libera a compra e uma recusa não a libera.
5. Como conferência técnica opcional, verifique que o webhook Cielo foi recebido e que a cobrança evoluiu para `Paid` ou `Voided`; não é necessário interpretar payloads pelo gestor.

### Recuperação de venda Pix

1. No painel administrativo, localize uma venda pendente sem código Pix e com recuperação de vendas configurada.
2. Confirme que nenhum disparo de recuperação é enviado para o comprador e que não há consumo de crédito de comunicação.
3. Em seguida, use uma venda pendente equivalente com código Pix válido e confirme que o comportamento normal de recuperação continua disponível conforme a configuração do produto.

Se qualquer validação falhar, interromper novas campanhas ou cobranças de teste e executar o rollback abaixo antes de investigar.

## Rollback

1. Retornar primeiro o Commerce V2 para `main`, atualizar a branch e reconstruir o container:

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git status --porcelain=v1
   git fetch origin --prune
   git switch main
   git pull --ff-only origin main
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=100
   ```

   Esse rollback remove a mudança do cartão Cielo e preserva a regra de `skip` sem Pix, pois ela já está em `main` do Commerce V2.

2. Retornar o Banking V2 para `main`, atualizar a branch e reconstruir o container:

   ```bash
   cd /opt/lowify/services/services-banking-v2
   git status --porcelain=v1
   git fetch origin --prune
   git switch main
   git pull --ff-only origin main
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=100
   ```

3. Não apagar cobranças, vendas, eventos, dispatches, créditos ou mensagens de fila criados durante a versão nova. O rollback só restaura o código; os registros persistidos devem ser avaliados caso a caso.
4. Depois do rollback, validar uma venda Cielo de teste e uma venda Pix com código válido antes de reabrir campanhas de recuperação.

## Referências

- `services-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ExecuteSaleRecoveryDispatchUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPendingSaleEventSaleRecoveryUseCase.php`
- `services-banking-v2/app/Infrastructure/Gateways/CieloEcommerce/Client/CieloEcommerceChargeCardClient.php`
- `services-banking-v2/app/Http/Request/ChargeCard/CreateChargeCardFormRequest.php`
- [Cielo — análise de fraude com Cybersource](https://docs.cielo.com.br/split/reference/split-apiecommerce-fraudanalysis-cybersource)
