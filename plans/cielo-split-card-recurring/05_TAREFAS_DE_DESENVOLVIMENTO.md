# Backlog executável de desenvolvimento

> Ordem obrigatória: não ativar a interface pública antes de os bloqueios de persistência e checkout estarem implantados e testados. A conclusão de uma tarefa não autoriza ativação em produção.

## Pré-requisitos externos e decisões

- [ ] Cielo confirma por escrito Recorrência Programada, Split pós-transacional, webhook `ChangeType: 2`, tokenização/Cartão Protegido e política de CVV para a conta Master.
- [ ] Sandbox comprova criação, primeira parcela, próxima parcela, consulta, Split e cancelamento.
- [ ] Produto e Financeiro aprovam composição recorrente para principal, oferta, desconto, bump, afiliado, MDR/tarifa e falha de Split.
- [ ] Segurança aprova o contrato de tokenização e confirma que nenhum dado de cartão será persistido.

## 1. Dashboard Seller — restrição e configuração de produto

- [ ] Criar um resolvedor local que busque exclusivamente `user_system_vars.cielo_split_card_recurring_enabled` para um seller e devolva `null`, `false` ou `true`; ausência é `null`.
- [ ] Incluir o seletor triestado nas duas telas administrativas de restrição.
- [ ] Estender `actions/admin/user/restrictions.php` para validar, inserir/atualizar `0`/`1` ou apagar somente a chave quando `null`.
- [ ] Ajustar a listagem assíncrona de sellers para carregar o estado da chave e inicializar corretamente seu modal.
- [ ] Ajustar a visão geral de seller para carregar e renderizar o mesmo estado.
- [ ] Incluir a elegibilidade recorrente do seller na montagem de `product_form.php`, usando o dono do produto quando houver edição administrativa.
- [ ] Em `SUBSCRIPTION` elegível, exibir cartão com texto de recorrência e campo hidden `credit_card_installments=1`; não renderizar o seletor de parcelas nem o modal de regras.
- [ ] Em assinatura não elegível, manter cartão indisponível. Não alterar o fluxo existente de `ONE_TIME`.
- [ ] Cobrir com teste/manual controlado: `null`, `0`, `1`, edição por admin de produto de outro seller, cartão não aprovado e produto avulso.

## 2. Commerce V2 — fonte de decisão e persistência segura

- [ ] Criar caso de uso/resolvedor de elegibilidade da recorrência Cielo, baseado na chave por seller, no gateway `cielo_ecommerce` e na elegibilidade Cielo existente.
- [ ] Expor apenas o booleano necessário em `GET /products[/id]/form-data`.
- [ ] Completar `ValidateProductPaymentMethodsUseCase`: em `SUBSCRIPTION` com cartão, exigir elegibilidade e exatamente `credit_card_installments=1`.
- [ ] Garantir o mesmo resultado em criação, atualização e manutenção de ofertas, aproveitando o validador comum já chamado por esses fluxos.
- [ ] Ajustar resolução de métodos, shortcode/contexto público e request de checkout para aceitar cartão somente para a assinatura Cielo elegível.
- [ ] Rejeitar `installments > 1` no request e no caso de uso de checkout, mesmo que o request pule a interface.
- [ ] Criar testes unitários/focados para a matriz de decisão do documento 04 e testes de regressão de `ONE_TIME`.

## 3. Banking V2 — criação e ciclo da série Cielo

- [ ] Criar o contrato de criação de recorrência no cliente Cielo, isolado do cartão avulso.
- [ ] Persistir a assinatura provisória e o `RecurrentPaymentId` de modo idempotente.
- [ ] Modelar/persistir a evidência do Split pós-transacional por `PaymentId`, se os campos atuais não forem suficientes.
- [ ] Criar publicação exclusiva para `commerce:cielo:subscriptions:actions`, com envelope versionado `subscription.charge.paid`.
- [ ] Implementar consulta por `RecurrentPaymentId`, cancelamento, reconciliação limitada e recuperação de Split pendente.
- [ ] Implementar métricas, retry e DLQ antes de habilitar publicação financeira.

## 4. Edge Webhook

- [ ] Aceitar e validar `ChangeType: 2`, exigindo `PaymentId` e preservando `RecurrentPaymentId` para auditoria.
- [ ] Conservar assinatura/verificação e deduplicação existentes; redelivery não pode criar duas mensagens de negócio.
- [ ] Encaminhar o evento para Banking sem dados de cartão ou segredo.

## 5. Commerce V2 — compensação assíncrona

- [ ] Registrar processo consumidor exclusivo, inicialmente desligado, para `commerce:cielo:subscriptions:actions`.
- [ ] Reutilizar `ProcessSubscriptionChargePaidUseCase` e `ProcessPaidSaleEventUseCase` para primeira e demais parcelas.
- [ ] Garantir unicidade/idempotência por `RecurrentPaymentId` + `PaymentId` e manter efeitos de venda pagos uma única vez.
- [ ] Tratar explicitamente a decisão Financeiro sobre confirmar venda antes/depois do Split pós-transacional.

## 6. Front Checkout

- [ ] Renderizar cartão em assinatura somente quando o contexto público do Commerce V2 o anunciar.
- [ ] Mostrar somente `1x`; não enviar valor de parcelas maior que um.
- [ ] Aplicar o contrato aprovado de tokenização/3DS sem persistir ou registrar PAN, CVV ou token.
- [ ] Tratar pendência, recusa e confirmação da primeira cobrança sem marcar compra como paga prematuramente.

## 7. Teste integrado e rollout

- [ ] Publicar schemas/processos com a disponibilidade desligada.
- [ ] Homologar a matriz de configuração de seller e produto antes da primeira cobrança.
- [ ] Homologar uma série completa: criação, primeira parcela, renovação, reentrega de webhook, Split, venda, entrega, comissão, cancelamento e refund de parcela.
- [ ] Habilitar para um seller de teste e periodicidade mensal; conciliar todos os valores e evidências.
- [ ] Ampliar somente após aprovação de Produto, Financeiro e Operações.

## Critérios de encerramento

O desenvolvimento só estará pronto para rollout quando todos os itens acima estiverem concluídos, a Cielo tiver confirmado o contrato externo e os seguintes invariantes forem demonstrados: ausência/`0` da flag nega cartão; `1` não supera a ausência de elegibilidade Cielo; assinatura aceita somente `1x`; cartão avulso permanece inalterado; nenhuma reentrega cria venda, Split, saldo, comissão, entrega ou notificação duplicados.
