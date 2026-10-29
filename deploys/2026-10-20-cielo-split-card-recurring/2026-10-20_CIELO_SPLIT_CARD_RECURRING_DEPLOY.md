# Deploy — assinaturas por cartão Cielo Split

## Objetivo

Disponibilizar de forma controlada o cartão recorrente da Cielo Split para produtos `SUBSCRIPTION`. A Cielo cria a série e cobra cada ciclo; a Lowify persiste o `RecurrentPaymentId`, consulta cada `PaymentId`, aplica o Split pós-transacional e processa a parcela no Commerce V2 por uma fila exclusiva e idempotente.

Este deploy publica a capacidade técnica, mas **não libera cartão recorrente globalmente**. A criação de novas séries continua bloqueada até que a Recorrência Programada esteja habilitada no EC Master e o callback real tenha sido exercitado. Depois disso, a liberação é explícita e individual por seller, por `user_system_vars.cielo_recurring_card_enabled=1`.

## Componentes e referências

Os commits abaixo foram registrados no ambiente de desenvolvimento em 20/10/2026. Antes da publicação, confirmar que cada hash está no remoto e registrar o `git rev-parse --short HEAD` efetivamente publicado.

| Repositório | Diretório na VPS | Branch de deploy | Commit observado | Entrega |
| --- | --- | --- | --- | --- |
| `services-banking-v2` | `/opt/lowify/services/services-banking-v2` | `feat/cielo-split-card-recurring` | `e97093b` | Criação/cancelamento/reconciliação da série Cielo, consulta por `PaymentId`, Split pós-transacional, persistência de estado e publicação da ação exclusiva. |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/cielo-split-card-recurring` | `8656388` | Elegibilidade de cartão recorrente, validação de `1x`, consumidor confiável da fila Cielo, eventos duráveis e efeitos idempotentes da venda. |
| `edge-webhook` | `/opt/lowify/edge/edge-webhook` | `feat/cielo-split-card-recurring` | `d55f2d7` | Aceita `ChangeType: 2`, preserva `PaymentId`/`RecurrentPaymentId` e encaminha o evento ao Banking. |
| `services-account` | `/opt/lowify/services/services-account` | `feat/cielo-split-card-recurring` | `d7349e2` | Deduplicação de notificações por chave de idempotência. |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `feat/cielo-split-card-recurring` | `9dc92a5` | Controle triestado por seller e configuração de produto de assinatura com cartão somente em `1x`. |

No corte inicial de recorrência, `edge-gateway` e `edge-public-api` não recebiam mudanças. O complemento de suporte operacional descrito abaixo passa a exigir a publicação compatível desses dois componentes antes do Dashboard.

## Alterações incluídas

1. `SUBSCRIPTION` pode usar cartão apenas quando o seller estiver explicitamente liberado, a integração for `cielo_ecommerce` elegível e o número de parcelas for exatamente `1`.
2. O Banking V2 cria a recorrência Cielo, salva o `RecurrentPaymentId` em `subscriptions.correlation_id` e trata cada `PaymentId` como uma parcela idempotente.
3. O webhook Cielo `ChangeType: 2` e a reconciliação por `RecurrentPaymentId` chegam ao mesmo fluxo de consulta, Split pós-transacional e confirmação.
4. O Banking publica somente em `commerce:cielo:subscriptions:actions`; o processo exclusivo do Commerce V2 não consome `sales:subscriptions:actions` nem filas legadas.
5. O Commerce persiste evento e etapas da venda recorrente, recupera trabalho interrompido e evita repetir venda, entrega, saldo, comissão, push e notificação.
6. Cancelamento atua sobre a série (`RecurrentPaymentId`); refund continua sendo operação de uma cobrança (`PaymentId`). Desligar a flag do seller impede novas adesões, sem cancelar séries existentes.

## Configuração no portal Cielo

Esta feature não cria credencial nova nem exige env nova da Cielo. Ela reutiliza as credenciais de API E-commerce, OAuth do Split e webhook já usadas pelo cartão Cielo em produção.

1. No Site Cielo, selecionar o EC Master, abrir **E-commerce → Gestão API E-commerce → Microsserviços**, localizar **Recorrência Programada**, ativar a chave, aceitar o termo e concluir a autenticação pelo Cielo Gestão. Se a opção não estiver disponível, solicitar sua habilitação ao Atendimento E-commerce Cielo.
2. Após a ativação, abrir a engrenagem de **Recorrência Programada** e definir a política operacional de retentativas: quantidade, intervalo entre tentativas e se a série será desativada ao esgotá-las. Registrar a política definida na evidência do deploy.
3. Manter o Post de Notificação já configurado para o EC apontando ao endpoint produtivo atual do `edge-webhook`. Não há URL, segredo ou credencial adicional a cadastrar para recorrência; o mesmo callback deve ser homologado recebendo uma cobrança recorrente com `ChangeType: 2`.
4. Manter a contratação/habilitação atual do Split no Master e nos sellers. Para cada `PaymentId` recorrente pago, o Banking usa o OAuth Split já existente para chamar a divisão pós-transacional.

Não habilitar Cartão Protegido, 3DS ou gerar novas credenciais apenas por causa desta feature. A primeira cobrança continua no fluxo de cartão atual, que informa o dado de segurança exigido pela Cielo; as cobranças seguintes são geradas pela Recorrência Programada.

## Pré-requisitos

1. Executar a configuração do portal Cielo acima. Um retorno `313` na criação indica que a Recorrência Programada ainda não foi habilitada.
2. Homologar com credenciais reais da Cielo uma série completa: criação, primeira cobrança, próxima cobrança, callback `ChangeType: 2`, consulta, Split, venda, entrega, cancelamento e refund de uma parcela. O teste local de 20/10 usou mock e reconciliação; ele não substitui o callback real.
3. Confirmar que os cinco diretórios da tabela estão limpos e que suas branches e commits aprovados já foram enviados ao remoto. Se `git status --porcelain=v1` retornar linhas, parar antes de `git switch`.
4. Confirmar MariaDB e Redis saudáveis. Não limpar, consumir manualmente, mover ou reprocessar mensagens Redis durante o deploy.
5. Preservar os segredos já existentes, sem registrar valores no runbook: `CIELO_ECOMMERCE_MERCHANT_ID`, `CIELO_ECOMMERCE_MERCHANT_KEY`, `CIELO_ECOMMERCE_SPLIT_MERCHANT_ID`, `CIELO_ECOMMERCE_SPLIT_CLIENT_SECRET` e `CIELO_ECOMMERCE_WEBHOOK_SECRET`.
6. Antes de subir o Commerce V2, definir ou preservar `CIELO_SUBSCRIPTION_ACTIONS_PROCESS_ENABLED=false`. A fila é `commerce:cielo:subscriptions:actions` por padrão e pode ser explicitamente fixada por `CIELO_SUBSCRIPTION_ACTIONS_QUEUE` nos dois serviços.
7. Não cadastrar `CIELO_ECOMMERCE_ENDPOINT_API`, `CIELO_ECOMMERCE_ENDPOINT_QUERY` ou `CIELO_ECOMMERCE_VERIFY_SSL` para produção sem necessidade operacional aprovada. Os defaults de produção são os endpoints oficiais e SSL habilitado.

## Banco de dados

Aplicar migrations antes de ativar seller ou consumidor. Elas são aditivas; não executar `down`, não apagar tabelas e não marcar migration manualmente como aplicada.

| Serviço | Migrations esperadas | Efeito |
| --- | --- | --- |
| Banking V2 | `20261019190000_add_metadata_to_subscriptions.php`, `20261019193000_add_cielo_split_state_to_subscription_charges.php` | Preserva metadados da série e o estado/evidência sanitizada do Split por parcela. |
| Commerce V2 | `20261019194500_create_cielo_recurring_sale_events.php`, `20261019201500_create_cielo_recurring_sale_event_steps.php` | Cria evento durável por venda e suas etapas idempotentes/reprocessáveis. |

Após cada migration, executar `migrate:status` e confirmar as quatro entradas. Se uma migration falhar, não habilitar flag, processo ou seller; registrar o nome e corrigir o schema antes de seguir.

## Sequência de deploy

O modo é rebuild obrigatório para todos os serviços empacotados. Em cada bloco, `git rev-parse --short HEAD` deve resultar no commit aprovado ou em uma revisão posterior expressamente aprovada. Os comandos não descartam alterações locais.

### 1. Publicar `services-account`

```bash
cd /opt/lowify/services/services-account
git status --porcelain=v1
git fetch origin --prune
git switch feat/cielo-split-card-recurring
git pull --ff-only origin feat/cielo-split-card-recurring
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100
```

### 2. Publicar `services-banking-v2` e aplicar suas migrations

O Banking deve estar disponível antes do webhook e antes de qualquer produtor de cobrança/ação Cielo.

```bash
cd /opt/lowify/services/services-banking-v2
git status --porcelain=v1
git fetch origin --prune
git switch feat/cielo-split-card-recurring
git pull --ff-only origin feat/cielo-split-card-recurring
git rev-parse --short HEAD
docker compose up -d --build
docker compose exec -T services-banking-v2 php bin/hyperf.php migrate --force
docker compose exec -T services-banking-v2 php bin/hyperf.php migrate:status
docker compose ps
docker compose logs --tail=100 services-banking-v2
```

Confirmar que o processo `cielo_recurring_reconciliation` iniciou sem erro. Ele reconcilia apenas assinaturas Cielo já persistidas; não habilita cartão para nenhum seller.

### 3. Publicar `services-commerce-v2` com o consumidor desligado

```bash
cd /opt/lowify/services/service-commerce-v2
git status --porcelain=v1
git fetch origin --prune
git switch feat/cielo-split-card-recurring
git pull --ff-only origin feat/cielo-split-card-recurring
git rev-parse --short HEAD
docker compose up -d --build
docker compose exec -T service-commerce-v2 php bin/hyperf.php migrate --force
docker compose exec -T service-commerce-v2 php bin/hyperf.php migrate:status
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

Manter `CIELO_SUBSCRIPTION_ACTIONS_PROCESS_ENABLED=false` nesta etapa. O processo só pode ser habilitado depois da homologação de ponta a ponta e imediatamente antes da liberação do seller piloto.

### 4. Publicar `edge-webhook`

```bash
cd /opt/lowify/edge/edge-webhook
git status --porcelain=v1
git fetch origin --prune
git switch feat/cielo-split-card-recurring
git pull --ff-only origin feat/cielo-split-card-recurring
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 edge-webhook
```

Confirmar que a autenticação existente do webhook Cielo continua ativa. O payload e os logs não podem expor PAN, CVV, tokens, segredo ou Bearer token.

### 5. Atualizar `dashboard-seller`

```bash
cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git fetch origin --prune
git switch feat/cielo-split-card-recurring
git pull --ff-only origin feat/cielo-split-card-recurring
git rev-parse --short HEAD
```

Não liberar o cartão no Dashboard neste ponto. A ausência da linha em `user_system_vars` é o estado padrão negado.

### 6. Homologar e liberar um seller piloto

1. Confirmar novamente que o processo Commerce está desligado e que nenhum seller possui `cielo_recurring_card_enabled=1`.
2. Com a Cielo homologada, ajustar `CIELO_SUBSCRIPTION_ACTIONS_PROCESS_ENABLED=true` no ambiente do Commerce V2 e executar `docker compose up -d --build`; confirmar o processo `commerce_cielo_subscription_actions_queue` ativo.
3. No Dashboard, para somente um seller de teste, selecionar **Liberado** em `cielo_recurring_card_enabled`. Não criar a chave por SQL e não habilitar a opção globalmente.
4. Configurar um produto `SUBSCRIPTION` Cielo em `1x`, realizar a compra de teste e conciliar antes de liberar outro seller.

## Validação pós-deploy

1. Confirmar no `migrate:status` as duas migrations do Banking V2 e as duas do Commerce V2; validar também que os containers e processos nomeados acima permanecem saudáveis.
2. No Dashboard, verificar o seletor triestado: `Não configurado` remove a linha, `Bloqueado` grava `0` e `Liberado` grava `1`. Para `null` ou `0`, cartão não pode aparecer nem ser aceito por request adulterado.
3. Para um seller liberado e integração Cielo aprovada, criar/editar `SUBSCRIPTION` com cartão e confirmar que o parcelamento fica fixo em `1x`. `ONE_TIME` deve manter cartão e parcelamento atuais, sem regressão.
4. Fazer uma compra de teste: deve haver uma única série com `RecurrentPaymentId`, uma venda inicial pendente e nenhuma persistência/log de dados sensíveis.
5. Confirmar a primeira cobrança por callback real `ChangeType: 2`; o webhook deve encaminhar ao Banking, que consulta o `PaymentId`, aplica um único Split pós-transacional e publica uma única ação na fila exclusiva.
6. Confirmar no Commerce que a venda inicial fica paga uma única vez e que os efeitos de acesso, entrega, financeiro, comissão e notificação não duplicam ao reenviar o callback ou executar nova consulta.
7. Homologar uma cobrança futura: deve gerar parcela `2`, novo `PaymentId`, Split único e venda recorrente paga ligada à mesma série. Testar também webhook perdido pela reconciliação por `RecurrentPaymentId`.
8. Cancelar a série e confirmar que futuras cobranças são interrompidas, preservando histórico e parcelas já criadas. Reembolsar uma parcela por `PaymentId` sem presumir cancelamento da série.
9. Provocar uma falha transitória controlada do Split. A parcela deve permanecer observável/recuperável, sem liberar repasse duplicado; conferir retry e, se esgotado, a fila `commerce:cielo:subscriptions:actions:dlq`.

## Observabilidade operacional

- Acompanhar séries criadas, callbacks recebidos, consultas falhas, parcelas confirmadas, Split pendente/falho, retries e DLQ.
- Investigar qualquer série ativa sem evento dentro da janela prevista e qualquer `PaymentId` pago sem Split confirmado.
- Usar `RecurrentPaymentId`, `PaymentId`, `subscription_id`, `sale_id`, número da parcela e `event_id` como chaves de investigação. Nunca usar ou registrar dados de cartão, CVV, tokens ou segredos.
- Antes de ampliar a liberação, conciliar valor pago, Split e saldo/repasse do seller para cada cobrança do piloto.

## Complemento — suporte aos erros de integração

Foi adicionada ao painel administrativo do Checkout Transparente uma consulta de erros de integração por seller. Ela é destinada ao suporte investigar falhas reportadas pelo vendedor, sem exigir acesso direto ao banco ou aos logs dos serviços.

1. A página administrativa exibe inicialmente os 20 erros mais recentes e oferece **Carregar mais** para consultar o histórico progressivamente.
2. Cada linha identifica a integração, a origem, o momento e um resumo legível. O detalhe abre os dados técnicos sanitizados do registro.
3. Dashboard, `edge-public-api` e `edge-gateway` fazem a consulta autenticada até a API do Checkout Transparente; a API mantém o escopo do seller e da integração.
4. PAN, CVV, token, segredo e credenciais não podem ser apresentados; os dados exibidos usam a sanitização já aplicada ao log de integração.

Para publicar esse complemento, subir primeiro `edge-public-api` e `edge-gateway`, e depois `dashboard-seller`. Não depende de habilitar cartão recorrente, nem altera o fluxo financeiro ou as filas da Cielo.

## Rollback

1. Primeiro remover a liberação do seller piloto no Dashboard, escolhendo `Não configurado` ou `Bloqueado`. Isso pausa novas adesões sem cancelar séries já existentes.
2. Manter Banking V2, Commerce V2, webhook e o consumidor Cielo na revisão compatível enquanto houver `PaymentId`, Split, evento durável, retry ou mensagem pendente. O Commerce V2 é o último componente interno que pode ser revertido, após concluir ou isolar todas as ações.
3. Se necessário, desligar `CIELO_SUBSCRIPTION_ACTIONS_PROCESS_ENABLED` e reconstruir somente o Commerce V2; preservar a fila, DLQ e eventos para análise e recuperação.
4. Depois de drenar/registrar as pendências, retornar o código na ordem inversa: `dashboard-seller`, `edge-webhook`, `services-commerce-v2`, `services-banking-v2`, `services-account`.
5. Não executar `down`, não apagar migrations, assinaturas, parcelas, `RecurrentPaymentId`, `PaymentId`, estado/evidência de Split, vendas, eventos, steps, logs, mensagens ou DLQ. Nenhuma compensação financeira automática faz parte do rollback.
6. Antes de qualquer nova liberação, reconciliar cada série e cobrança pendente com a Cielo e registrar a causa da reversão.

## Referências

- `plans/cielo-split-card-recurring/README.md`
- `plans/cielo-split-card-recurring/01_ESTADO_ATUAL_E_FRONTEIRAS.md`
- `plans/cielo-split-card-recurring/02_CONTRATO_DADOS_E_EVENTOS.md`
- `plans/cielo-split-card-recurring/03_IMPLEMENTACAO_ROLLOUT_E_ACEITE.md`
- `plans/cielo-split-card-recurring/04_DASHBOARD_E_TRAVAS_DE_CONFIGURACAO.md`
- `services/services-banking-v2/config/autoload/cielo_recurring.php`
- `services/service-commerce-v2/config/autoload/cielo_subscription_actions.php`
- [Cielo — gerenciar microsserviços](https://docs.cielo.com.br/ecommerce-cielo/docs/como-habilitar-microsservi%C3%A7os)
- [Cielo — Recorrência Programada](https://docs.cielo.com.br/ecommerce-cielo/docs/recorr%C3%AAncia-programada-cielo)
- [Cielo — divisão após a autorização](https://docs.cielo.com.br/split/reference/split-autorizado)
