# Checkout Transparente — roteiro de revisão de cartão e Pix Automático

Data: 2026-10-13. Revisão estática das branches remotas `feat/checkout-transparent-card`, comparadas com `origin/main`, após fetch. Complementa o [plano de deploy](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_DEPLOY.md); não autoriza publicação.

Os [esclarecimentos e regras de aceite](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW_DETAILS.md) detalham os pontos 1–9 e registram as decisões posteriores do produto: gateway único por seller/método, ativação após aprovação, cancelamento bloqueando novos ciclos, regras comerciais no Commerce V2 e inclusão de RisePay no escopo. A descrição abaixo registra o código examinado, não implementação dessas correções.

## Parecer

A direção arquitetural é adequada: métodos separados por integração, tokenização no provedor, tentativas de cartão separadas da cobrança e entidades próprias para autorização/parcelas recorrentes. Isso evita encaixar toda recorrência em uma cobrança Pix avulsa.

**Não considero o conjunto pronto para liberação.** Existem lacunas confirmadas no encadeamento entre repositórios, transporte de dados de cartão, atualização de credenciais e recuperação de recorrência. A escalabilidade ainda não está demonstrada: há consumidores sequenciais e consultas de polling que podem deixar registros indefinidamente sem processamento.

“Confirmado” abaixo significa observado no código ou em uma sondagem local, não reproduzido em produção. Consequências financeiras e contratos reais de gateways precisam de homologação.

## Escopo e versões examinadas

| Repositório | `main` | Branch da feature | Arquivos alterados |
| --- | --- | --- | ---: |
| services-checkout-transparent-api | `55ce14aa` | `ecc012a0` | 68 |
| services-checkout-transparent-worker | `167ade52` | `fcc86992` | 24 |
| edge-checkout-transparent-webhook | `5ad99b32` | `b8d63ea1` | 7 |
| edge-public-api | `1dbd3a8c` | `026b87f9` | 10 |
| edge-gateway | `40757796` | `4613767e` | 1 |
| front-checkout | `65c4c4e4` | `830c6a2e` | 9 |
| dashboard-seller | `60f2b68b` | `bd673bd6` | 19 |
| services-commerce-v2 | `4cd8a7b1` | `a4b0015c` | 11 |
| edge-webhook | `6e1dc1fc` | `74be04f3` | 3 |

Inventário: 152 arquivos. Revisão das alterações textuais e caminhos relacionados de checkout, integrações, filas, migrations, billing e confirmação de venda; a imagem de tutorial não recebeu validação visual. Commerce V2 e edge-webhook são dependências reais, embora não estejam entre os sete repositórios listados para publicação no plano original. Banking V2 e o consumidor de billing foram consultados como dependências, não como novas entregas deste pacote.

Foram preservadas as alterações locais dos repositórios. A análise usou as referências remotas, sem checkout das branches da feature.

## Bloqueios e riscos prioritários

Prioridade P1: resolver ou comprovar segurança antes da liberação. P2: corrigir ou definir uma restrição operacional explícita, com teste e responsável.

### 1. P1 — plano de deploy não fecha o fluxo de venda

**Confirmado:** Commerce V2 possui mudanças exclusivas da feature para resolver métodos transparentes, compartilhar a referência da assinatura e tratar confirmação recorrente. O edge-webhook principal adiciona `/api/checkout-transparent/subscription-paid` e o encaminhamento da ação de assinatura. Essas alterações não estão nas respectivas `main` examinadas.

Publicar somente os sete componentes do plano deixa esse caminho incompleto. Integrar essas dependências antes do aceite e testar a confirmação até a venda/acesso, não somente até o status no CT.

O ct-webhook próprio recebe os eventos dos provedores. A dependência do edge-webhook principal é outra etapa: `CommerceWebhookClient::notifySubscriptionPayment` chama a rota acima para levar a confirmação ao Redis principal/Commerce. Não se trata de substituir ou ignorar o webhook isolado do CT.

**Cuidado adicional:** a branch de Commerce está atrás da `main` em mudanças alheias à feature. Não substituir o estado atual por essa branch. A implementação de `ProcessSubscriptionChargePaidUseCase::recurringSale` também precisa preservar a correção da `main` que recompõe o valor bruto da parcela; a versão da feature clona valores sem a mesma recomposição. Revisar o resultado do merge, incluindo taxas e valor da venda recorrente.

### 2. P1 — tokenização não impede o envio de PAN/CVV à Lowify

**Confirmado:** o formulário cria `FormData(form)` e remove campos brutos de cartão apenas em condições de providers antigos (`pagarme_psp` sem 3DS e `risepay_jwe`). Os novos providers `mercado_pago`, `pagarme` e `efi_bank` não entram nessa remoção. `process.php` encaminha o payload ao backend. A filtragem na public-api ocorre depois de o dado já passar pela infraestrutura Lowify.

Remover os campos antes do primeiro envio e conferir a requisição real no navegador. Isso não demonstra persistência de PAN/CVV, mas contradiz o objetivo de não recebê-los no backend.

**Também confirmado por sondagem do sanitizador:** mensagens contendo `token=SYNTHETIC_SECRET`, CPF formatado e e-mail permaneceram intactas, embora Bearer e cartão contínuo tenham sido mascarados. Existem caminhos com mensagens brutas em logs/erros de tentativa. Usar mensagens públicas permitidas e sanitização consistente; testar logs, banco, auditoria e endpoint de erros com dados sintéticos.

### 3. P1 — refresh Mercado Pago não atualiza credenciais usadas pelo worker

**Confirmado:** a feature copia credenciais para métodos Pix/cartão. `GetGatewayContextUseCase` passa a ler as credenciais do método, enquanto `ApplyMercadoPagoOAuthTokenRefreshResultUseCase::persistTokens` continua atualizando `integration_keys`. A atualização do token legado não atualiza automaticamente as cópias dos métodos.

Testar expiração/refresh com ambos os métodos e definir uma fonte única de credenciais, ou atualização atômica das cópias. “Conexão válida” no painel não basta se a cobrança usa um token antigo.

### 4. P1 — recuperação e idempotência de recorrência incompletas

**Confirmado:** `CreateCheckoutSubscriptionUseCase` grava a assinatura antes de publicar a instrução. Se a publicação falhar, a repetição encontra a assinatura por venda e retorna sem republicar. Sem ID no gateway, ela também fica fora da recuperação por polling.

O consumidor de instruções usa `BLPOP`, processamento de rede sequencial e retry em memória. Os consumidores de resultado/confirmação também retiram mensagens antes de completar o efeito e possuem caminhos que apenas registram a falha. Isso é uma fragilidade herdada de fila, agora aplicada a obrigações recorrentes.

Na criação Efí há múltiplas operações externas (`locrec`, cobrança imediata, recorrência, consulta), sem checkpoints persistidos suficientes para retomar cada etapa. Uma falha intermediária pode deixar recursos órfãos ou recriar operações. Além disso, reenvio do checkout recebe novo UUID e Pix Automático não usa a mesma deduplicação de venda pendente aplicada a Pix/cartão.

Exigir identidade estável da operação, recuperação da publicação, reentrega durável e reconciliação após falha parcial. Testar timeout depois de sucesso no provedor, queda do worker e falha de Redis/Commerce.

### 5. P1 — autorização ativa não equivale a primeira parcela paga

**Confirmado:** polling Efí transforma autorização `APROVADA` em `subscription.active`. A página `transparent_payment.php` trata assinatura `active` como pagamento confirmado. O contrato retornado não distingue suficientemente autorização ativa e primeira cobrança liquidada para essa decisão de interface.

Separar os dois estados e só apresentar compra paga/liberar acesso conforme a regra explícita do negócio. Testar autorização aprovada com cobrança inicial pendente ou falha. A notificação Efí de cancelamento de recorrência também precisa ser exercitada: o resolvedor atual não cobre adequadamente esse evento; reconciliação tardia não deve permitir novas cobranças indevidas.

### 6. P1 — fallback da primeira cobrança Efí consulta o recurso errado

**Confirmado:** a primeira cobrança é criada em `/v2/cob`, mas o polling das parcelas consulta genericamente `/v2/cobr/{id}`. A cobrança imediata e a cobrança recorrente têm recursos e respostas distintos. O webhook inicial pode funcionar e esconder a falha do fallback.

Separar a recuperação por tipo de cobrança; homologar a primeira parcela sem webhook e as parcelas futuras sem webhook. Referência: [Efí — cobranças imediatas](https://dev.efipay.com.br/docs/api-pix/cobrancas-imediatas/) e [Pix Automático](https://dev.efipay.com.br/docs/api-pix/pix-automatico/).

### 7. P1 — custo/billing da recorrência precisa de caminho comprovado

**Confirmado no caminho examinado:** `ConfirmCheckoutSubscriptionPaymentUseCase` notifica Commerce e marca a parcela como paga, mas não faz o snapshot/publicação de billing presente no fluxo avulso (`CreateChargeUseCase` / `ConfirmChargePaymentUseCase`). Não foi encontrado produtor alternativo equivalente para essas parcelas nos caminhos relacionados.

Antes do aceite, comprovar como cada parcela gera o custo contratado exatamente uma vez. Se a política comercial isenta alguma parcela, documentar isso e testar a exceção. Validar valor bruto, taxas, repasse e reentrega sem débito duplicado.

Regra financeira definida posteriormente pelo produto: cartão gera billing uma vez na primeira parcela/confirmação elegível; Pix assinatura gera billing no pagamento de cada recorrência. O achado trata do custo Lowify, não propõe cobrar novamente o comprador em cada prestação de cartão.

### 8. P1 — polling pode repetir os mesmos registros e abandonar outros

**Confirmado:** a consulta de assinaturas aplica `ORDER BY updated_at` e limite antes do filtro Efí feito no processo. Registros ativos cujo status não muda continuam elegíveis sem avançar um cursor/`last_polled_at`. O mesmo lote pode ocupar repetidamente o limite de 100; registros de outro provedor também consomem posições. Há problema semelhante na consulta de parcelas pendentes.

Separar seleção por provedor, definir próxima consulta/cursor e distribuir lotes com justiça. Medir backlog e tempo até reconciliação com volume acima do limite. A frequência horária de polling e o worker sequencial de instruções não constituem, sozinhos, uma estratégia de escala.

### 9. P2 — calendário, transições e configuração exigem fechamento

- O primeiro vencimento usa ajuste de mês com limite de dia; vencimentos posteriores usam `modify('+1 month')`. Sondagem reproduziu `2027-01-31 → 2027-03-03`. Definir aniversário, fevereiro, ano bissexto e fuso de maneira consistente.
- Reentrega de resultado não deve voltar parcela paga para pendente nem avançar vencimento duas vezes. Cancelamento e confirmação fora de ordem precisam preservar invariantes.
- O dashboard usa `PATCH /checkout-transparent/integrations/{id}`, mas a rota correspondente não foi encontrada no gateway da feature. Testar edição real, não apenas criação.
- A configuração por método pode ser habilitada antes de terminar validação assíncrona de escopo/webhook. Exercitar falha e repetição do cadastro, sem deixar método disponível em estado parcialmente configurado.
- A exclusividade do método padrão por seller não está garantida pela constraint de método por integração. Regra definida pelo produto: somente um gateway ativo por seller/método, não apenas um padrão; testar ativações concorrentes e proteção no backend.
- Validar parcelas contra o limite do produto no servidor. A remoção de `installments` do payload Commerce não pode eliminar essa proteção.
- RisePay cartão continua com código/catálogo sob flag desabilitada. O produto solicitou habilitá-lo: incluir no roteiro de implementação e homologação, fechando envelope, idempotência e reconciliação antes da ativação.

## Roteiro de revisão e homologação

Executar em ambiente com bancos/Redis isolados e contas sandbox. Para cada cenário, guardar ID da venda, assinatura, parcela, tentativa e operação do provedor, sem dados sensíveis. Conferir navegador, API, banco, fila e efeito final em Commerce/billing.

| Grupo | Análise de código | Fluxos funcionais mínimos / critério de aceite |
| --- | --- | --- |
| 1. Integração e permissões | Rotas gateway/public/CT; ownership por seller; segredo público vs privado; validação assíncrona; método padrão e edição. | Criar/editar/desativar integração; seller A não lê/altera B; conta inválida não aparece disponível; habilitar Pix não quebra cartão e vice-versa; refresh MP mantém os dois funcionando. |
| 2. Disponibilidade e checkout legado | Commerce resolve produto/método; flags; regras de parcelas, recorrência e provider; contrato público. | Produto avulso e recorrente; CT ligado/desligado; provider sem método; Pix legado, cartão legado e 3DS continuam funcionando; valor e parcelas respeitam produto. |
| 3. Cartão transparente | Tokenização de MP/Pagar.me/Efí; whitelist de payload; tentativas, status e idempotência; erros seguros. | Aprovação, recusa, pendência seguida de aprovação, token inválido e timeout; duplo clique/reenvio não duplica cobrança; nenhuma requisição Lowify contém PAN/CVV; erros não expõem segredo. |
| 4. Pix Automático: adesão | Referência estável de assinatura; criação Efí/Woovi; pagamento inicial separado da autorização; recursos criados parcialmente. | Autorização aprovada sem pagamento; inicial pago/pendente/expirado; abandono, reenvio e timeout após sucesso; uma adesão/venda lógica; acesso só no estado contratado. |
| 5. Pix Automático: ciclo de vida | Calendário, agendador, parcela única, cancelamento, estados terminais e corrida entre eventos. | Segunda/terceira parcela; dia 28–31 e fevereiro; saldo insuficiente; cancelamento antes/depois do agendamento; webhook duplicado/fora de ordem; assinatura cancelada não gera próxima cobrança. |
| 6. Webhooks e recuperação | Autenticação/validação conforme provider; roteamento; assinatura/parcela correta; retry, ACK, outbox e polling. | Webhook ausente, duplicado, inválido e anterior ao resultado; queda do worker/Redis; Commerce indisponível; reprocessamento converge sem duplicação. Validar payload real Woovi e correlação por assinatura/parcela. |
| 7. Venda e financeiro | Confirmação edge-webhook → Commerce; valor bruto, taxas, billing por parcela e idempotência. | Uma venda recorrente por pagamento; liberação/acesso e notificações uma vez; custo/repasse correto; nenhuma venda ou débito duplicado após reentrega. |
| 8. Banco, capacidade e operação | Migrations/backfill, constraints, índices/EXPLAIN, retenção de chaves/erros, métricas e rollback compatível. | Base com dados antigos; migração/backfill repetido sem perda; concorrência; mais de 100 assinaturas/parcelas; todos recebem polling; backlog drena dentro do SLA definido; rollback não perde obrigações ativas. |

## Avaliação do modelo de dados e da escala

**Boas decisões:** credenciais/regras por método; tabela de tentativas; assinatura e parcelas próprias; constraints de integração/método e assinatura/parcela; locks transacionais no agendamento. Essas peças fornecem uma base melhor que sobrecarregar a cobrança avulsa com todos os estados.

**O que falta provar ou corrigir:**

- As sete migrations e o backfill Pix precisam preservar integrações existentes, criptografia e disponibilidade durante rollout. Conferir antes/depois, execução repetida e versões antigas ainda em execução; rollback de código não desfaz cobranças externas nem autorizações vigentes.
- Constraint única não garante entrega exatamente uma vez ao provedor. Persistir intenção/etapa e resultado de operações externas; tratar timeout como estado desconhecido, não como autorização para criar outra cobrança.
- Índices atuais não cobrem diretamente todos os filtros/ordenações de scheduler e polling. Validar planos para `(status, next_charge_due_at, id)` e seleção de polling por provedor/data, de acordo com a consulta final, em volume representativo.
- Evitar consultas N+1 de integração/contexto nos lotes e crescimento ilimitado de histórico de chaves/erros. Definir retenção, limites de paginação e métricas por provider.
- O lock Redis do agendador tem TTL finito e liberação sem token de propriedade. Validar lote que ultrapasse o TTL e execução concorrente; locks de banco e unicidade ajudam, mas não substituem o teste de publicação duplicada.
- Medir latência e saturação: um único consumidor de instruções faz chamadas externas síncronas; timeouts de 30 segundos bloqueiam os próximos trabalhos. Definir concorrência, rate limit por provider/seller, backpressure e alerta de idade do item mais antigo.

**Conclusão:** modelo extensível, mas segurança e escala dependem do fechamento dos estados, da consistência das credenciais e da entrega/reconciliação durável. Adicionar tabelas e filas não comprova esses atributos por si só.

## Evidências de código para orientar a revisão

Os links abaixo estão fixados nas versões analisadas; os nomes de classes/métodos nos achados permitem localizar os caminhos complementares.

- [Front: formulário e montagem do payload](https://github.com/lowify/front-checkout/blob/830c6a2ea55bd736c3bf5695c438de85b0fb2cd4/views/checkout/form/index.php) e [retorno de pagamento](https://github.com/lowify/front-checkout/blob/830c6a2ea55bd736c3bf5695c438de85b0fb2cd4/transparent_payment.php).
- [CT API: contexto de credenciais](https://github.com/lowify/services-checkout-transparent-api/blob/ecc012a073b6d604826225b4b5110a25a1f5fcd5/app/Application/UseCase/Worker/GetGatewayContextUseCase.php) e [refresh Mercado Pago](https://github.com/lowify/services-checkout-transparent-api/blob/ecc012a073b6d604826225b4b5110a25a1f5fcd5/app/Application/UseCase/Integration/ApplyMercadoPagoOAuthTokenRefreshResultUseCase.php).
- [CT API: resultado de gateway](https://github.com/lowify/services-checkout-transparent-api/blob/ecc012a073b6d604826225b4b5110a25a1f5fcd5/app/Process/GatewayResultQueueProcess.php) e [confirmação](https://github.com/lowify/services-checkout-transparent-api/blob/ecc012a073b6d604826225b4b5110a25a1f5fcd5/app/Process/PaymentConfirmedQueueProcess.php).
- [Worker: versão examinada](https://github.com/lowify/services-checkout-transparent-worker/tree/fcc86992353d1c1276e0ee14b8c2c54a6432d519): `GatewayInstructionQueueProcess`, `EfiBankSubscriptionClient` e publicadores de resultado.
- [Commerce: versão examinada](https://github.com/lowify/services-commerce-v2/tree/a4b0015c04ee4124f315baffc902df2dbf445c10): `ProcessProductCheckoutUseCase`, `FindDuplicatePendingSaleUseCase` e `ProcessSubscriptionChargePaidUseCase`.
- [edge-webhook: confirmação recorrente](https://github.com/lowify/edge-webhook/tree/74be04f3a142dab1e2ebad7f84ad85990151c6a0); [gateway: rotas da versão examinada](https://github.com/lowify/edge-gateway/tree/4613767ece996267beafa313925ca142f907f119).
- [Woovi: contrato público](https://developers.woovi.com/en/api-redoc). A correlação de eventos deve ser validada com payloads reais; não considerar o funcionamento confirmado apenas pela leitura do exemplo.

## Verificações executadas e limites

- Sintaxe dos 139 arquivos PHP alterados: aprovada com PHP 8.3.26.
- `git diff --check` nos nove repositórios: aprovado.
- Sondagens locais do sanitizador e do cálculo mensal: problemas descritos acima reproduzidos com entradas sintéticas.
- Não foram encontrados testes novos para esses fluxos nas alterações, nem harness de testes nos serviços CT examinados.
- Não foram executados migrations em banco real, checkout de homologação, chamadas financeiras, teste de carga ou validação em VPS. Sintaxe aprovada não comprova integração, segurança ou comportamento financeiro.

## Condição de liberação

Fechar os P1 com evidência de código e cenário de homologação; integrar as dependências preservando as correções da `main`; executar os oito grupos acima; registrar política de billing e liberação de acesso; definir SLA de reconciliação e sinais de rollback. Pendências P2 só podem permanecer com impacto delimitado e responsável explícito. Até lá, este documento é roteiro de revisão, não aprovação de deploy.
