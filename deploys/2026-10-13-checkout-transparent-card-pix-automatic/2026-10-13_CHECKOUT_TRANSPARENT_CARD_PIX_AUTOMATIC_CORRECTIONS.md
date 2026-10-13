# Checkout Transparente — correções para implementação pelo dev

Data: 2026-10-13. Este é o documento consolidado para encaminhar ao desenvolvedor. Identifica os problemas, onde procurar, a correção sugerida e o teste de aceite. Não registra correções já implementadas nem autoriza deploy.

Base: branches `feat/checkout-transparent-card` e commits da [revisão original](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW.md). O [detalhamento técnico](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW_DETAILS.md) e o [mapa de polling Banking V2](2026-10-13_CHECKOUT_TRANSPARENT_POLLING_BANKING_V2_MAP.md) são evidências complementares; este arquivo reúne as orientações finais do produto.

## Regras confirmadas

- Encaminhar apenas token/envelope e campos permitidos quando dados brutos do cartão não forem necessários ao contrato. Exceções precisam ser explícitas e limitadas ao fluxo que realmente as exige.
- Usar nonce estável por tentativa, sem exigir novos campos temporais neste ajuste. Não armazenar CVV; também não guardar o envelope com CVV como histórico.
- Cancelar assinatura somente por cancelamento explícito. Atraso, falta de pagamento e falha/expiração de parcela não cancelam a assinatura.
- Billing de cartão uma vez, na primeira parcela/confirmação elegível; billing de Pix assinatura no pagamento de cada recorrência.
- Um gateway ativo por seller e por método; métodos diferentes podem usar gateways diferentes.
- Só disponibilizar método após validação/aprovação; mostrar modal seguro enquanto integração não aprovada.
- Centralizar regras comerciais de cartão no Commerce V2. Habilitar RisePay depois de fechar os requisitos técnicos e homologar.
- Se cartão estiver disponível no checkout do seller, a configuração de cartão também deve aparecer em Editar Produto, respeitando elegibilidade do produto e as mesmas regras comerciais.

## C01 — incluir dependências já implementadas no update

**Problema:** o plano original lista sete repositórios, omite `edge-webhook` principal e declara que Commerce V2 não tem código a publicar. A implementação da feature depende de ambos para a confirmação recorrente.

**Evidência:** a rota `/api/checkout-transparent/subscription-paid` **já existe** na branch `feat/checkout-transparent-card` do edge-webhook, commit `74be04f3`. `CommerceWebhookClient::notifySubscriptionPayment`, no CT-API, chama essa rota. `CheckoutTransparentWebhookHandler` encaminha o evento para `sales:subscriptions:actions`. Commerce V2 também tem mudanças na branch (`a4b0015c`).

**Correção sugerida:** completar a matriz/ordem do próximo plano de update com esses repositórios e revisões compatíveis. Não recriar a rota nem alterar a arquitetura dos dois webhooks por causa deste achado. A ausência na `main` não é defeito da branch de entrega; o risco ocorre se esses componentes forem omitidos na atualização. Se já estiverem publicados em outro update, registrar o commit compatível como pré-requisito e verificar a rota/consumidor.

**Aceite:** confirmação real chega de ct-webhook ao CT e deste ao Commerce, criando/confirmando a venda correta. No merge do Commerce, preservar correções mais recentes de valor bruto/taxas da `main`; não substituir `main` por uma branch antiga.

## C02 — enviar somente token/envelope quando o cartão bruto não é necessário

**Problema confirmado:** `front-checkout/views/checkout/form/index.php` monta `FormData(form)` e remove `card_number`, `card_expiry`, `card_cvv` e outros campos apenas em condições limitadas. MP/Pagar.me/Efí podem enviar esses campos junto do token. `process.php` encaminha o payload; a public-api só remove os dados antes do Commerce, tarde demais para evitar passagem pela infraestrutura.

**Correção sugerida:** construir payload por allowlist/contrato de fluxo. Depois da tokenização, remover PAN/CVV/validade brutos em todos os contextos em que não são necessários, não apenas para dois nomes de provider. Encaminhar `payment_token` ou `encrypted_card`, nonce, parcelas e dados de comprador estritamente necessários.

Preservar somente exceções comprovadas do contrato (ex.: fluxo específico de 3DS legado); não retirar seus dados indiscriminadamente nem presumir que qualquer 3DS exige cartão aberto. A exceção deve depender do fluxo validado pelo servidor, não de uma flag arbitrária enviada pelo navegador. Reforçar a filtragem nas fronteiras públicas/internas e não encaminhar CVV ao Commerce.

**Sobre armazenamento:** não foi encontrada gravação explícita de CVV/JWE no caminho CT analisado. RisePay abre em memória e envia ao provedor; tentativas/resultados armazenam campos selecionados. Isso não prova ausência de captura por logs/APM/proxy, ainda não auditados. O problema confirmado aqui é transporte desnecessário de campos brutos, não uma alegação de CVV já persistido.

**Aceite:** conferir requisições no navegador e payloads entre camadas para cada provider/fluxo: somente token/envelope quando suficiente; legado/3DS continuam compatíveis; banco, fila, logs e auditoria sem CVV/PAN bruto.

## C03 — nonce e deduplicação independentes do token/cifra

**Problema confirmado:** `edge-public-api/app/Http/Controllers/ProductController.php::createTransparentCardAttempt` deriva a chave da tentativa de `orderId + paymentToken/encryptedCard`. Novo token ou nova cifra muda a chave mesmo quando é retry da mesma tentativa. O middleware do CT apenas exige o header; a deduplicação efetiva depende do use case/banco.

**Correção sugerida:** gerar nonce criptograficamente aleatório (pelo menos 128 bits) uma vez por tentativa, mantê-lo nos retries e incluir no envelope autenticado quando houver JWE. Propagá-lo por front → public-api → CT como chave de idempotência, usando o escopo seller/cobrança/método existente. Validar correspondência entre nonce externo e interno no JWE e autorização/ownership da cobrança.

Redis pode reservar execução com `SET NX` e guardar apenas estado/referência segura. Persistir o mesmo nonce na tentativa com constraint única e transação/locking já usados pelo CT; retorno concorrente deve reutilizar tentativa/resultado. Nova tentativa após recusa conhecida usa outro nonce; timeout/estado desconhecido não libera nova cobrança. Não deduplicar por PAN/CVV ou conteúdo criptografado.

**Aceite:** dois POSTs simultâneos, nova cifra com mesmo nonce e expiração/perda do Redis não geram segunda cobrança. Mudança de valor/parcelas/escopo sob a mesma identidade é conflito, não outra tentativa. Não exigir `issued_at`/`expires_at` novos neste ajuste.

## C04 — sincronizar credenciais Mercado Pago após refresh

**Problema confirmado no CT-API:**

- `CreateIntegrationUseCase` grava credenciais em `integration_keys` e nas chaves do método Pix.
- `UpsertIntegrationPaymentMethodUseCase::integrationCredentialsForMethod` herda o `access_token` para cartão.
- `ApplyMercadoPagoOAuthTokenRefreshResultUseCase::persistTokens` renova somente `integration_keys`.
- `GetGatewayContextUseCase::execute` lê `integration_payment_method_keys`; `executeByIntegrationId` pode sobrepor o token renovado com a cópia antiga quando recebe o método.

**Correção sugerida para este pacote:** manter o modelo atual de credenciais por método, mas estender `persistTokens` para gravar a versão renovada nas chaves de todos os métodos que utilizam o OAuth dessa mesma integração, na mesma transação da integração. Propagar `access_token` e, onde houver cópia utilizada, `refresh_token`; manter metadados de expiração coerentes. Incluir métodos desabilitados que possam voltar a ser habilitados, sem ativá-los automaticamente.

Usar a criptografia/repositórios existentes. A gravação repetida do mesmo resultado não pode falhar por constraint de hash/duplicar histórico desnecessariamente. Não sobrescrever configuração pública ou credenciais de outra conta/método independente. Aplicar o mesmo princípio aos caminhos de renovação/reconexão que atualizam a mesma credencial compartilhada. Garantir que as leituras resolvam a versão mais recente após commit.

Como evolução futura, pode-se eliminar cópias de OAuth e manter referência à fonte única por integração. Não é necessário fazer essa refatoração maior para fechar este pacote.

**Aceite:** após refresh sintético `A → B`, contextos Pix e cartão devolvem `B`, inclusive `executeByIntegrationId` com método; método desabilitado usa `B` ao voltar; falha na transação não deixa versões parcialmente atualizadas; reentrega do resultado é idempotente. Nenhum token aparece em logs.

## C05 — processo de recuperação com fonte de verdade em banco

**Problema confirmado:** `CreateCheckoutSubscriptionUseCase` salva cadastro antes de publicar e retorna o existente sem republicar. Consumidores usam `BLPOP` e retries em memória; queda após retirada pode perder o trabalho. `EfiBankSubscriptionClient::create` faz várias chamadas sem checkpoints persistidos suficientes para retomada.

**Correção sugerida:** criar um `Process` de recuperação que leia operações incompletas no banco, com estado, próximo retry, lease/reserva transacional e IDs/etapas externas persistidos. Gravar a intenção de execução/publicação junto do cadastro. Redis pode continuar como transporte/acelerador; não deve ser o único registro da pendência.

Persistir resultados/eventos a aplicar de forma durável e permitir retomada de efeitos Commerce/billing após reinício. Onde a fila continuar sendo o único caminho de entrega, adicionar reserva/ACK/reentrega ou assegurar reconstituição idempotente pelo banco. Antes de repetir uma criação cujo resultado ficou desconhecido, consultar/reconciliar a operação externa. Não salvar CVV/JWE para viabilizar retry automático; solicitar entrada novamente quando necessária, sem recriar cegamente pagamento já enviado.

**Aceite:** falha de Redis após cadastro, kill de processo, timeout após sucesso no provider e falha em etapa intermediária não abandonam a operação nem duplicam cobrança/venda/billing. Ver seção 4 do [mapa Banking V2](2026-10-13_CHECKOUT_TRANSPARENT_POLLING_BANKING_V2_MAP.md).

## C06 — cancelamento explícito e transições seguras

**Problema confirmado:** o ct-webhook Efí não fecha o tratamento do evento de cancelamento de recorrência; polling agrupa `EXPIRADA` com `CANCELADA`; `ConfirmCheckoutSubscriptionPaymentUseCase` pode voltar assinatura cancelada a `active`. Resultado tardio de criação de parcela pode também escrever `pending` sobre estado já concluído.

**Onde:** `EfiBankWebhookPaymentResolver` no ct-webhook; `GatewayResultQueueProcess`, `EfiBankSubscriptionSchedulerProcess` e `ConfirmCheckoutSubscriptionPaymentUseCase` no CT-API; handlers de execução de assinatura/parcela no worker.

**Correção sugerida:** separar estado da autorização/assinatura do estado financeiro de cada parcela. Atraso, falha e expiração de parcela não cancelam a assinatura. Normalizar cancelamento somente a partir de evento/ação explícita do contrato; tratar estado desconhecido/rejeitado/tecnicamente expirado sem inferir inadimplência como cancelamento.

Cancelamento explícito bloqueia novos ciclos no scheduler e na execução de instrução já enfileirada, e solicita cancelamento das cobranças ainda abertas. Persistir confirmação/pendência externa. Pagamento atrasado confirma a parcela e seus efeitos financeiros, mas não reativa assinatura cancelada. Proteger estados finais contra reentrega e ordem invertida.

**Aceite:** cancelar antes/depois do agendamento e durante execução; receber pagamento após cancelamento; repetir resultados fora de ordem. Nenhum ciclo novo após cancelamento, nenhum pagamento real perdido, nenhum cancelamento automático por falta de pagamento.

## C07 — polling por conta para recebimentos e autorizações

**Problema confirmado:** a rotina atual escolhe até 100 assinaturas por `updated_at` antes de filtrar Efí; pode repetir o mesmo lote indefinidamente. A primeira parcela Efí é criada em `/v2/cob`, mas consultada como `/v2/cobr`.

**Onde:** `CheckoutSubscriptionRepository::pendingOrActiveForPolling`, `CheckoutSubscriptionChargeRepository::pendingForPolling`, `EfiBankSubscriptionPollingProcess`; worker `EfiBankSubscriptionClient::checkStatus`.

**Correção sugerida:** adaptar o padrão Banking V2 para contas/integrações CT, com três trilhas: recebimentos, autorizações/cancelamentos e recuperação pontual. Para Efí, a listagem de recebimentos `/v2/pix` pode recuperar primeira cobrança e pagamento tardio; correlacionar conta + txid + end-to-end à parcela correta. Consulta pontual inicial usa `/v2/cob/{txid}`; recorrente, `/v2/cobr/{txid}`.

Usar cursor/checkpoint separado por provider/ambiente/conta/tipo; janelas com sobreposição; paginação completa; persistência dos itens antes de avançar; deduplicação compartilhada com webhook; justiça entre contas e limite de trabalho por conta. Continuar reconciliando operações antigas mesmo após desabilitar integração para novas vendas. Verificar a semântica temporal das listas para não perder cancelamento de autorização criada há meses.

**Aceite:** mais de 100 itens por minuto, 250+ registros, contas misturadas, falha/reinício e pagamento antigo recebido hoje: todas as contas avançam, todos os pagamentos conhecidos são aplicados uma vez, cancelamentos explícitos são recuperados. Não copiar cegamente locks, limites e mapeamento genérico de estados do Banking; consultar o [mapa completo](2026-10-13_CHECKOUT_TRANSPARENT_POLLING_BANKING_V2_MAP.md).

## C08 — billing no momento aprovado e aprovação de compra separada da autorização

**Problemas confirmados:** `ConfirmCheckoutSubscriptionPaymentUseCase` não publica o billing equivalente ao caminho avulso. Além disso, `front-checkout/transparent_payment.php` trata assinatura `active` como pagamento confirmado, mas `active` também vem de autorização aprovada sem pagamento.

**Correção sugerida:** manter billing de cartão uma vez na primeira parcela/confirmação elegível, aproveitando `SnapshotChargeFeesUseCase`, `ConfirmChargePaymentUseCase` e `BillingItemsQueueClient`. Acrescentar snapshot/publicação correspondente ao pagamento de cada recorrência Pix, com identidade persistente por assinatura/parcela/tipo de custo. Fechar publicação/reentrega com C05.

Expor no contrato estado da autorização separado de pagamento da parcela inicial. Ajustar front e confirmação Commerce para não apresentar autorização como dinheiro recebido. A ativação da autorização pode permitir agendamento conforme o contrato sem significar compra paga nem cancelamento por ausência de pagamento.

**Aceite:** cartão em 12 parcelas gera um único custo conforme a política; cada recorrência Pix paga gera seu custo uma vez. Autorizar/agendar/consultar/repetir webhook não gera billing. Autorização aprovada com pagamento inicial pendente não aparece como pagamento confirmado. Registrar o tratamento financeiro do pagamento inicial Pix na política de aceite.

## C09 — calendário único e avanço idempotente de vencimento

**Problema confirmado:** primeiro vencimento no worker limita o dia ao mês; vencimentos seguintes em `GatewayResultQueueProcess::nextSubscriptionDueAt` usam `modify('+1 month')`, que pode produzir `31/jan → 03/mar`.

**Correção sugerida:** centralizar política de calendário, persistir dia/data-âncora e calcular cada ciclo a partir dela, não do dia já limitado em fevereiro. Proposta: último dia disponível naquele mês e retorno ao dia-âncora no seguinte. Alinhar fuso, frequência e ajuste de dia útil exigido pelo provider. Resultado repetido não avança o ciclo novamente nem altera parcela já paga.

**Aceite:** dias 28–31, fevereiro normal/bissexto, frequência anual/semestral e reentrega: não pula mês, não deriva o aniversário, não cria duas parcelas para o mesmo ciclo. Exemplo esperado após aprovação da política: `31/jan → 28/fev → 31/mar`.

## C10 — aprovação antes de ativar e apenas um gateway por método

**Problema confirmado:** métodos podem ser habilitados antes da conclusão assíncrona de validações; a unicidade existente é integração/método, não seller/método efetivamente ativo. Limpar `is_default` não impede dois métodos habilitados.

**Onde:** `UpsertIntegrationPaymentMethodUseCase`, `IntegrationPaymentMethodRepository`, disponibilidade do checkout e resultados de configuração no CT; modal de métodos no dashboard.

**Correção sugerida:** distinguir configuração solicitada de disponibilidade aprovada. Permitir ativação somente com integração ativa e requisitos daquele método concluídos, incluindo credenciais, escopos e webhooks exigidos. Responder com erro seguro e mostrar modal “integração não aprovada” quando pendente/reprovada.

Implementar troca atômica por seller/método: reservar um registro de controle/seleção único para esse escopo, desabilitar o método anterior para novas vendas e habilitar o novo na mesma transação. Ajustar validações existentes que exigem outro padrão ativo para permitir essa troca atômica. Garantir a invariável em criação, edição, backfill e disponibilidade, não apenas no dashboard. Não migrar autorizações antigas nem impedir reconciliação da integração anterior.

**Aceite:** duas ativações concorrentes deixam no máximo um gateway disponível para aquele método; Pix e cartão em gateways diferentes funcionam; método pendente não aparece no checkout nem é ativável por requisição direta.

## C11 — fechar rota de edição e regra comercial no Commerce

**Problemas confirmados:** dashboard chama `PATCH /checkout-transparent/integrations/{id}`, mas essa rota não foi encontrada no gateway da feature. A public-api remove `installments` do payload enviado ao Commerce, impedindo esse caminho de validar a escolha contra a regra do produto.

**Correção sugerida:** adicionar encaminhamento PATCH no gateway com autenticação/permissão compatíveis com as rotas existentes. Encaminhar parcelas e demais campos comerciais não sensíveis ao Commerce e executar lá as mesmas regras autoritativas de cartão: produto, valor, elegibilidade e limites. O CT mantém restrições técnicas do provider, sem duplicar política comercial. Não reintroduzir campos brutos de cartão para corrigir parcelas.

**Aceite:** editar integração pelo dashboard chega ao destino e respeita ownership; parcelas acima do limite do produto ou valor adulterado são rejeitados no servidor; checkout legado permanece compatível.

## C12 — habilitar RisePay e impedir vazamento em erros

**Situação:** RisePay tem tokenização JWE, decryptor e criação de transação, mas permanece desabilitada pelo plano/flag. Foi solicitada sua habilitação. Sanitizadores atuais também deixam segredo/CPF/e-mail em alguns textos livres; há caminhos de mensagens de erro brutas.

**Correção sugerida:** fechar C02/C03/C05 antes da ativação RisePay, conferir rota, chaves pública/privada, seleção de método, consulta de status e reconciliação por referência quando o envio teve resultado desconhecido. Homologar e atualizar o novo plano para permitir a flag; não considerar pronto só por trocar `false` para `true`.

Nos erros, usar códigos/mensagens públicas permitidas e payloads operacionais selecionados; sanitizar antes de gravar/publicar/expor, inclusive texto livre. Não confiar somente no nome da chave do JSON ou em regex de número de cartão. Aplicar aos logs, erros de tentativa, auditoria e relatório seller, mantendo isolamento por seller.

**Aceite:** RisePay aprovada/recusada/pendente/timeout funciona sem repetição de cobrança; dados sintéticos de cartão/CVV/segredo não aparecem em logs, banco, fila ou painel; seller não lê erro de outra integração.

## C13 — mostrar cartão também em Editar Produto

**Requisito do produto:** quando cartão estiver disponível no checkout, a tela Editar Produto precisa exibir a configuração correspondente, incluindo habilitação e regras de parcelas existentes. Mostrar a configuração não significa ativar cartão automaticamente em todos os produtos.

**Pontos confirmados para revisão:** `dashboard-seller/product_form.php` carrega `seller.payment_methods.credit_card.available`; `views/dashboard/products/form/_components/checkout.php` condiciona a seção a `$cardFeatureEnabled` e calcula `$creditCardEnabled` combinando disponibilidade com configuração salva. Revisar também `product_edit.php`, `views/dashboard/products/form/index.php` e o caminho de salvamento. A inclusão deste requisito não afirma que a falha visual foi reproduzida em ambiente.

**Correção sugerida:** unificar a disponibilidade de cartão usada pelo checkout e pelo formulário de edição, considerando o método CT ativo/aprovado, não somente a integração de cartão do checkout normal. Propagar essa informação pelo contrato público/Commerce até o dashboard e ajustar as condições de renderização para permitir a edição quando o seller tem cartão disponível. Manter valor salvo, habilitação e limites de parcelas do produto sob as regras autoritativas do Commerce (C11).

Disponibilidade da integração e preferência salva do produto são estados distintos. Se a integração ficar temporariamente indisponível, indicar isso sem apagar silenciosamente a configuração do produto ao salvar outra informação. Se o produto não for elegível para cartão, manter a regra de elegibilidade e explicar a restrição.

**Aceite:** seller com cartão CT aprovado e disponível vê a opção em Editar Produto; ativa/desativa e ajusta parcelas, salva e reabre com os valores preservados; o checkout reflete a configuração salva. Seller sem integração de cartão normal, mas com cartão CT disponível, também vê a opção. Alteração de campo não relacionado e falha temporária da consulta não zeram a preferência de cartão. Testar regressão do cartão normal e produtos não elegíveis.

## Ordem e entrega esperada do dev

1. Fechar contratos C02/C03/C06/C08/C10/C11 e incluir as dependências C01 na entrega.
2. Corrigir credenciais, recuperação durável e calendário: C04/C05/C09.
3. Integrar polling por conta, callbacks, cancelamento e billing: C06/C07/C08.
4. Fechar painel/rotas, paridade da edição de produto e homologar RisePay: C10/C11/C12/C13.
5. Executar os oito grupos do [roteiro funcional e de código](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW.md), incluindo regressão do checkout legado, concorrência e falhas.

Para schema necessário, criar migrations novas; não editar migrations já commitadas. Validar backfill com dados antigos e repetição, constraints/índices com consultas reais e compatibilidade de versões durante rollout. Preservar worktrees locais e correções de `main`; não limpar Redis nem apagar operações para fazer testes passarem.

Registrar por item: commits alterados, teste executado, resultado e pendência. Atualizar o plano de deploy com todos os componentes, flags e contratos finais. Não há aprovação de liberação até os bloqueios terem evidência de correção e homologação; somente sintaxe PHP e leitura estática foram validadas na revisão inicial.
