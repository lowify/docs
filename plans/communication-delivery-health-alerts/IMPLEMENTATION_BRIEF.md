# Brief de implementação — Alertas operacionais de entregas

> Feature: alertas de saúde de envio
> Status: pronto para desenvolvimento
> Data: 2026-10-01
> Fora de escopo: bloquear envios, Evolution, SMS, push e créditos internos de comunicação.

## Resultado esperado

O sistema detecta cinco falhas consecutivas nos últimos cinco envios relevantes, abre um incidente por categoria, ativa uma `system_var` global e avisa todos os administradores por notificação interna. Enquanto o incidente estiver ativo, a mesma categoria gera no máximo uma nova notificação a cada dez minutos.

O Dashboard Seller mostra um banner vermelho e genérico para administradores. O botão **Resolvido** reconhece todos os incidentes ativos, desliga a sysvar e remove o banner. Uma mesma sequência histórica não pode reabrir o alerta após esse reconhecimento; apenas uma falha nova pode fazê-lo.

## Regras fechadas

| ID | Regra | Universo consultado | Dispara quando |
| --- | --- | --- | --- |
| `whatsapp_meta_provider_failure` | Provedor WhatsApp Meta | os cinco registros terminais mais recentes de `whatsapp_meta` | os cinco têm `status = failed` |
| `whatsapp_template_failure:{template_id}` | Template WhatsApp Meta | os cinco registros terminais mais recentes do mesmo `template_id` em `whatsapp_meta` | os cinco falharam (`status = failed` ou `delivery_status = FAILED`) |
| `email_provider_failure:{provider}` | Provedor de e-mail | os cinco registros terminais mais recentes do mesmo `provider` em `email_single` | os cinco falharam (`status = failed` ou `delivery_status = FAILED`) |
| `email_template_failure:{template_id}` | Template de e-mail | os cinco registros terminais mais recentes do mesmo `template_id` em `email_single` | os cinco falharam (`status = failed` ou `delivery_status = FAILED`) |

Definições obrigatórias:

- Registro terminal: `status` igual a `success` ou `failed`. Não incluir `pending`, `attempting`, `skipped`, nulo ou outros estados transitórios.
- Falha para template: `status = failed` **ou** `delivery_status = FAILED`.
- Falha para o provedor Meta: apenas `status = failed`. Isso evita classificar falhas individuais de entrega pós-aceite como indisponibilidade global do provedor.
- Falha para o provedor de e-mail: `status = failed` **ou** `delivery_status = FAILED`. A população nunca mistura provedores: `provider` vazio/nulo deve ser agrupado como `unknown`, sem ser combinado com SendGrid, Mailtrap ou outro provedor nomeado.
- Cinco falhas consecutivas: os cinco registros mais recentes da população da regra são falhas. Um sucesso entre esses cinco impede a abertura.
- A avaliação deve executar a cada minuto. O cooldown de notificação é de dez minutos e não muda a frequência de avaliação.
- O escopo de “provedor WhatsApp” é exclusivamente `whatsapp_meta`; não incluir Evolution.

## Configuração por ambiente

O limiar padrão é cinco, mas cada regra precisa aceitar override independente por variável de ambiente em `services-notification`. Não incluir valores reais de ambiente em commit; registrar apenas os nomes no `.env.example`/documentação de configuração conforme o padrão do repositório.

| Variável | Regra controlada | Padrão quando ausente ou inválida |
| --- | --- | --- |
| `DELIVERY_HEALTH_WHATSAPP_META_PROVIDER_FAILURE_THRESHOLD` | Provedor WhatsApp Meta | `5` |
| `DELIVERY_HEALTH_WHATSAPP_TEMPLATE_FAILURE_THRESHOLD` | Template WhatsApp Meta | `5` |
| `DELIVERY_HEALTH_EMAIL_PROVIDER_FAILURE_THRESHOLD` | Provedor de e-mail | `5` |
| `DELIVERY_HEALTH_EMAIL_TEMPLATE_FAILURE_THRESHOLD` | Template de e-mail | `5` |
| `DELIVERY_HEALTH_NOTIFICATION_COOLDOWN_MINUTES` | Intervalo mínimo para uma nova notificação da mesma categoria ativa | `10` |

Normalização obrigatória: aceitar somente inteiro maior ou igual a `1`. String vazia, valor não numérico, zero e número negativo devem cair no padrão: `5` para os limiares e `10` para o cooldown. O processo deve carregar as variáveis pela configuração do serviço, não por leitura direta de `$_ENV` espalhada no domínio. Converter o cooldown para segundos internamente apenas no ponto de comparação. Os testes precisam cobrir os cinco overrides e o fallback.

## Desempenho das consultas

**Não consultar todos os templates ou provedores a cada minuto.** Isso seria uma varredura crescente e pode ficar caro. O processo deve trabalhar de forma incremental, com uma única instância (`nums = 1`) e cursor seguro por tabela em Redis, ordenado pelo par `(updated_at, id)`.

Em cada ciclo de um minuto, buscar no máximo um lote paginado de registros alterados desde o cursor, em ordem de `(updated_at, id)`. Do lote, deduplicar somente as categorias afetadas: uma categoria global de Meta quando houver mudança em `whatsapp_meta`, os `template_id` de WhatsApp alterados, e os pares `provider`/`template_id` de e-mail alterados. Avançar o cursor somente depois de concluir o lote; em reinício ou perda do cursor, iniciar em `agora - 5 minutos` e processar em lotes, sem consulta sem limite ao histórico completo.

Para cada categoria afetada, executar uma consulta indexada que lê **somente os últimos N registros da própria categoria**, ordenados por `updated_at DESC, id DESC`, com `LIMIT N`. Avaliar os estados retornados em memória. A consulta não pode filtrar `status = failed` antes do `LIMIT`: um sucesso entre os últimos N precisa impedir o strike. A categoria global do Meta usa os últimos N de `whatsapp_meta`; templates/provedores usam os últimos N do seu grupo.

Criar, após confirmar os índices existentes, os índices compostos necessários para esse plano:

| Tabela | Índice necessário | Uso |
| --- | --- | --- |
| `whatsapp_meta` | `(updated_at, id)` | paginação incremental de mudanças e categoria global Meta. |
| `whatsapp_meta` | `(template_id, updated_at, id)` | últimos N por template WhatsApp. |
| `email_single` | `(updated_at, id)` | paginação incremental de mudanças. |
| `email_single` | `(provider, updated_at, id)` | últimos N por provedor de e-mail; `NULL` é tratado como `unknown`. |
| `email_single` | `(template_id, updated_at, id)` | últimos N por template de e-mail. |

O tamanho do lote deve ser uma constante configurada do processo, com padrão conservador de `500` registros. Se houver mais alterações, o cursor mantém o restante para os ciclos seguintes. O processo deve registrar métricas/telemetria de duração, tamanho de lote, atraso do cursor e quantidade de categorias avaliadas; se o atraso crescer continuamente, isso é sinal para ajustar capacidade, não para remover os limites das consultas.

## Fluxo

```text
Processo Notification (a cada 1 min; 1 instância)
  -> lê um lote de até 500 mudanças desde o cursor Redis
  -> deduplica apenas as categorias afetadas no lote
  -> para cada categoria, lê os últimos N envios via índice (N vem da regra/env; padrão 5)
  -> últimos N envios são todos falha?
       não: não abre incidente
       sim: se a categoria ainda não foi registrada no ciclo ativo,
            grava um único log simplificado de incidente
            -> chama HTTP interno do services-account para ativar system_var global = 1
  -> enquanto a sysvar estiver ativa, Redis limita a publicação in-app
     da mesma categoria ao cooldown configurado

Admin no Dashboard
  -> CommunicationDeliveryMaintenanceService consulta a sysvar local
  -> active = 1: exibe banner vermelho
  -> confirmação de Resolvido chama API local do Dashboard
       -> service local desativa a sysvar e registra o horário de reconhecimento
       -> banner some

Próxima avaliação
  -> ignora mensagens até a marca d’água de resolução da categoria
  -> somente falha nova pode reabrir o incidente
```

## Dados e migrations

### `system_vars`

Inserir/upsert seguro da chave global abaixo. O valor é texto porque segue o padrão atual da tabela.

O `services-notification` **não acessa essa tabela diretamente**. Ao detectar uma categoria, ele chama o endpoint HTTP interno do `services-account`, que usa `SystemVarService` para fazer o upsert das chaves. O Dashboard Seller continua sendo uma exceção deliberada: para exibir e reconhecer o alerta, seu service local lê e escreve diretamente no banco compartilhado.

| `var_key` | Valor padrão | Uso |
| --- | --- | --- |
| `communication_delivery_maintenance_active` | `'0'` | Banner global e estado público aos admins. |
| `communication_delivery_maintenance_started_at` | vazio | Início do ciclo ativo; permite gravar apenas um log por categoria no ciclo. |
| `communication_delivery_maintenance_resolved_at` | vazio | Marca d’água global para impedir que os mesmos envios históricos reativem o alerta. |

### Nova tabela em `services-notification`: `delivery_health_logs`

Criar nova migration; não editar migrations existentes.

| Coluna | Tipo sugerido | Regra |
| --- | --- | --- |
| `id` | bigint PK | padrão do serviço |
| `category` | varchar(150) | categoria determinística |
| `service` | varchar(50) | `whatsapp_meta` ou `email_single` |
| `provider` | varchar(100) nullable | Meta ou provedor de e-mail, quando aplicável |
| `template_id` | bigint nullable | nulo para falha de provedor |
| `template_name` | varchar(255) nullable | snapshot, quando aplicável |
| `detected_at` | datetime | data/hora da primeira detecção do ciclo |
| `created_at`, `updated_at` | datetime | padrão do serviço |

Não persistir mensagem de erro, hash/assinatura de erro, contador, último envio analisado, `last_notified_at`, status de incidente nem uma linha nova a cada reavaliação. A tabela é um log mínimo: “nesta data, o serviço/provedor/template entrou em falha recorrente”.

Índice do log: `category, detected_at`. Os índices das tabelas de envio são os definidos em [Desempenho das consultas](#desempenho-das-consultas); antes de criar a migration, confirmar se algum equivalente já existe para não duplicá-lo.

### Reabertura após “Resolvido”

Ao resolver, `CommunicationDeliveryMaintenanceService` grava `communication_delivery_maintenance_resolved_at`. Nas avaliações seguintes, a regra só pode reativar o modo se a população contiver ao menos um envio atualizado após esse horário. Isso impede o loop de reabrir imediatamente com os mesmos cinco erros históricos, sem exigir estado detalhado na tabela de log.

## Classificação e conteúdo seguro

Reutilizar a classificação já presente em `WhatsappMetaOperationalAlertProcess` para os erros do Meta:

- `131042`: método de pagamento da conta WhatsApp Meta;
- template pausado;
- timeout (`curl error 28` / timeout);
- falha de conexão (`curl error 7` / Graph API);
- fallback: falha interna recorrente da Meta.

Para cada template, o rótulo deve conter canal e nome do template. Não incluir telefone, e-mail, payload, URL, conteúdo de mensagem, parâmetros nem a mensagem bruta do provedor. Usar somente a assinatura hash e um rótulo normalizado.

## Notificação interna

Reutilizar integralmente a infraestrutura existente:

```text
fila: notifications:in_app:create
processo: InAppNotificationStreamProcess
destino: [{ "type": "admin" }]
```

Criar templates em `in_app_notifications_template`:

| `template_code` | Severidade | Categoria | Mensagem |
| --- | --- | --- | --- |
| `delivery_health_whatsapp_provider_failure` | `critical` | `delivery_health` | Últimos 5 envios pelo WhatsApp Meta falharam. Categoria: `{{ error_label }}`. |
| `delivery_health_whatsapp_template_failure` | `critical` | `delivery_health` | Últimos 5 envios do template WhatsApp `{{ template_name }}` falharam. |
| `delivery_health_email_provider_failure` | `critical` | `delivery_health` | Últimos 5 envios pelo provedor de e-mail `{{ provider }}` falharam. |
| `delivery_health_email_template_failure` | `critical` | `delivery_health` | Últimos 5 envios do template de e-mail `{{ template_name }}` falharam. |

Payload obrigatório na fila:

```json
{
  "template_code": "delivery_health_whatsapp_provider_failure",
  "targets": [{ "type": "admin" }],
  "data": {
    "category": "whatsapp_meta_provider_failure",
    "channel": "whatsapp_meta",
    "template_id": null,
    "template_name": null,
    "failure_count": 5,
    "error_label": "Falha recorrente no método de pagamento do WhatsApp",
    "detected_at": "ISO-8601"
  }
}
```

O cooldown de notificação não pertence ao log persistido. Usar chave Redis por categoria, por exemplo `notifications:delivery_health:cooldown:{category}`, com `SET NX EX` pelo total de segundos configurado. Se a publicação falhar, liberar a chave para permitir nova tentativa na próxima avaliação. Enquanto `communication_delivery_maintenance_active = '1'`, o processo continua avaliando e pode publicar novamente após o cooldown; a tabela não recebe novas linhas por essas repetições.

## Dashboard Seller: service local de manutenção

Toda leitura e escrita das `system_vars` desta feature no Dashboard deve ficar em um único service local, por exemplo `CommunicationDeliveryMaintenanceService`, apoiado em `SystemVarsService` e `SystemVarsModel`. Não distribuir consultas SQL de `system_vars`, nomes de chave ou conversões booleanas entre `header.php`, partials, APIs e JavaScript.

Contrato mínimo do service:

```php
isActive(): bool
resolve(): void
```

`resolve()` altera localmente, via PDO/`SystemVarsService`, `communication_delivery_maintenance_active = '0'` e `communication_delivery_maintenance_resolved_at` com o horário atual. A API local do Dashboard apenas autoriza o usuário, chama esse service e devolve `{ "active": false }`; ela não chama Gateway, Public API ou Notification. A ação é idempotente.

O processo em `services-notification` não lê nem escreve diretamente em `system_vars`: ele envia a data da detecção ao cliente HTTP interno de Account, e o Account aplica a marca d’água de reconhecimento antes de decidir se ativa o modo. Nenhum browser acessa essa tabela diretamente.

## Integração interna Notification → Account

Criar no `services-account` um endpoint **interno**, por exemplo `POST /internal/communication-delivery-maintenance/activate`, indisponível nas rotas públicas e protegido pelo mesmo mecanismo de confiança entre serviços já usado pelos endpoints internos. O contrato não recebe PII nem detalhes do erro; recebe somente `detected_at` em ISO-8601, para aplicar a marca d’água de reconhecimento.

O endpoint deve, de forma idempotente:

1. se `detected_at` não for posterior a `communication_delivery_maintenance_resolved_at`, devolver que a detecção foi ignorada, sem ativar nem criar novo ciclo;
2. caso contrário, fazer upsert de `communication_delivery_maintenance_active = '1'`;
3. preencher `communication_delivery_maintenance_started_at` somente quando iniciar um ciclo novo após uma resolução; e
4. devolver no envelope padrão do Account se a detecção foi aceita e o estado efetivo.

Em `services-notification`, acrescentar `activateCommunicationDeliveryMaintenance(DateTimeInterface $detectedAt)` a `AccountInternalService`, usando `InternalHttpClient` e o alias `account`. O avaliador só considera a abertura concluída quando o HTTP retornar sucesso com detecção aceita; se for ignorada pela marca d’água, não cria log nem notificação. Se o Account estiver indisponível ou responder erro, registrar erro técnico seguro e deixar a categoria elegível para nova tentativa; não criar uma notificação in-app que anuncie manutenção sem que a sysvar tenha sido ativada.

O Dashboard **não usa esse endpoint**: `CommunicationDeliveryMaintenanceService::resolve()` mantém a atualização local via PDO/`SystemVarsService`, conforme a decisão desta feature.

## Dashboard Seller

### Banner

**Não criar uma segunda faixa de alerta.** Reutilizar o mesmo fluxo do banner de cadastro incompleto: `TopNoticeService` → `dashboardResolveTopNotice()` → `views/partials/top_notice_bar.php`, já renderizado antes do `header.php` e já responsável pelo offset do cabeçalho sticky.

Adicionar uma definição/candidato `communication-delivery-maintenance` ao `TopNoticeService`, alimentada exclusivamente por `CommunicationDeliveryMaintenanceService`. Requisitos:

- renderizar exclusivamente para administradores com `admin_service_status`;
- prioridade maior que todo aviso existente; usar `priority: 1000` (os avisos atuais mais altos usam `100`). Quando estiver ativo, ele é o único `top-notice` visível, inclusive acima do banner de cadastro incompleto;
- não ser dispensável pelo botão `x` nem pela sessão. O alerta sai exclusivamente após a confirmação bem-sucedida de `Resolvido` ou quando o estado global deixar de estar ativo;
- estado ativo: banner vermelho, texto `Há falhas recorrentes nos envios. Verifique o Status de serviços.`, link para `/services_status.php` e botão `Resolvido`;
- renderizar dois botões pelos componentes base `Button`: **Detalhes** (link para `/services_status.php`, sem mutação) e **Resolvido** (abre o modal de confirmação);
- o botão **Detalhes** deve permanecer disponível mesmo quando o admin optar por cancelar o modal de resolução;
- o botão **Resolvido** não pode chamar a API diretamente: ele abre o modal base `Modal` de confirmação;
- no modal, usar `Button` para as ações `Cancelar` e `Sim, marcar como resolvido`; o último é do tipo `danger`, mostra estado de carregamento enquanto o `POST` está pendente e permanece desabilitado para evitar duplo envio;
- conteúdo obrigatório do modal: título `Marcar envios como resolvidos?` e explicação `Isso removerá o alerta e interromperá novas notificações deste incidente. Não corrige a falha no provedor nem reenvia mensagens.`;
- configurar o `Modal` com `backdropClose: false`, para que a ação de reconhecimento seja cancelada somente por `Cancelar` ou pelo botão de fechar;
- somente ao confirmar no modal, enviar `POST` para a API local do Dashboard; ela chama `CommunicationDeliveryMaintenanceService::resolve()`. Ao sucesso, fechar o modal e ocultar o banner;
- se a consulta falhar, ocultar o banner e registrar apenas erro técnico seguro; não bloquear a página;
- o botão reconhece o incidente, não corrige a Meta e não reenvia mensagens.

Evoluir o contrato da partial `top_notice_bar.php` para aceitar uma lista de ações, preservando compatibilidade com a chave `button` dos avisos atuais. O novo aviso usa `buttons` com `Detalhes` e `Resolvido`; os avisos existentes não devem mudar de aparência ou comportamento. Renderizar o `Modal` de confirmação uma única vez no fluxo compartilhado do top notice, com ID exclusivo, para evitar duplicação em páginas que incluem o header.

### Clique em notificação

Em `dashboard-seller/app/services/InAppNotificationService.php`, incluir os quatro `template_code`s no resolvedor de rota. Para usuário com `admin_service_status`, todos devem retornar:

```text
/services_status.php
```

Para usuário sem a permissão, retornar `null`. O fluxo atual de leitura da notificação deve permanecer intacto.

## Mapa de alteração esperado

| Repositório | Arquivos/pontos a criar ou evoluir |
| --- | --- |
| `services-notification` | Migration de `delivery_health_logs`; model/repository de log mínimo; service/processo de avaliação das regras Meta, e-mail por provedor e templates; cliente `AccountInternalService` para ativação HTTP; configuração em `config/autoload/processes.php`; templates in-app; testes unitários e de processo. |
| `services-account` | Endpoint interno idempotente de ativação, use case/service apoiado em `SystemVarService`, rota interna e testes de contrato/autorização entre serviços. |
| `dashboard-seller` | Novo `CommunicationDeliveryMaintenanceService` para as sysvars; evolução do `TopNoticeService` e de `views/partials/top_notice_bar.php`; modal/ações base no layout compartilhado; API local de resolução sob `api/dashboard/`; rota dos novos templates no `app/services/InAppNotificationService.php`; testes/manuais de prioridade e permissão. |

Não há alteração planejada em `edge-gateway` nem `edge-public-api`. A ativação ocorre por HTTP interno de Notification para Account; o Dashboard mantém a leitura e a resolução local pela tabela global `system_vars`.

## Ordem obrigatória de desenvolvimento

1. Inspecionar migrations e índices existentes de `whatsapp_meta`, `email_single`, templates e `system_vars`.
2. Entregar migration/model/repositório do log mínimo e os quatro templates in-app.
3. Implementar no Account o endpoint interno idempotente de ativação e seu teste de contrato.
4. Implementar o avaliador com consultas determinísticas, marca d’água global, ativação HTTP no Account, cooldown Redis e testes unitários.
5. Implementar `CommunicationDeliveryMaintenanceService`, a API local de resolução e o banner no Dashboard.
6. Implementar o roteamento da notificação no Dashboard.
7. Validar o fluxo Notification → HTTP interno Account → `system_vars` e Dashboard local → `system_vars`, e atualizar o mapa da feature `docs/features/sale-notifications/` quando a implementação estiver confirmada.

## Critérios de aceite verificáveis

1. Com o valor padrão, cinco `whatsapp_meta.status = failed` consecutivos abrem `whatsapp_meta_provider_failure`, chamam com sucesso o endpoint interno do Account que põe a sysvar em `'1'` e criam uma notificação para `admin`.
2. Quatro falhas e um sucesso nos últimos cinco não ativam incidente.
3. Cinco falhas de um template WhatsApp ativam somente a categoria daquele template; cinco falhas de outro template criam categoria independente.
4. Cinco falhas do mesmo provedor de e-mail ativam a categoria daquele provedor; provedores diferentes não se misturam.
5. Cinco falhas de um template de e-mail ativam a categoria de e-mail e não interferem nas regras de provedor.
6. A primeira detecção da categoria no ciclo ativo persiste exatamente uma linha em `delivery_health_logs`; reavaliações e notificações repetidas não inserem nem atualizam esse log.
7. Com o padrão, após a primeira notificação, reavaliar antes de dez minutos não cria outra para a mesma categoria; após dez minutos, com a condição ainda positiva, cria uma nova, sem criar novo log persistido.
8. Cada nova categoria ativa mantém a sysvar em `'1'`; `CommunicationDeliveryMaintenanceService::resolve()` é o único caminho do Dashboard que a coloca em `'0'`.
9. Após `Resolvido`, os mesmos cinco envios históricos não reabrem alerta. Uma falha atualizada após `communication_delivery_maintenance_resolved_at` pode reabrir quando a regra voltar a ser satisfeita.
10. O banner aparece para perfis 1, 2 e 4, não aparece para seller/perfil 3, e desaparece após resposta bem-sucedida de resolução.
11. Com o estado de manutenção ativo, o mesmo espaço do `top_notice_bar` exibe somente o aviso de falha de envios; ele tem prioridade `1000` e substitui temporariamente o banner de cadastro incompleto e qualquer outro top notice elegível.
12. O banner contém **Detalhes**, que abre `/services_status.php` sem alterar o incidente.
13. **Resolvido** abre o `Modal` base; cancelar, fechar ou clicar fora não deve chamar o endpoint, e confirmar chama o endpoint uma única vez.
14. A notificação de cada categoria abre `/services_status.php` para admin autorizado.
15. Nenhuma tela, payload novo de notificação ou log novo inclui PII, conteúdo da mensagem ou parâmetros de entrega.
16. Cada uma das quatro variáveis de limiar altera somente sua regra correspondente; variáveis ausentes, inválidas ou menores que `1` usam o limiar padrão `5`.
17. Falha ou indisponibilidade do HTTP interno para Account não ativa a sysvar, não publica a notificação in-app e deixa a abertura elegível para retentativa segura.
17. `DELIVERY_HEALTH_NOTIFICATION_COOLDOWN_MINUTES` altera o intervalo de repetição de todas as categorias; valor ausente, inválido ou menor que `1` usa `10` minutos.

## Referências de código confirmadas

- `services-notification/app/Process/WhatsappMetaOperationalAlertProcess.php`
- `services-notification/app/Model/WhatsappMeta.php`
- `services-notification/app/Model/EmailSingle.php`
- `services-notification/app/Process/InAppNotificationStreamProcess.php`
- `services-notification/app/Service/RegisterInAppNotificationEvent.php`
- `services-notification/app/Domain/InAppNotification/Repository/InAppNotificationRepository.php`
- `services-notification/app/UseCase/DeliveryStatus/GetDeliveryStatusUseCase.php`
- `dashboard-seller/header.php`
- `dashboard-seller/app/services/TopNoticeService.php`
- `dashboard-seller/views/partials/top_notice_bar.php`
- `dashboard-seller/app/services/InAppNotificationService.php`
- `dashboard-seller/services_status.php`
