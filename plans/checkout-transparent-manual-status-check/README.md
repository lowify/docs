# Planejamento — Consulta manual de status no Checkout Transparente

## Objetivo

Permitir que o suporte solicite uma consulta pontual de uma venda pendente ao gateway de pagamento e acompanhe, na propria tela, o resultado daquela consulta assincrona.

A funcionalidade nao aprova uma venda manualmente. Quando o gateway retornar pagamento confirmado, a confirmacao usa o fluxo normal do checkout transparente.

## Escopo

- Tela unica: `dashboard-seller/admin_sale_detail.php`.
- Elegivel somente quando a venda:
  - pertencer ao Checkout Transparente;
  - estiver com status legado `pending`;
  - tiver charge consultavel no Checkout Transparente, com `gateway_charge_id` e gateway com suporte a polling.
- Perfis permitidos: `1`, `2` e `4`.
- Fora do escopo: pagina do seller, aprovacao manual da venda, reconsulta automatica pelo navegador e exposicao de payload bruto do gateway.

## Principios

1. **Consulta verificavel, nao aprovacao manual.** A equipe solicita uma consulta; somente a resposta do gateway pode confirmar a charge.
2. **Rastreabilidade por solicitacao.** Cada consulta efetivamente enviada cria um registro proprio, associado ao usuario que a solicitou e a um UUID publico.
3. **Uma consulta ativa por charge.** Reutilizar uma solicitacao pendente evita duplicidade e pressao indevida no gateway.
4. **Reuso seguro de resultado recente.** Um resultado com menos de um minuto e mostrado antes de oferecer nova consulta.
5. **Defesa em profundidade.** Elegibilidade e permissao sao verificadas no dashboard, no edge publico e na API do checkout.
6. **Polling proporcional ao risco.** Gateways com webhook confiavel usam reconciliacao economica; gateways que dependem de polling recebem uma cadencia intensiva.

## Nova politica de polling

Esta entrega tambem substitui a politica unica de polling por perfis configurados por gateway e amplia o TTL padrao inicial das charges para **6 horas**. A extensao para 12 horas fica fora desta primeira etapa e depende da analise dos resultados operacionais da janela de 6 horas.

O relatorio de [fontes de confirmacao](../checkout-transparent-confirmation-sources/README.md) sustenta a separacao: no recorte consultado, 98,31% das confirmacoes vieram por webhook. Woovi, Mercado Pago e Efibank tiveram entre 1,11% e 2,58% de confirmacoes por polling; RisePay foi a excecao, com 86,05% por polling.

### Perfis

| Idade da charge | Perfil economico — webhook confiavel | Perfil intensivo — polling relevante |
| --- | ---: | ---: |
| 0–2 min | A cada 1 min | A cada 1 min |
| 2–10 min | A cada 5 min | A cada 1 min |
| 10–30 min | A cada 10 min | A cada 5 min |
| 30–60 min | A cada 30 min | A cada 10 min |
| 1–2 h | A cada 30 min | A cada 15 min |
| 2–6 h | A cada 30 min | A cada 30 min |
| Ao vencer em 6 h | Uma consulta final; expirar se nao houver pagamento | Uma consulta final; expirar se nao houver pagamento |

Os intervalos sao sempre calculados pela idade da charge e pela ultima consulta registrada. Assim, a politica reutiliza o mecanismo atual de `ultima consulta + intervalo`; nao ha a regra ambigua de “uma vez por faixa”.

Classificacao inicial sugerida:

| Perfil | Gateways iniciais |
| --- | --- |
| Economico | Woovi, Mercado Pago e Efibank |
| Intensivo | RisePay e qualquer gateway sem webhook confiavel ou em degradacao operacional |

A classificacao deve ficar no catalogo `integration_gateways`, e nao em condicionais fixas no codigo. Criar a coluna `has_reliable_webhook` (`boolean`, `not null`, `default false`) para registrar que o webhook de um gateway foi validado operacionalmente como fonte confiavel de confirmacao.

Essa coluna tem semantica diferente das flags existentes:

| Campo | Significado |
| --- | --- |
| `supports_webhook` | O provider oferece webhook tecnicamente. |
| `has_reliable_webhook` | O webhook foi aprovado como confiavel para ser a fonte primaria de confirmacao. |
| `supports_polling` | A API do provider permite consulta ativa de status. |

Decisao operacional:

| `supports_polling` | `has_reliable_webhook` | Polling |
| --- | --- | --- |
| `false` | qualquer valor | Desativado: o provider nao permite consulta ativa. |
| `true` | `true` | Mantido como reconciliacao, no perfil economico. Nao deve ser desligado apenas por haver webhook, pois ele cobre perda ou atraso de entrega. |
| `true` | `false` | Mantido ativo no perfil intensivo; e a fonte primaria ou de contingencia forte de confirmacao. |

O perfil pode ser derivado inicialmente dessa coluna (`true` = economico; `false` = intensivo). Se futuramente houver necessidade de excecao, uma configuracao explicita de `polling_profile` pode ser adicionada como override auditavel, mas nao faz parte do escopo inicial.

## Permissao

Adicionar a chave abaixo em `dashboard-seller/includes/user_functions.php` e usa-la na renderizacao e no endpoint AJAX do dashboard:

```php
'admin_checkout_transparent_manual_status_check' => [1, 2, 4],
```

No `edge-public-api`, as duas rotas administrativas tambem devem aceitar exclusivamente as permissoes `1`, `2` e `4` a partir do JWT. A API do checkout recebe o identificador do ator somente do edge autenticado por HMAC/Bearer; o navegador nunca informa esse identificador.

## Experiencia na tela

No card de detalhes do pagamento, para uma venda elegivel, mostrar o bloco **Consulta ao gateway**.

| Situacao ao carregar a tela ou acionar a consulta | Comportamento |
| --- | --- |
| Existe solicitacao `queued` ou `processing` | Mostrar que a consulta esta em andamento, assumir o UUID existente e iniciar polling do resultado. Nao criar outra solicitacao. |
| Ultima solicitacao foi concluida ou falhou ha menos de 1 minuto | Mostrar o resultado anterior e o alerta “Consulta ja realizada ha X segundos.” Nao criar nova solicitacao automaticamente. |
| Nao existe solicitacao recente | Mostrar o botao `Consultar gateway`. |

Depois de criar ou localizar uma solicitacao ativa, o navegador consulta o seu UUID a cada 2 segundos. Ele para quando receber `completed` ou `failed`, ou apos 60 segundos de espera visual. O timeout do navegador nao cria outra consulta; a tela informa que o processamento continua e permite atualizar a pagina.

O resultado apresentado deve conter apenas dados seguros: gateway, horario, status retornado/normalizado e mensagem operacional de erro quando houver. Nao mostrar credenciais, segredos de webhook, payload bruto do provedor ou dados sensiveis desnecessarios.

### Contrato de erros para o front

A API do checkout deve resolver erros conhecidos em um mapeamento unico, para que a tela nao replique regras especificas de cada gateway.

Quando o erro recebido ja estiver mapeado — por exemplo, `gateway_unavailable`, `invalid_credentials`, `account_not_allowed` ou `rate_limited` — a resposta da solicitacao inclui uma mensagem tratada, pronta para exibicao:

```json
{
  "status": "failed",
  "error": {
    "type": "gateway_unavailable",
    "mapped": true,
    "message": "O gateway esta indisponivel no momento. Tente novamente em alguns minutos."
  }
}
```

Quando nao houver mapeamento para o erro, a API nao inventa uma mensagem. Ela devolve somente a resposta sanitizada recebida do gateway, marcada como nao mapeada; o front a apresenta como detalhe tecnico da consulta:

```json
{
  "status": "failed",
  "error": {
    "mapped": false,
    "response": "resposta sanitizada do gateway"
  }
}
```

`response` nunca pode conter token, segredo, certificado, chave, dado pessoal desnecessario ou payload bruto nao sanitizado. O status HTTP, codigo e tipo original podem ser preservados quando forem seguros e uteis ao suporte.

### Tentar novamente

Depois de resultado, falha ou alerta de resultado recente, mostrar `Tentar novamente`.

O botao envia uma requisicao explicita com `force=true`:

- cria um novo registro e um novo UUID;
- ignora o reuso de resultado concluido em menos de um minuto;
- continua recusando a criacao se existir uma solicitacao `queued` ou `processing` para a mesma charge.

O botao normal `Consultar gateway` nao usa `force=true`.

## Contrato HTTP proposto

As rotas externas seguem o mesmo caminho atual: dashboard -> edge-gateway -> edge-public-api -> checkout-transparent-api.

| Metodo | Rota | Finalidade |
| --- | --- | --- |
| `POST` | `/checkout-transparent/admin/sales/{saleId}/status-checks` | Criar uma consulta, seguir uma ativa, ou iniciar tentativa forcada. |
| `GET` | `/checkout-transparent/admin/sales/{saleId}/status-checks/latest` | Obter a solicitacao ativa ou o ultimo resultado recente ao abrir a tela. |
| `GET` | `/checkout-transparent/admin/sales/{saleId}/status-checks/{uuid}` | Obter o estado e o resultado de uma solicitacao especifica. |

O dashboard tera endpoints AJAX internos equivalentes. O browser nao chama o gateway nem o checkout-transparent-api diretamente.

### Respostas esperadas

Nova consulta criada:

```json
{
  "action": "created",
  "request": {
    "uuid": "...",
    "status": "queued",
    "requested_at": "2026-10-28T12:00:00-03:00"
  }
}
```

Consulta ja ativa:

```json
{
  "action": "follow_existing",
  "request": {
    "uuid": "...",
    "status": "processing"
  }
}
```

Resultado recente reaproveitado:

```json
{
  "action": "recent_result",
  "retry_after_seconds": 38,
  "request": {
    "uuid": "...",
    "status": "completed",
    "gateway_status": "pending",
    "normalized_charge_status": "processing",
    "checked_at": "2026-10-28T11:59:38-03:00"
  }
}
```

## Persistencia

Reaproveitar a tabela existente `charge_status_checks`. Criar uma migration nova no `services-checkout-transparent-api` que adicione colunas anulaveis para suportar a solicitacao manual, sem alterar os registros de polling ja existentes.

| Campo | Finalidade |
| --- | --- |
| `id`, `charge_id`, `status`, `response_json`, `checked_at`, `created_at` | Campos existentes; `status` continua sendo o status normalizado retornado ou o ultimo status conhecido da charge. |
| `uuid` (`NULL`) | UUID publico acompanhado pelo front; unico quando preenchido. |
| `trigger` (`NULL`) | Origem do check, como `scheduler`, `webhook`, `expiration_guard` ou `admin_manual_status_check`. |
| `request_status` (`NULL`) | Ciclo da solicitacao manual: `queued`, `processing`, `completed` ou `failed`. |
| `requested_by_user_id` (`NULL`) | Usuario de suporte que iniciou a consulta. |
| `error` (`JSON NULL`) | Erro sanitizado; `response_json` permanece como resultado sanitizado. |
| `requested_at`, `completed_at`, `updated_at` (`NULL`) | Auditoria e calculo do reuso de um minuto. |

Para uma consulta manual, a API cria inicialmente uma linha com `trigger = admin_manual_status_check`, `request_status = queued`, UUID e ator. Quando o worker iniciar e terminar, atualiza a mesma linha para `processing`, depois `completed` ou `failed`. Os checks automaticos existentes permanecem validos, com as colunas novas em `NULL`.

Usar transacao e lock na charge ou nos checks manuais ativos para decidir entre reutilizar e criar. Assim, dois cliques simultaneos nao criam duas consultas.

## Fila e processamento

A API do checkout reutiliza `payment.status.check` e o worker existente. A nova solicitacao publica a instrucao com metadados suficientes para identificar sua origem:

```json
{
  "trigger": "admin_manual_status_check",
  "confirmation_source": "manual_polling",
  "manual_status_check_id": 123,
  "manual_status_check_uuid": "UUID"
}
```

O resultado retornado pelo worker conclui a linha de `charge_status_checks` identificada pelo ID/UUID, tanto para status nao terminal quanto para erro e pagamento confirmado. O consumidor atual de `payment.status.check.result` deve gravar essa conclusao inclusive no caminho `paid`, que hoje confirma a charge antes de registrar o historico comum de checks.

## Fonte de confirmacao

Incluir `manual_polling` em `charges.confirmation_source` por meio de uma nova migration e no enum `ChargeConfirmationSource`.

| Situacao | Fonte |
| --- | --- |
| Scheduler periodico | `polling` |
| Webhook validado | `webhook` |
| Aprovacao operacional direta | `manual` |
| Consulta solicitada pelo suporte e confirmada pelo gateway | `manual_polling` |

Quando a consulta manual retornar `paid`, o fluxo normal de confirmacao deve ser executado com `confirmation_source = manual_polling`. Isso deixa claro que o suporte nao marcou a venda como paga: ele iniciou uma consulta que o gateway confirmou.

Relatorios, filtros e a documentacao de fontes de confirmacao devem passar a considerar essa quarta origem separadamente do polling automatico.

## Componentes afetados

| Repositorio | Alteracoes previstas |
| --- | --- |
| `dashboard-seller` | Permissao, bloco visual em `admin_sale_detail`, endpoints AJAX e JavaScript de polling. |
| `edge-gateway` | Rotas de encaminhamento para criar e consultar solicitacoes. |
| `edge-public-api` | Rotas, use cases e autorizacao JWT para admin `1`, `2` e `4`; encaminhamento do ator autenticado. |
| `services-checkout-transparent-api` | Migrations, incluindo `has_reliable_webhook`; modelo/repositorio/use cases, rotas internas, publicacao da consulta, leitura de status, conclusao do resultado da fila, TTL de 6 horas e selecao de polling por perfil. |
| `services-checkout-transparent-worker` | Preservar os metadados da solicitacao na resposta, se isso ainda nao ocorrer de ponta a ponta. |
| `docs` | Atualizar relatorio/documentacao de fontes de confirmacao para `manual_polling`. |

## Criterios de aceite

1. Somente perfis `1`, `2` e `4` veem e executam a funcionalidade.
2. A acao aparece somente para venda CT pendente e charge consultavel.
3. Cada consulta enviada tem UUID proprio e registra o `requested_by_user_id`.
4. Uma consulta pendente e retomada automaticamente pela tela, mesmo apos recarregamento.
5. Resultado com menos de um minuto e reaproveitado com alerta e sem nova chamada ao gateway.
6. `Tentar novamente` cria novo registro e UUID, salvo se ja houver consulta ativa.
7. Resultado `paid` confirma pelo fluxo normal e fica marcado como `manual_polling`.
8. Nenhuma credencial ou payload sensivel do gateway chega ao navegador.
9. O historico permite identificar ator, charge, gateway, horario e resultado.
10. Charges novas recebem TTL padrao de 6 horas, exceto quando o gateway informar vencimento proprio.
11. Cada gateway usa somente um dos perfis de polling documentados, configurado no catalogo e auditavel.
12. A consulta final no vencimento ocorre antes de expirar uma charge ainda aberta e consultavel.
13. Erros mapeados entregam mensagem tratada ao front; erros nao mapeados entregam somente a resposta sanitizada do gateway.
14. `has_reliable_webhook` define se um gateway com polling usa o perfil economico ou intensivo; `supports_webhook` por si so nao e suficiente.

## Validacao

- Testes unitarios da decisao criar/reutilizar/forcar, da elegibilidade e da conclusao da solicitacao.
- Testes de autorizacao para permissoes permitidas e negadas em dashboard e edge publico.
- Testes de integracao da fila: `pending`, `paid`, `expired/canceled` e erro do gateway.
- Testes de interface: retomada de consulta pendente, alerta de resultado recente, polling encerrado e tentativa forcada.
- Testes do contrato de erros: mensagem tratada para erro mapeado e somente `response` sanitizada para erro nao mapeado.
- Testes da politica de polling para cada fronteira de idade, os dois perfis, o TTL de 6 horas e a consulta final de expiracao.
- Testes da classificacao por `supports_polling`, `supports_webhook` e `has_reliable_webhook`.
- Antes de promover a feature, criar e executar em homologacao um teste de compatibilidade que percorra dashboard/edge/API/fila/worker com uma charge de teste reversivel. A execucao na VPS depende de aprovacao explicita.
