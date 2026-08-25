# Fase 3 — Acesso, dispatch e histórico

## Dependências e decisões

Esta fase consome as regras e a taxa efetiva das Fases 1 e 2. Ela introduz o
rollout controlado e o ciclo operacional; a página consolidada de status fica
na Fase 4 e a liquidação financeira na Fase 5.

| Tema | Decisão |
| --- | --- |
| Produto principal | Usar exclusivamente `tbl_sale_items.item_type = 'principal'`. O código novo não deve usar o fallback legado para o primeiro item. |
| Confirmação de envio | Reutilizar o fluxo de status já empregado por `sales_delivery`: registrar `sent_to_provider` quando o sender recebe o ID externo e atualizar em callback/webhook para sucesso, falha ou leitura. |
| Retry | Não haverá retry nem reenvio para recovery nesta primeira versão. |
| WhatsApp | Usar conta Meta padrão. |
| E-mail | Usar o remetente/provedor definido no template Twig salvo no banco. |
| Opt-in/opt-out | O controle será interno à plataforma. |
| Visibilidade seller/afiliado | Uma recuperação originada por afiliado é visível apenas para esse afiliado em detalhe de venda; o produtor não vê esse bloco. |
| Visibilidade admin | `admin_sale_detail` sempre exibe o histórico, seja do produtor ou afiliado. |
| Feature flag | Desligada por padrão para todos; admins 1 e 2 habilitam/desabilitam por usuário na área de Restrições. |

## Fluxo atual de `sales_delivery`

```text
services-notification sender
  → envia a mensagem ao provedor e persiste external_id
  → publica sent_to_provider na fila Redis sales:delivery:actions
  → callback/webhook do provedor atualiza email_single ou whatsapp_meta
  → publica success / fail / read na mesma fila
  → services-commerce-v2: SaleDeliveryCreationProcess consome a fila
  → CreateSaleDeliveryUseCase faz upsert em sales_delivery por (type, reference_id)
```

Hoje isso é implementado por:

- `services-notification/app/Service/SaleDeliveryResultQueueService.php`;
- `services-notification/app/Service/EmailSenderService.php`;
- `services-notification/app/Service/WhatsappMetaSenderService.php`;
- `services-notification/app/Process/EmailDeliveryStatusQueueProcess.php`;
- `services-notification/app/Process/WhatsappMetaDeliveryStatusQueueProcess.php`;
- `services-commerce-v2/app/Process/SaleDeliveryCreationProcess.php`;
- `services-commerce-v2/app/Domain/Sale/Repository/SaleDeliveryRepository.php`.

## Fila genérica de resultado de notificação

Substituir a publicação específica de `sales_delivery` por uma fila genérica, por exemplo `sales:notification:results`. O `services-notification` publica tanto o resultado da entrega de compra quanto o resultado de recovery.

Payload proposto:

```json
{
  "context": "sale_delivery",
  "subject_id": 123,
  "channel": "whatsapp",
  "reference_type": "whatsapp_meta",
  "reference_id": 456,
  "status": "sent_to_provider",
  "error": null
}
```

```json
{
  "context": "sale_recovery",
  "subject_id": 789,
  "channel": "email",
  "reference_type": "email_single",
  "reference_id": 321,
  "status": "success",
  "error": null
}
```

- Em `sale_delivery`, `subject_id` é o `sale_id`.
- Em `sale_recovery`, `subject_id` é o `sale_recovery_dispatches.id`.
- `reference_type` e `reference_id` identificam a mensagem concreta criada no notification service.

No `services-commerce-v2`, um único processo consumidor valida o payload e roteia pelo `context`:

```text
sale_delivery → CreateSaleDeliveryUseCase → sales_delivery
sale_recovery → RegisterSaleRecoveryEventUseCase → dispatch + eventos
```

No contexto `sale_recovery`, o resultado do provedor é convertido para a
semântica do dispatch: `success` torna-o `confirmed`, `fail` torna-o `failed`
e `read` é registrado como evento posterior sem reabrir cobrança ou envio.

Isso mantém a integração com o provedor concentrada no `services-notification` e evita acoplar o novo RDC à tabela `sales_delivery`.

## Aplicação para recovery

Não usar `sales_delivery` para persistir recovery. Reaproveitar o mesmo padrão de
sender → webhook → fila → consumer, mas com uma correlação por dispatch:

```text
Mensagem de recovery
  → correlation/params incluem sale_recovery_dispatch_id
  → sender publica sent_to_provider na fila genérica
  → webhook publica success / fail / read na fila genérica
  → consumer genérico do Commerce roteia para recovery
  → grava sale_recovery_dispatch_events e atualiza o dispatch
```

Para e-mail, criar um correlation type próprio, por exemplo
`sale_recovery_email`, cujo `correlation.id` é o ID do dispatch. Para Meta,
incluir `mode = sale_recovery` e `sale_recovery_dispatch_id` nos parâmetros.
O dispatcher não deve depender de `sale_id` para correlacionar o callback.

## Responsabilidades por arquivo

### `services-commerce-v2`

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `app/Application/UseCase/Sale/ProcessPendingSaleEventSaleRecoveryUseCase.php` | Alterar | Resolver o item com `item_type = principal`, a regra por produto/responsável e criar um dispatch por stage/canal. |
| `app/Application/UseCase/Sale/ExecuteSaleRecoveryDispatchUseCase.php` | Alterar | Enviar recovery somente por e-mail/Meta, com uma tentativa por canal. |
| Scheduler/worker legado de Evolution | Descontinuar | Impedir novos agendamentos e envios pelo canal legado antes de habilitar o fluxo oficial. |
| `app/Application/DTO/Sale/SaleNotificationResultMessage.php` | Novo | Validar o payload genérico: contexto, subject, canal, referência do provedor, status e erro. |
| `app/Process/SaleNotificationResultProcess.php` | Novo | Consumir a fila genérica e rotear eventos de delivery e recovery. |
| `app/Application/UseCase/Sale/RegisterSaleRecoveryEventUseCase.php` | Novo | Aplicar evento de forma idempotente e gravar em `sale_recovery_dispatch_events`. |
| `app/Application/UseCase/Sale/CreateSaleDeliveryUseCase.php` | Alterar somente se necessário | Continuar persistindo `sales_delivery`, agora chamado pelo consumidor genérico. |
| `app/Domain/Sale/Repository/SaleRecoveryDispatchRepository.php` | Alterar | Buscar/atualizar dispatch por ID, com transição de status válida e sem retry automático. |
| `app/Domain/Sale/Repository/SaleRecoveryDispatchEventRepository.php` | Novo | Inserir eventos idempotentes e listar timeline. |
| `config/autoload/sale_recovery.php` | Alterar | Adicionar filas e limites da recuperação oficial. A feature flag é resolvida pelo Account. |
| `plans/sale-recovery/deploy/001_sale_recovery.sql` | Alterar | Evoluir `sale_recovery_dispatches` e criar a tabela de eventos pelo SQL manual. |

### `services-notification`

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `app/Service/SaleDeliveryResultQueueService.php` | Renomear/evoluir para serviço genérico | Publicar `sale_delivery` e `sale_recovery` na mesma fila, com `context` e `subject_id`. |
| `app/Service/EmailSenderService.php` | Alterar | Para mensagens `sale_recovery`, publicar `sent_to_provider` e falha usando o dispatch; forçar apenas uma tentativa de envio. |
| `app/Service/WhatsappMetaSenderService.php` | Alterar | Para mensagens `sale_recovery`, publicar eventos pelo dispatch, usar conta Meta padrão e forçar uma tentativa; não disparar fallback automático de e-mail. |
| `app/Process/EmailDeliveryStatusQueueProcess.php` | Alterar | Publicar na fila genérica, escolhendo delivery ou recovery pela correlação. |
| `app/Process/WhatsappMetaDeliveryStatusQueueProcess.php` | Alterar | Publicar na fila genérica, escolhendo delivery ou recovery pelo `mode`. |
| Migrations/templates de notificação | Novos | Criar template Twig de e-mail, template Meta e correlações de recovery; ambos recebem o link `/rdc?cod={order}`. |

> Atenção: os senders atuais têm retry interno. A regra “sem retry” exige um
> sinal explícito na mensagem de recovery ou tratamento dedicado com máximo de
> uma tentativa; simplesmente não reenfileirar o dispatch não basta.

### `dashboard-seller` — restrições/feature flag

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `includes/user_functions.php` | Alterar | Criar permissão específica de gestão de recovery, exclusiva para permissões 1 e 2. |
| `actions/admin/user/restrictions.php` | Alterar ou nova ação dedicada | Gravar o override de ativação em `user_system_vars`, sem adicionar coluna em `tbl_usuarios`. |
| `views/dashboard/admin/seller_overview/_components/restrictions_modal.php` | Alterar | Adicionar toggle “Permitir recuperação de venda”. |
| `views/dashboard/admin/users/_components/modal_restrictions.php` | Alterar | Adicionar o mesmo toggle na lista administrativa de usuários. |
| `api/admin/users/list.php` | Alterar | Passar o estado efetivo da nova restrição ao modal. |

Chaves sugeridas:

```text
system_vars.sale_recovery_feature_enabled = 0
user_system_vars.sale_recovery_feature_enabled = 0 | 1
```

O resolvedor usa override do usuário e fallback global. Sem override e com
padrão `0`, ninguém tem acesso. A autorização deve ser verificada no backend ao
ler/salvar a regra e novamente antes de criar/enviar dispatch. Para venda de
afiliado, verificar o afiliado responsável; para venda própria, verificar o
produtor.

### `dashboard-seller` — histórico de venda

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `sale_detail.php` e seus componentes | Alterar | Exibir timeline de recovery somente quando `owner_user_id` for o usuário atual. Assim produtor não vê recovery criado pelo afiliado. |
| `admin_sale_detail.php` e componentes de detalhe | Alterar | Sempre exibir a timeline, identificando produtor/afiliado responsável. |
| API/serviço de detalhes de venda | Alterar ou criar | Retornar dispatches/eventos com filtro de visibilidade no seller e sem esse filtro para admin autorizado. |

## Critérios de aceite

- [ ] O item usado para recuperar venda é sempre o de `item_type = principal`.
- [ ] Cada canal de cada stage registra `sent_to_provider` e recebe atualizações do webhook na timeline da recovery.
- [ ] Nenhuma mensagem de recovery sofre retry ou fallback automático.
- [ ] Recovery de afiliado aparece apenas para o afiliado em `sale_detail`; aparece para admin em `admin_sale_detail`.
- [ ] Usuários sem feature flag efetiva não veem, não salvam, não agendam e não enviam recovery.
- [ ] Por padrão, nenhum usuário possui a feature habilitada.
