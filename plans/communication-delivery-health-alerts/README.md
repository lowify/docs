# Plano — Alertas operacionais de entregas

> Status: planejado
> Atualizado em: 2026-10-01
> Escopo: documentação local; não publicado.

O [brief de implementação](IMPLEMENTATION_BRIEF.md) é a fonte de verdade detalhada para o desenvolvimento. Este README resume o mesmo desenho.

## Objetivo

Detectar falhas recorrentes de envio, avisar administradores por notificação interna e mostrar um alerta prioritário no Dashboard Seller. O alerta não bloqueia envios, não reenvia mensagens e não corrige o provedor; ele sinaliza e permite reconhecimento operacional.

## Regras de detecção

Cada regra avalia os últimos `N` envios terminais da própria população. O incidente ocorre apenas se todos os `N` forem falhas; um sucesso entre eles impede a abertura.

| Categoria | População |
| --- | --- |
| Provedor WhatsApp Meta | `whatsapp_meta` |
| Template WhatsApp Meta | `whatsapp_meta` do mesmo `template_id` |
| Provedor de e-mail | `email_single` do mesmo `provider` |
| Template de e-mail | `email_single` do mesmo `template_id` |

Estados pendentes, em tentativa, `skipped` ou não terminais não participam. Para template e provedor de e-mail, contam `status = failed` e `delivery_status = FAILED`. Para o provedor Meta, conta apenas `status = failed`.

## Consultas e escala

O processo roda a cada minuto em uma única instância, mas não varre todas as mensagens, templates ou provedores. Ele pagina até 500 alterações desde um cursor Redis por tabela, deduplica as categorias afetadas e consulta apenas os últimos N registros de cada uma, usando índices compostos por `updated_at`/`id`, template e provedor. Um sucesso entre os últimos N impede o alerta; por isso o filtro de falha é aplicado depois do `LIMIT`.

Em reinício sem cursor, ele retoma uma janela limitada dos últimos cinco minutos e continua em lotes. O brief define os índices obrigatórios e métricas de atraso do cursor.

## Configuração por ambiente

No `services-notification`, todas as regras têm padrão `5` e aceitam override individual:

- `DELIVERY_HEALTH_WHATSAPP_META_PROVIDER_FAILURE_THRESHOLD`
- `DELIVERY_HEALTH_WHATSAPP_TEMPLATE_FAILURE_THRESHOLD`
- `DELIVERY_HEALTH_EMAIL_PROVIDER_FAILURE_THRESHOLD`
- `DELIVERY_HEALTH_EMAIL_TEMPLATE_FAILURE_THRESHOLD`

O intervalo entre notificações repetidas da mesma categoria é controlado por `DELIVERY_HEALTH_NOTIFICATION_COOLDOWN_MINUTES`, com padrão `10`. Variáveis ausentes, inválidas ou menores que `1` usam os valores padrão.

## Persistência e notificações

`services-notification` criará `delivery_health_logs` como um log mínimo de abertura: categoria, serviço, provedor, template quando aplicável e data de detecção. Não persistirá a mensagem de erro, assinatura, contador, estado de incidente, cooldown ou redetecções.

Durante o ciclo ativo, cada categoria gera somente um log. O cooldown de novas notificações internas é controlado no Redis por categoria. As notificações internas usam o destino `admin`, explicam a categoria e levam para `services_status.php`.

## Sysvars e reconhecimento

As chaves globais são:

- `communication_delivery_maintenance_active`
- `communication_delivery_maintenance_started_at`
- `communication_delivery_maintenance_resolved_at`

Ao detectar a falha, o processo de Notification chama um endpoint HTTP **interno** no `services-account`, que ativa as sysvars via `SystemVarService`; ele não escreve diretamente nessa tabela. No Dashboard, toda a manipulação dessas chaves fica no service local `CommunicationDeliveryMaintenanceService`, via PDO, `SystemVarsModel` e `SystemVarsService`. Para consultar ou resolver o alerta, o Dashboard não chama Gateway, Public API nem Notification.

Ao confirmar **Resolvido**, o service local desativa a chave ativa e grava a marca d’água de reconhecimento. A mesma sequência histórica não deve reativar o modo; uma nova falha posterior ao reconhecimento pode reabri-lo.

## Dashboard Seller

O aviso reutiliza o mesmo `TopNoticeService` e `top_notice_bar.php` do banner de cadastro incompleto. Ele tem prioridade `1000`, portanto substitui temporariamente qualquer outro top notice enquanto estiver ativo.

O banner aparece somente para administradores com `admin_service_status` e contém:

- **Detalhes**: abre `services_status.php` sem alterar o incidente.
- **Resolvido**: abre confirmação com os componentes base `Modal` e `Button`; somente a confirmação positiva chama a API local do Dashboard, que executa o service local.

O banner não pode ser dispensado pelo `x` ou pela sessão.

## Componentes envolvidos

| Componente | Responsabilidade |
| --- | --- |
| `services-notification` | Avaliação recorrente, log mínimo, cooldown Redis, ativação HTTP interna no Account e notificações internas. |
| `services-account` | Endpoint interno idempotente que ativa as sysvars com `SystemVarService`. |
| `dashboard-seller` | Service local das sysvars, top notice prioritário, modal de confirmação e rota das notificações. |

## Referências confirmadas

- `services-notification/app/Process/WhatsappMetaOperationalAlertProcess.php`
- `services-notification/app/Model/WhatsappMeta.php`
- `services-notification/app/Model/EmailSingle.php`
- `services-notification/app/Process/InAppNotificationStreamProcess.php`
- `services-notification/app/Service/RegisterInAppNotificationEvent.php`
- `services-notification/app/Service/Internal/AccountInternalService.php`
- `services-notification/app/Service/Internal/InternalHttpClient.php`
- `services-account/app/Domain/SystemVar/Service/SystemVarService.php`
- `services-account/config/routes.php`
- `dashboard-seller/app/models/SystemVarsModel.php`
- `dashboard-seller/app/services/SystemVarsService.php`
- `dashboard-seller/app/services/TopNoticeService.php`
- `dashboard-seller/views/partials/top_notice_bar.php`
- `dashboard-seller/app/services/InAppNotificationService.php`
- `dashboard-seller/services_status.php`
