# Caso de homologação — injeção controlada de falha de entrega

> Status: planejado; não executado.
> Objetivo: comprovar a abertura e a resolução de um incidente de saúde de entrega sem enviar mensagens reais.

## Cenário escolhido

Validar `whatsapp_meta_provider_failure`: cinco registros terminais consecutivos com `status = failed` devem abrir o incidente global da Meta.

O caso injeta registros sintéticos **já falhos** em `whatsapp_meta`. Não publica na stream de envio e, portanto, não chama a API da Meta, não contata telefone algum e não cria uma entrega real. O avaliador deve observar esses registros pelo cursor incremental normal.

## Pré-condições obrigatórias

1. Todos os componentes da feature devem estar publicados e saudáveis em homologação: `services-notification`, `services-account` e `dashboard-seller`.
2. A migration de `delivery_health_logs`, índices e templates in-app deve estar aplicada.
3. Confirmar que não existe incidente real ativo ou teste concorrente:
   - registrar os valores atuais das três `communication_delivery_maintenance_*` antes de qualquer alteração;
   - abortar se `communication_delivery_maintenance_active = '1'`, salvo autorização operacional explícita.
4. Usar um identificador exclusivo de execução, por exemplo `delivery-health-hml-YYYYMMDDHHMM`, e um template sintético com esse nome. Não reutilizar template, contato ou registros de execução anterior.
5. Aguardar a configuração de threshold padrão `5`, ou registrar explicitamente o override aplicado no ambiente. Não registrar valores secretos.
6. Ter acesso de administrador com `admin_service_status` para observar e resolver o banner.

## Preparação dos dados sintéticos

Criar ou reutilizar somente dentro da execução atual:

- um registro em `whatsapp_meta_templates` com nome igual ao identificador exclusivo;
- um contato sintético de tipo telefone, sem referência a cliente real;
- cinco registros em `whatsapp_meta`, todos com o mesmo `template_id`, `contact_id` sintético, `status = 'failed'`, `updated_at` posterior ao instante de resolução atual e horários crescentes.

Os campos `params` devem conter somente um objeto vazio. O campo `error` pode usar uma assinatura técnica inofensiva, por exemplo `delivery-health-homologation-timeout`; não incluir telefone, conteúdo de mensagem, URL, token ou payload real.

Não inserir os registros por filas de envio e não executar sender, webhook ou chamada à Meta como parte deste caso.

## Execução e evidências esperadas

1. Inserir e confirmar os cinco registros sintéticos.
2. Aguardar um ciclo do processo `delivery_health` (até 60 segundos), sem limpar o cursor Redis manualmente.
3. Coletar evidências seguras:

| Verificação | Resultado esperado |
| --- | --- |
| Log do processo | lote de `whatsapp_meta` com a categoria `whatsapp_meta_provider_failure` avaliada, sem erro técnico. |
| `system_vars` | `communication_delivery_maintenance_active = '1'` e `started_at` preenchido. |
| `delivery_health_logs` | exatamente uma linha da categoria, serviço `whatsapp_meta`, provider `meta`; nenhuma mensagem ou dado pessoal persistido. |
| Notificação in-app | uma notificação `delivery_health_whatsapp_provider_failure` com destino `admin`. |
| Dashboard | banner vermelho, com **Detalhes** e **Resolvido**, visível apenas para administrador com `admin_service_status`. |
| Permissão | perfil sem `admin_service_status` não recebe rota da notificação e não vê o banner. |

4. Clicar em **Detalhes** e confirmar que navega para `/services_status.php` sem alterar a sysvar.
5. Clicar em **Resolvido**, cancelar uma vez e confirmar que nada é alterado. Em seguida, confirmar a resolução:
   - `active` passa para `'0'`;
   - `resolved_at` é preenchido;
   - o banner desaparece.
6. Aguardar mais um ciclo sem inserir novos registros. Os mesmos cinco registros históricos não podem reabrir o incidente, não podem criar outro log e não podem gerar outra notificação.
7. Inserir um sexto registro sintético falho, com `updated_at` posterior a `resolved_at`. A categoria deve reabrir em um novo ciclo. Isso comprova a marca d’água de resolução.

## Reversão e limpeza

Depois de registrar as evidências, remover somente os artefatos cujo nome/identificador corresponda à execução atual:

1. notificações in-app e targets gerados pelo teste;
2. linhas de `delivery_health_logs` do identificador/categorias de teste;
3. registros `whatsapp_meta` sintéticos, tentativas relacionadas caso tenham sido criadas e o contato/template sintéticos;
4. chaves Redis de cursor e cooldown da categoria de teste, somente se identificadas pelo prefixo da feature;
5. restaurar exatamente os valores de `communication_delivery_maintenance_*` registrados antes do teste.

Nunca limpar filas, streams, chaves Redis genéricas, notificações de outros testes ou registros de usuários reais.

## Critérios de aprovação

O caso é aprovado somente se a abertura, a notificação, a visualização autorizada, a resolução, a não reabertura histórica e a reabertura por falha nova ocorrerem na ordem esperada. Qualquer divergência deve interromper a progressão para deploy e ser registrada com componente, etapa, evidência obtida e resultado esperado.
