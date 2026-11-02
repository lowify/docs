# Plano — Centralização de templates de comunicações de venda

> Status: planejado  
> Escopo inicial: entrega pós-compra e recuperação de venda (RDC), somente WhatsApp Meta.  
> Não inclui implementação, migration executável, deploy, alteração de filas nem mudança de comportamento em produção.

## Decisão de arquitetura

`services-notification` passa a ser o único componente que escolhe o template
físico enviado à Meta. Nenhum produtor de mensagem — HTTP, Redis stream, processo
ou outro serviço — pode informar ou depender de `whatsapp_meta_templates.name`.

Os demais componentes continuam decidindo **se** uma comunicação é elegível,
quando ela deve ocorrer, canal, destinatário, cobrança, correlação comercial e
os dados de negócio. Eles publicam somente uma ação semântica e seu contexto.

```text
Commerce V2
  └─ stream:notifications:whatsapp_meta
       action = sale_delivery | sale_recovery
       context + params comerciais, sem nome/id de template Meta

Notifications
  └─ resolve ação + contexto/payload → vínculo ativo → template principal
  └─ persiste a mensagem já associada ao template resolvido
  └─ envia à Meta e publica outcome comercial como hoje
```

Essa regra vale igualmente para qualquer entrada futura HTTP: HTTP pode criar uma
ação semântica autorizada, mas não pode selecionar template físico.

## Estado atual e lacuna que a migração corrige

Hoje o Commerce V2 publica um `event` que também é o nome lógico/físico do
template, por exemplo os eventos configurados por estágio do RDC e os nomes de
template da entrega. O Notifications só troca o nome no sender para a família
especial `sale_recovering_ct`/`sale_recovering_ct_3` a `_7`.

Assim, a decisão ainda é híbrida: Commerce influencia o template recebido e o
Notifications aplica rotação apenas a uma exceção. Além disso, o registro
`whatsapp_meta.template_id` pode representar o evento recebido e não o template
efetivamente enviado à Meta. A nova modelagem elimina essa ambiguidade.

## Contrato-alvo da fila

O payload deve separar ação, contexto de roteamento e parâmetros de renderização.
Os nomes abaixo são ilustrativos; o contrato final deve ser versionado e validado
antes da implementação.

```json
{
  "action": "sale_recovery",
  "phone": "5511999999999",
  "context": {
    "stage": 1,
    "payment_state": "pending",
    "has_pix_code": false
  },
  "params": {
    "first_name": "...",
    "product_name": "...",
    "button_link": "...",
    "notification_outcome": { "...": "..." }
  }
}
```

| Campo | Dono | Regra |
| --- | --- | --- |
| `action` | produtor da comunicação | Valor fechado inicialmente: `sale_delivery` ou `sale_recovery`. Não é nome de template. |
| `context` | produtor da comunicação | Fatos de negócio necessários para selecionar o cenário. Não contém nome, ID, provider ou categoria Meta. |
| `params` | produtor da comunicação | Dados já autorizados para renderizar o template e para correlação/outcome. |
| template final | Notifications | Resolvido exclusivamente no banco do Notifications. |

O consumidor deve rejeitar/registrar como erro de contrato payload novo que
contenha `template`, `template_name`, `template_id` ou equivalente. Durante a
migração, o formato legado será aceito apenas pelo adaptador de compatibilidade,
nunca pelo novo resolvedor.

## Cenários e vínculos de template

Criar no `services-notification` uma entidade de vínculo de template, separada de
`whatsapp_meta_templates`. Nome sugerido: `whatsapp_meta_template_bindings`.

| Campo | Finalidade |
| --- | --- |
| `id` | Identidade interna. |
| `action` | `sale_delivery` ou `sale_recovery`. |
| `scenario_code` | Chave estável de negócio, como `recovery_stage_1_without_pix`; não é o nome do template Meta. |
| `label` | Rótulo administrativo, por exemplo “Recuperação 1 — sem PIX”. |
| `priority` | Ordem determinística entre cenários elegíveis da mesma ação. |
| `match_criteria` | Critérios versionados para comparar com `context`; inicialmente JSON com operadores restritos/evaluados em código, não SQL livre. |
| `primary_template_id` | Template oficial atualmente usado pelo vínculo. FK para `whatsapp_meta_templates`. |
| `backup_template_id` | Reserva de uso único; FK anulável para a mesma tabela. |
| `is_active`, timestamps | Habilitação e auditoria operacional. |

Restrições obrigatórias:

- unicidade de `action + scenario_code`;
- `primary_template_id` obrigatório para vínculo ativo;
- principal e reserva não podem ser iguais;
- a seleção exige exatamente um cenário vencedor: maior prioridade entre os
  critérios satisfeitos; empate ou ausência de cenário é erro observável e não
  pode cair silenciosamente em um template arbitrário;
- toda ação tem um cenário oficial de fallback explícito, com menor prioridade,
  para os casos em que nenhum cenário específico se aplique.

Exemplo de configuração inicial a validar com Produto:

| Ação | Cenário | Critério ilustrativo | Principal | Reserva |
| --- | --- | --- | --- | --- |
| `sale_recovery` | Recuperação 1 — sem PIX | `stage=1` e `has_pix_code=false` | template X | template Y |
| `sale_recovery` | Recuperação 1 — oficial | `stage=1` | template A | vazio |
| `sale_delivery` | Entrega — conteúdo | `delivery_mode=content_link` | template B | vazio |
| `sale_delivery` | Entrega — oficial | fallback da ação | template C | template D |

“Sem PIX” é apenas exemplo de cenário solicitado. No código atual, RDC sem código
PIX é ignorada; portanto, antes de ativar esse cenário, Produto/Commerce devem
decidir se ele muda a elegibilidade do RDC ou apenas classifica um payload que já
seja elegível. A seleção de template não deve, por si só, liberar uma comunicação
que Commerce tenha marcado como inelegível.

## Resolução e persistência

1. O consumidor recebe a ação e valida o contrato.
2. O resolvedor encontra o cenário vencedor a partir de `action + context`.
3. Ainda dentro da criação da mensagem, grava em `whatsapp_meta` o
   `template_id` do `primary_template_id` resolvido, além de um snapshot mínimo
   do vínculo/cenário para auditoria.
4. O sender usa somente o `template_id` persistido; ele não interpreta eventos
   de venda nem consulta configuração de rotação.
5. O outcome para Commerce preserva a correlação comercial atual e pode incluir
   o `binding_id`/`scenario_code` para observabilidade, sem expor parâmetros ou
   conteúdo da mensagem.

O snapshot na criação evita que uma troca posterior altere mensagens já aceitas e
mantém histórico, métricas e callbacks associados ao template que foi realmente
enviado.

## Nova regra de reserva e falha

A rotação deixa de ser uma sequência global de nomes (`_3` a `_7`). Ela pertence
ao vínculo que selecionou a mensagem.

Quando a rotina de saúde/falha confirmar que o **principal atual** de um vínculo
deve ser desativado:

1. bloqueia o vínculo em transação;
2. confirma que o template que falhou ainda é o `primary_template_id` atual;
3. se `backup_template_id` estiver preenchido, promove-o a
   `primary_template_id` e define `backup_template_id = NULL` na mesma
   transação;
4. registra uma transição de configuração auditável e emite o alerta operacional
   com vínculo, cenário e antigo/novo principal;
5. se não houver reserva, não modifica o vínculo e não tenta qualquer rotação:
   o template oficial atual permanece sendo usado.

Não há encadeamento automático, wrap-around nem busca de “próximo” template. Uma
nova reserva só existe após alteração administrativa explícita do vínculo. Essa
regra também evita que uma falha num cenário altere outros cenários que, por
acaso, usam o mesmo template.

O limiar que caracteriza “cair” deve reutilizar ou substituir explicitamente a
política atual de `DeliveryHealthProcess`. A decisão necessária é se o limiar será
contado por `binding_id` (recomendado) ou por template físico; para a nova regra,
o primeiro evita que falhas de cenários distintos consumam a reserva errada.

## Administração

Criar administração no caminho já existente de Admin → Gateway → Public API →
Notifications para listar e alterar vínculos, não templates em linha solta.

Operações previstas:

- listar vínculos, cenário, critérios, principal, reserva e estado;
- criar/editar critérios e prioridade;
- definir/substituir principal e reserva, validando templates ativos e distintos;
- ativar/desativar vínculo;
- consultar histórico de mudanças e de promoção de reserva.

O endpoint atual que escolhe um único default de recuperação deve permanecer
somente como compatibilidade temporária ou ser descontinuado após a migração. Ele
não deve coexistir como uma segunda fonte de verdade para a ação `sale_recovery`.

## Migração por etapas

### Etapa 0 — definição funcional e inventário

- Fechar a taxonomia de cenários para `sale_delivery` e `sale_recovery`, incluindo
  campos permitidos no `context`, precedência e fallback oficial de cada ação.
- Decidir o significado operacional de “sem PIX” frente à elegibilidade atual de
  RDC.
- Inventariar todos os produtores atuais de `stream:notifications:whatsapp_meta`,
  chamadas HTTP relacionadas e todos os templates Meta usados por entrega/RDC.
- Mapear mensagens pendentes e dashboards/relatórios que leem `template_id`.

Saída: contrato versionado, tabela de cenários aprovada e plano de compatibilidade.

### Etapa 1 — fundação no Notifications, sem mudar produtores

- Criar migrations, modelos, repositório, resolvedor de cenário e trilha de
  auditoria de vínculos.
- Cadastrar os vínculos equivalentes ao comportamento atual, com principal e,
  quando houver, uma reserva explícita.
- Evoluir `whatsapp_meta` para armazenar o vínculo/cenário resolvido ou snapshot
  equivalente, sem reescrever o histórico existente.
- Implementar administração e autorização já usada para configurações de admin.
- Adaptar health/alertas para operar por vínculo, mas manter a rotação automática
  desligada até a Etapa 3.

Saída: Notifications sabe resolver e auditar vínculos, ainda sem depender do novo
contrato de Commerce.

### Etapa 2 — contrato semântico e adaptador de compatibilidade

- Aceitar o novo envelope `action + context + params` no consumer da stream.
- Manter um adaptador explícito para eventos legados, traduzindo-os para ações e
  contextos conhecidos; registrar métricas de uso legado.
- Fazer o sender usar somente o template persistido pelo resolvedor; remover a
  lógica especial de nomes `sale_recovering_ct*` dele.
- Rejeitar nomes de template nos novos payloads e cobrir rejeição com testes.

Saída: o Notifications é capaz de escolher o template final tanto para contratos
novos quanto para produtores ainda legados.

### Etapa 3 — migração de entrega pós-compra

- Alterar o Commerce V2 para publicar `action=sale_delivery` e apenas contexto
  semântico de entrega (por exemplo, modo de conteúdo), parâmetros e correlação.
- Remover do Commerce constantes/configurações que representem nomes de template
  Meta de entrega.
- Validar outcome, cobrança, timeout, fallback de e-mail e reenvios: eles devem
  permanecer inalterados porque não pertencem à escolha do template.
- Ativar a promoção principal→reserva para vínculos de entrega que já tenham
  reserva aprovada.

Saída: entrega não tem dependência externa de nome de template.

### Etapa 4 — migração de recuperação de venda

- Alterar o Commerce V2 para publicar `action=sale_recovery`, estágio e demais
  fatos aprovados no contexto, sem `SALE_RECOVERY_WHATSAPP_META_*_EVENT` nem
  nomes de template.
- Migrar os cenários de RDC, inclusive fallback oficial por etapa, para vínculos
  administrados no Notifications.
- Ativar promoção principal→reserva exclusivamente nos vínculos com reserva.
- Manter regras de agendamento, pending/janela, contato, crédito e callbacks no
  Commerce; somente a escolha de template muda de dono.

Saída: RDC não depende de configuração externa para template Meta.

### Etapa 5 — retirada da compatibilidade

- Após métricas comprovarem ausência de produtores legados e não existirem
  mensagens legadas pendentes, remover o adaptador e as envs/configurações de
  nomes de template no Commerce.
- Remover o endpoint/default global legado e a rotação baseada em sufixos.
- Atualizar mapa técnico da feature e documentação operacional.

## Testes e aceite

- Para cada ação, o mesmo `context` sempre resolve o mesmo vínculo vencedor;
  critérios ausentes, inválidos ou ambíguos falham de modo observável.
- Nenhum producer consegue alterar o template físico ao incluir nome/id de
  template no novo contrato.
- Entrega e RDC persistem o template efetivamente escolhido antes do sender.
- Após falha qualificada com reserva, a próxima mensagem nova usa a reserva como
  principal e o campo reserva fica vazio.
- Após nova falha de vínculo sem reserva, o principal permanece inalterado e não
  há tentativa de próximo template.
- Uma rotação de um vínculo não altera outro vínculo que compartilhe o mesmo
  template físico.
- Callbacks, outcomes, idempotência comercial, holds/consumo/liberação e e-mail
  fallback de entrega continuam com os mesmos contratos.
- O adaptador legado produz a mesma seleção esperada enquanto estiver ativo, e
  sua remoção só ocorre sem backlog pendente.

## Riscos e decisões pendentes

- Definir todos os cenários, seus critérios permitidos e precedência antes de
  expor telas administrativas; JSON livre sem validador não é aceitável.
- Decidir se alteração de vínculo afeta somente mensagens novas (recomendado e
  previsto neste plano) ou também mensagens já pendentes.
- Confirmar se a saúde deve promover reserva após falha imediata, após limiar de
  falhas consecutivas ou por outra política; o plano pressupõe uma confirmação
  idempotente por vínculo.
- Definir comportamento para template principal inativo/ausente e para nenhum
  cenário elegível: falhar com outcome técnico, nunca escolher outro template por
  aproximação.
- O escopo não cobre push, Evolution, e-mail, outros domínios de WhatsApp nem
  configuração por produto/afiliação além do contexto já produzido por Commerce.

## Componentes afetados

| Componente | Papel na migração |
| --- | --- |
| `services-notification` | Dono dos vínculos, seleção, persistência do template resolvido, promoção de reserva, administração e observabilidade. |
| `services-commerce-v2` | Publica ações/contexto semântico para entrega e RDC; mantém elegibilidade, cobrança, agendamento e outcomes. |
| `edge-public-api` e `edge-gateway` | Expõem somente a administração de vínculos autorizada; não resolvem templates. |
| `dashboard-seller`/admin | Interface futura para administrar vínculos; fora da primeira implementação até existir contrato administrativo aprovado. |

## Referências confirmadas

- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPaidSaleEventDeliveryUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ExecuteSaleRecoveryDispatchUseCase.php`
- `services-commerce-v2/app/Queue/NotificationQueueService.php`
- `services-notification/app/Service/RegisterWhatsappMetaEvent.php`
- `services-notification/app/Service/WhatsappMetaSenderService.php`
- `services-notification/app/Service/SaleRecoveryTemplateRotationService.php`
- `services-notification/app/Process/DeliveryHealthProcess.php`
