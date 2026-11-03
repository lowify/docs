# Plano — Centralização de templates da recuperação de venda

> Status: planejado
>
> Escopo: somente RDC por WhatsApp Meta. Entrega pós-compra, e-mail, push e outros fluxos não fazem parte desta migração.
> Não inclui implementação, migration executável, deploy ou alteração de comportamento em produção.

## Decisão de arquitetura

`services-notification` será o único dono da escolha do template físico enviado
à Meta para recuperação de venda. Nenhum produtor externo — Commerce, HTTP,
stream Redis ou processo — informa nome ou ID de template.

O Commerce continua dono de elegibilidade, agendamento, destinatário, cobrança,
correlação e parâmetros da venda. Na fila, ele informa apenas a ação semântica
`sale_recovery`, fatos do payload necessários para a decisão e os parâmetros de
renderização.

```text
Commerce V2 → stream:notifications:whatsapp_meta
  action = sale_recovery
  context + params comerciais, sem template Meta

Notifications
  action + context → resolver em código escolhe um cenário conhecido
                   → vínculo do cenário → template principal
                   → persistência da mensagem e envio à Meta
```

Esta mesma regra vale para qualquer entrada HTTP futura: ela poderá solicitar a
ação `sale_recovery` autorizada, mas jamais escolher o template físico.

## Resultado esperado

Não existirá uma relação 1:1 entre `sale_recovery` e um único template default.
O Notifications manterá exatamente dois cenários iniciais de recuperação: estágio
1 com PIX e estágio 2 com PIX. Para uma mensagem com `pix_code`, um resolver
escrito no código devolve um `scenario_code` conhecido; o vínculo desse cenário
determina o template principal. Mensagens sem `pix_code` são ignoradas pelo
Notifications e não selecionam template. Os critérios não são configuráveis no
banco.

Exemplo conceitual:

| Pré-template/vínculo | Regra aplicada pelo resolver | Principal | Reserva |
| --- | --- | --- | --- |
| Recuperação 1 — com PIX | `stage=1` e `pix_code` presente | template X | template Y |
| Recuperação 2 — com PIX | `stage=2` e `pix_code` presente | template B | template C |

Os dois cenários são fechados para esta fase: estágio 1 ou 2 com `pix_code`
presente. PIX ausente não é cenário nem fallback: o Notifications ignora a
mensagem, sem criar mensagem Meta ou chamar o sender. Nenhum outro campo do
payload decide o template.

O único template mapeado e elegível nesta fase é `sale_recovering_ct_pix`. Ele
deve estar aprovado na Meta como template com CTA de solicitação de pagamento PIX.
Os nomes `sale_recovering_ct_pix_2` até `_8` não são tratados nem podem ser
selecionados: qualquer template sem mapping é ignorado como `skipped`, sem chamada
à Meta.

No Commerce, `payment_method` igual a `pix` ou `pix_automatic` exige `pix_code`:
sem código, o dispatch é marcado como `skipped` antes de enfileirar. Outros meios
de pagamento podem ser enfileirados sem código; nesse caso, o Notifications os
ignora. O Notifications não deve liberar um envio que Commerce tenha marcado como
inelegível.

## Contrato-alvo da fila

```json
{
  "version": 2,
  "action": "sale_recovery",
  "phone": "5511999999999",
  "context": {
    "stage": 1,
    "payment_state": "pending",
    "pix_code": "000201..."
  },
  "params": {
    "first_name": "...",
    "product_name": "...",
    "until": "...",
    "button_link": "...",
    "notification_outcome": { "...": "..." }
  }
}
```

| Campo | Responsabilidade |
| --- | --- |
| `version` | Versão do contrato; o novo envelope usa `2`. |
| `action` | Valor fechado: `sale_recovery`; não é nome de template. |
| `context` | Fatos de negócio usados pelo resolver em código para selecionar um cenário conhecido. Inclui o valor literal de `pix_code`, nunca o booleano derivado `has_pix_code`; não contém provider, nome ou ID Meta. |
| `params` | Dados autorizados para renderização e correlação/outcome. |
| template final | Resolvido somente pelo Notifications. |

O produtor envia `pix_code` literalmente, preservando o valor disponibilizado pela
venda. O contrato não cria nem aceita `has_pix_code`; o resolver trata o conteúdo
de `pix_code` conforme a regra do cenário. A representação de ausência (`null` ou
string vazia) deve ser única e definida no contrato antes da implementação. Quando
ausente, o Notifications encerra o consumo como ignorado, sem resolver vínculo.

### Mapping da família de templates PIX

O catálogo de mapping desta fase contém somente o template abaixo. Um template só
pode ser usado como principal ou reserva depois de possuir mapping explícito:

| Templates elegíveis |
| --- |
| `sale_recovering_ct_pix` |

| Elemento do template aprovado | Origem do valor no payload |
| --- | --- |
| Corpo `{{first_name}}` | Primeiro nome do cliente. |
| Corpo `{{product_name}}` | Título do item principal da venda. |
| Corpo `{{until}}` | Texto de urgência definido pelo resolver para cada estágio; deve ser obrigatório e explícito, sem valor implícito. |
| Botão URL dinâmico, índice `0` | `button_link`: token que substitui o `{{1}}` da URL aprovada. No fluxo atual, é o `order_id` usado como código da URL RDC. |
| Botão de solicitação de pagamento PIX, índice `1` | Valor literal de `pix_code`. |

O corpo segue este texto:

```text
Olá, {{first_name}}! O pagamento PIX do produto {{product_name}} ainda está pendente {{until}}

Finalize agora
```

### CTA URL e “Copiar código Pix”

Pela configuração aprovada mostrada, o template tem dois botões fixos. O sender
deve enviar ambos os componentes, respeitando seus índices:

```json
[
  {
    "type": "button",
    "sub_type": "url",
    "index": "0",
    "parameters": [{ "type": "text", "text": "<button_link>" }]
  },
  {
    "type": "button",
    "sub_type": "payment_request",
    "index": "1",
    "parameters": [
      {
        "type": "action",
        "action": {
          "payment_request": {
            "payment_setting": {
              "type": "pix_dynamic_code",
              "pix_dynamic_code": {
                "code": "<pix_code_literal_da_venda>"
              }
            }
          }
        }
      }
    ]
  }
]
```

O texto do botão é definido pelo tipo de CTA aprovado na Meta (“Copiar código
Pix” na interface localizada); não é um texto que o payload define. O sender atual
monta apenas o botão `url` para `button_link`, portanto esta migração prevê suporte
explícito ao `payment_request` no índice `1` e deve impedir que `pix_code` seja
serializado como parâmetro do corpo.

Não é possível abstrair/remover dinamicamente um botão de um template aprovado:
se o template possui CTA de pagamento PIX, o envio deve conter o `pix_dynamic_code`
exigido por ele. Logo, sem `pix_code`, o Notifications não chama a Meta; ele ignora
a mensagem antes da montagem dos componentes. Isso é uma inferência do contrato
de componente obrigatório documentado pela Meta e de uma implementação de API que
documenta erro quando o `code` do CTA está ausente ou o formato do botão está
incorreto. Fontes: [Payment Request CTA — Meta](https://developers.facebook.com/documentation/business-messaging/whatsapp/payments/payments-br/payment-request-cta) e [referência de envio com PIX dinâmico](https://academy.insiderone.com/v1/docs/send-conversational-whatsapp-pix-payment-template-message).

Antes de chamar a Meta, o Notifications valida que o template principal resolvido
possui mapping. Se ele for qualquer nome fora do catálogo — incluindo
`sale_recovering_ct_pix_2` até `_8` nesta fase — encerra como `skipped`/ignorado,
publica o resultado terminal para Commerce liberar eventual hold e não tenta
montar componentes genéricos.

O novo contrato deve rejeitar ou registrar como erro qualquer campo de seleção
externa como `template`, `template_name` ou `template_id`. Durante a transição,
um adaptador traduz os eventos legados conhecidos; o resolvedor novo nunca recebe
o nome físico vindo do produtor.

## Modelo de dados proposto

Criar no `services-notification` a tabela `whatsapp_meta_template_bindings`,
separada de `whatsapp_meta_templates`.

| Campo | Finalidade |
| --- | --- |
| `id` | Identidade interna do vínculo. |
| `action` | Inicialmente sempre `sale_recovery`; mantém o modelo extensível sem ampliar o escopo. |
| `scenario_code` | Chave estável, por exemplo `recovery_stage_1_with_pix`; não é nome Meta. |
| `label` | Rótulo administrativo: “Recuperação 1 — com PIX”. |
| `primary_template_id` | Template oficial atual. FK para `whatsapp_meta_templates`. |
| `backup_template_id` | Template reserva de uso único; FK anulável. |
| timestamps | Auditoria de criação e alteração. |

Restrições:

- unicidade de `action + scenario_code`;
- todo vínculo registrado exige principal;
- principal e reserva não podem ser iguais;
- todo `scenario_code` retornado pelo resolver possui exatamente um vínculo;
- payload inválido, cenário desconhecido, vínculo ausente ou principal ausente são
  erros observáveis; não existe seleção alternativa ou fallback.

O `whatsapp_meta` deve persistir o `template_id` já resolvido e uma referência ou
snapshot do `binding_id`/`scenario_code`. Assim, auditoria, métricas, callback e
reprocessamento representam o template que realmente foi enviado.

## Seleção e regra de reserva

1. O consumer recebe `sale_recovery`, valida o contrato e o `context`.
2. Sem `pix_code`, o Notifications ignora a mensagem sem resolver cenário ou
   template e publica o resultado terminal necessário para o Commerce encerrar o
   dispatch e liberar eventual hold.
3. Com `pix_code`, o resolver de RDC, escrito no Notifications, usa o estágio e
   devolve `recovery_stage_1_with_pix` ou `recovery_stage_2_with_pix`; outro
   estágio falha.
4. Valida que o principal possui mapping; sem mapping, encerra como `skipped` e
   publica outcome terminal sem criar `whatsapp_meta`.
5. Na transação que cria a mensagem, grava o principal mapeado no
   `whatsapp_meta` e o snapshot do vínculo.
6. O sender usa somente esse `template_id`; não interpreta ação, payload de venda
   nem nomes legados de template.

A rotação por sufixos (`sale_recovering_ct_3` a `_7`) será removida. A reserva
passa a pertencer exclusivamente ao vínculo escolhido:

1. a rotina de saúde identifica falhas qualificadas do principal de um vínculo;
2. bloqueia esse vínculo em transação e confirma que o template falho ainda é o
   seu principal;
3. se há reserva, promove `backup_template_id` para `primary_template_id` e
   grava `backup_template_id = NULL` na mesma transação;
4. registra a mudança em auditoria e emite alerta operacional seguro;
5. se a reserva já está vazia, mantém o principal oficial atual e não rotaciona.

Não há busca de próximo template, encadeamento, wrap-around ou alternativa entre
vínculos. Uma nova reserva só é cadastrada por ação administrativa explícita.
O limiar de falha deve ser contado por `binding_id` (recomendado), para que uma
falha de um cenário não promova a reserva de outro cenário que use o mesmo
template físico.

Como só `sale_recovering_ct_pix` está mapeado neste recorte, a reserva inicial
fica vazia e não há rotação ativa. A reserva só poderá ser configurada quando um
segundo template receber mapping explícito e for validado no Notifications.

Trocas de vínculo afetam apenas mensagens novas; mensagens já criadas mantêm o
template persistido. Essa decisão evita alterar uma comunicação já aceita na fila.

## Administração e Dashboard Seller

No caminho Admin → Gateway → Public API → Notifications, administrar vínculos —
não um default global ou nomes de template soltos:

- listar vínculos, cenário conhecido, principal, reserva e estado;
- definir/substituir principal e reserva, validando templates ativos e distintos;
- consultar histórico de edições e de promoção de reserva.

O endpoint atual que define um único default de recuperação permanece somente como
compatibilidade temporária e é removido ao fim da migração. Ele não pode ser uma
segunda fonte de verdade.

O Dashboard Seller substitui a tabela atual de “Template padrão” por uma tela de
vínculos de recuperação. Nesta fase ela possui exatamente duas linhas fixas:

| Cenário | Campos editáveis |
| --- | --- |
| Recuperação de venda — estágio 1 com PIX | Template principal obrigatório e template reserva opcional. |
| Recuperação de venda — estágio 2 com PIX | Template principal obrigatório e template reserva opcional. |

A tela carrega vínculos e templates elegíveis do Notifications e salva cada
vínculo por `scenario_code`, usando IDs de template — nunca nome de template. Ela
deve impedir principal vazio e principal igual à reserva; a reserva pode ser
limpa para deixar o cenário sem rotação futura. A edição preserva a alteração
atômica do backend: a promoção automática principal→reserva continua sendo
decidida exclusivamente pelo Notifications.

Neste primeiro recorte, o catálogo exposto à tela contém somente
`sale_recovering_ct_pix`; portanto os dois vínculos usam esse principal e a reserva
permanece vazia. O controle de reserva só será habilitado quando houver outro
template mapeado e elegível.

O fluxo substitui o atual seletor global em:

- `dashboard-seller/views/dashboard/admin/configs/whatsapp_notifications/index.php`;
- `dashboard-seller/api/admin/whatsapp_meta_templates.php`;
- rotas equivalentes no Gateway, Public API e Notifications.

O contrato administrativo planejado deve expor listagem de vínculos e templates
elegíveis, além de atualização por cenário, por exemplo:

```text
GET /admin/whatsapp-meta-template-bindings/sale-recovery
PUT /admin/whatsapp-meta-template-bindings/sale-recovery/{scenario_code}
```

O `PUT` recebe somente `primary_template_id` e `backup_template_id`; o cenário é
fixado pela rota e o Dashboard não envia regras de seleção, template names ou
qualquer decisão de rotação.

## Migração por etapas

### Etapa 0 — decisão funcional e inventário

- Implementar no resolver de código os dois cenários fechados: estágio 1/2 com
  PIX. PIX ausente é ignorado pelo Notifications, sem cenário fallback.
- Alterar a elegibilidade do Commerce: `pix`/`pix_automatic` sem `pix_code` é
  `skipped`; demais métodos sem código são enfileirados e ignorados pelo
  Notifications.
- Inventariar produtores de `stream:notifications:whatsapp_meta`, eventos legados,
  variáveis de ambiente, templates Meta, mensagens pendentes e relatórios que
  usam `template_id`.

Saída: matriz de decisão aprovada e contrato versionado.

### Etapa 1 — fundação no Notifications

- Criar schema, modelo, repositório, resolver de cenários e histórico/auditoria
  dos vínculos.
- Cadastrar os dois vínculos exigidos pelos cenários do resolver com
  `sale_recovering_ct_pix` como único principal mapeado; reservas permanecem
  vazias até existir outro mapping aprovado.
- Evoluir `whatsapp_meta` para guardar template resolvido e vínculo/cenário, sem
  reescrever histórico.
- Adaptar health/alertas para identificar falhas por vínculo, deixando a promoção
  automática desligada até a validação da etapa seguinte.

Saída: Notifications resolve e audita a decisão sem alteração de Commerce.

### Etapa 1.1 — administração de vínculos

- Expor no Notifications a listagem e atualização administrativa dos dois
  vínculos, com validação de principal, reserva e templates elegíveis.
- Encaminhar as novas rotas pelo Public API e Gateway, preservando a autorização
  administrativa atual.
- Substituir no Dashboard Seller o seletor global pelos dois vínculos fixos;
  remover o uso da API local e endpoint que atualizam
  `sale-recovery-default`.

Saída: o Dashboard Seller administra principal e reserva por estágio com PIX,
sem acesso direto ao banco ou escolha de template pela fila.

### Etapa 2 — novo contrato e compatibilidade

- Aceitar `action=sale_recovery`, `context` e `params` no consumer.
- Traduzir eventos legados conhecidos para esse contrato por um adaptador isolado
  e medir seu uso.
- Fazer o sender depender exclusivamente do template persistido; remover a lógica
  especial de `sale_recovering_ct*`.
- Rejeitar template físico no novo envelope e testar o contrato.

Saída: Notifications usa o único template mapeado para os dois cenários com PIX e
ignora casos sem PIX ou com template sem mapping.

### Etapa 3 — Commerce V2: recuperação de venda

- Publicar somente `action=sale_recovery`, fatos aprovados no `context`, telefone,
  parâmetros e correlação; remover nomes Meta da fila.
- Retirar `SALE_RECOVERY_WHATSAPP_META_*_EVENT` e constantes equivalentes após o
  adaptador confirmar que não há outro produtor dependente.
- Preservar agendamento, pending/janela, contato, crédito, cobrança e callbacks
  no Commerce: apenas a escolha do template muda de dono.
- Não ativar promoção principal→reserva enquanto só existir um template mapeado.

Saída: RDC não possui dependência externa de template Meta.

### Etapa 4 — retirada do legado

- Com métricas sem produtores legados e sem backlog pendente, remover adaptador,
  endpoint/default global e rotação baseada em sufixos.
- Atualizar o mapa técnico e a documentação operacional confirmada.

## Testes e aceite

- O mesmo payload com PIX resolve o mesmo `scenario_code` dentre os dois cenários
  definidos no código e, então, o mesmo vínculo registrado.
- Mensagem sem PIX é ignorada e retorna resultado terminal ao Commerce, sem criar
  mensagem Meta; `pix`/`pix_automatic` sem código é `skipped` antes da fila.
- Template principal sem mapping é ignorado como `skipped`, sem criar mensagem
  Meta; isso inclui `sale_recovering_ct_pix_2` até `_8` neste recorte.
- Payload inválido, cenário com PIX sem vínculo ou principal ausente falham de forma
  observável, sem fallback.
- Um produtor não consegue alterar template ao enviar nome ou ID no novo contrato.
- A mensagem persiste o template e vínculo efetivamente resolvidos antes do sender.
- Falha qualificada com reserva promove-a para principal e limpa a reserva.
- Nova falha sem reserva mantém o principal oficial e não rotaciona.
- A troca de um vínculo não altera qualquer outro, mesmo que ambos referenciem o
  mesmo template físico.
- O Dashboard Seller exibe somente os dois cenários fixos, grava IDs de principal
  e reserva e não permite principal vazio ou igual à reserva.
- O Dashboard não chama nem exibe o endpoint/default global legado.
- Outcomes, idempotência comercial, holds, consumo e liberação do RDC mantêm seus
  contratos atuais.

## Decisões pendentes

- Representação única de PIX ausente (`null` ou string vazia) no contrato, para
  o Notifications ignorar a mensagem de modo determinístico.
- Política que qualifica “cair” (falha imediata, limiar consecutivo etc.); o plano
  pressupõe transição idempotente por vínculo.
- Formato do erro/outcome para principal ausente ou payload sem cenário elegível.
- Interface administrativa: é parte posterior à API administrativa, não condição
  para a primeira migração de backend.

## Componentes afetados

| Componente | Papel |
| --- | --- |
| `services-notification` | Dono dos vínculos, dos dois cenários com PIX, do catálogo de mapping, do ignore sem PIX/sem mapping, template persistido, reserva, administração e observabilidade. |
| `services-commerce-v2` | Publica ação/contexto semântico, aplica o skip de PIX/pix_automatic sem código e preserva as demais regras comerciais de RDC. |
| `edge-public-api` e `edge-gateway` | Expõem administração autorizada de vínculos, sem decidir templates. |
| `dashboard-seller` | Substitui o seletor global por edição dos dois vínculos, principal e reserva. |

## Referências confirmadas

- `services-commerce-v2/app/Application/UseCase/Sale/ExecuteSaleRecoveryDispatchUseCase.php`
- `services-commerce-v2/app/Queue/NotificationQueueService.php`
- `services-notification/app/Service/RegisterWhatsappMetaEvent.php`
- `services-notification/app/Service/WhatsappMetaSenderService.php`
- `services-notification/app/Service/SaleRecoveryTemplateRotationService.php`
- `services-notification/app/Process/DeliveryHealthProcess.php`
