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
  action + context → regra/vínculo vencedor entre N pré-templates
                   → template principal do vínculo
                   → persistência da mensagem e envio à Meta
```

Esta mesma regra vale para qualquer entrada HTTP futura: ela poderá solicitar a
ação `sale_recovery` autorizada, mas jamais escolher o template físico.

## Resultado esperado

Não existirá uma relação 1:1 entre `sale_recovery` e um único template default.
O Notifications manterá N vínculos pré-definidos de recuperação. Para cada
mensagem, o resolvedor avalia o payload, encontra a regra de maior prioridade
compatível e usa o principal daquele vínculo.

Exemplo conceitual:

| Pré-template/vínculo | Critério do payload | Principal | Reserva |
| --- | --- | --- | --- |
| Recuperação 1 — sem PIX | `stage=1` e `has_pix_code=false` | template X | template Y |
| Recuperação 1 — oficial | `stage=1` | template A | vazio |
| Recuperação 2 — oferta expirando | `stage=2` | template B | template C |
| Recuperação — fallback oficial | fallback explícito | template D | vazio |

“Sem PIX” é o exemplo de nome de negócio, não um template Meta. Hoje o Commerce
descarta RDC sem código PIX; antes de ativar esse vínculo, será preciso decidir se
o caso muda a elegibilidade da recuperação ou se apenas classifica mensagens que
já seriam elegíveis. O Notifications não deve liberar um envio que Commerce tenha
marcado como inelegível.

## Contrato-alvo da fila

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

| Campo | Responsabilidade |
| --- | --- |
| `action` | Valor fechado: `sale_recovery`; não é nome de template. |
| `context` | Fatos de negócio permitidos para a regra selecionar um dos N vínculos. Não contém provider, nome ou ID Meta. |
| `params` | Dados autorizados para renderização e correlação/outcome. |
| template final | Resolvido somente pelo Notifications. |

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
| `scenario_code` | Chave estável, por exemplo `recovery_stage_1_without_pix`; não é nome Meta. |
| `label` | Rótulo administrativo: “Recuperação 1 — sem PIX”. |
| `priority` | Ordem determinística entre os N vínculos elegíveis. |
| `match_criteria` | Critérios versionados comparados com `context`; JSON com operadores restritos e validados em código, nunca SQL livre. |
| `primary_template_id` | Template oficial atual. FK para `whatsapp_meta_templates`. |
| `backup_template_id` | Template reserva de uso único; FK anulável. |
| `is_active`, timestamps | Estado e auditoria. |

Restrições:

- unicidade de `action + scenario_code`;
- vínculo ativo exige principal;
- principal e reserva não podem ser iguais;
- há exatamente um vencedor: maior prioridade entre regras satisfeitas;
- empate, critério inválido ou ausência de fallback são erros observáveis, nunca
  seleção arbitrária;
- há um vínculo de fallback oficial explícito, com a menor prioridade, para RDC.

O `whatsapp_meta` deve persistir o `template_id` já resolvido e uma referência ou
snapshot do `binding_id`/`scenario_code`. Assim, auditoria, métricas, callback e
reprocessamento representam o template que realmente foi enviado.

## Seleção e regra de reserva

1. O consumer recebe `sale_recovery`, valida o contrato e o `context`.
2. O resolvedor avalia todos os vínculos ativos da ação e escolhe o vencedor por
   prioridade.
3. Na transação que cria a mensagem, grava o principal resolvido no
   `whatsapp_meta` e o snapshot do vínculo.
4. O sender usa somente esse `template_id`; não interpreta ação, payload de venda
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

Não há busca de próximo template, encadeamento, wrap-around nem fallback implícito
entre vínculos. Uma nova reserva só é cadastrada por ação administrativa explícita.
O limiar de falha deve ser contado por `binding_id` (recomendado), para que uma
falha de um cenário não promova a reserva de outro cenário que use o mesmo
template físico.

Trocas de vínculo afetam apenas mensagens novas; mensagens já criadas mantêm o
template persistido. Essa decisão evita alterar uma comunicação já aceita na fila.

## Administração

No caminho Admin → Gateway → Public API → Notifications, administrar vínculos —
não um default global ou nomes de template soltos:

- listar vínculos, critérios, prioridade, principal, reserva e estado;
- criar/editar cenário e critérios permitidos;
- definir/substituir principal e reserva, validando templates ativos e distintos;
- ativar/desativar vínculo;
- consultar histórico de edições e de promoção de reserva.

O endpoint atual que define um único default de recuperação permanece somente como
compatibilidade temporária e é removido ao fim da migração. Ele não pode ser uma
segunda fonte de verdade.

## Migração por etapas

### Etapa 0 — decisão funcional e inventário

- Fechar os N cenários de RDC, critérios permitidos, prioridades e fallback.
- Decidir o comportamento de “sem PIX” frente à elegibilidade atual.
- Inventariar produtores de `stream:notifications:whatsapp_meta`, eventos legados,
  variáveis de ambiente, templates Meta, mensagens pendentes e relatórios que
  usam `template_id`.

Saída: matriz de decisão aprovada e contrato versionado.

### Etapa 1 — fundação no Notifications

- Criar schema, modelo, repositório, validador de critérios, resolvedor e
  histórico/auditoria dos vínculos.
- Cadastrar N vínculos que reproduzam o comportamento atual, mais o fallback
  oficial; reservas são explícitas e inicialmente opcionais.
- Evoluir `whatsapp_meta` para guardar template resolvido e vínculo/cenário, sem
  reescrever histórico.
- Adaptar health/alertas para identificar falhas por vínculo, deixando a promoção
  automática desligada até a validação da etapa seguinte.

Saída: Notifications resolve e audita a decisão sem alteração de Commerce.

### Etapa 2 — novo contrato e compatibilidade

- Aceitar `action=sale_recovery`, `context` e `params` no consumer.
- Traduzir eventos legados conhecidos para esse contrato por um adaptador isolado
  e medir seu uso.
- Fazer o sender depender exclusivamente do template persistido; remover a lógica
  especial de `sale_recovering_ct*`.
- Rejeitar template físico no novo envelope e testar o contrato.

Saída: Notifications escolhe entre N pré-templates para contratos novos e legados.

### Etapa 3 — Commerce V2: recuperação de venda

- Publicar somente `action=sale_recovery`, fatos aprovados no `context`, telefone,
  parâmetros e correlação; remover nomes Meta da fila.
- Retirar `SALE_RECOVERY_WHATSAPP_META_*_EVENT` e constantes equivalentes após o
  adaptador confirmar que não há outro produtor dependente.
- Preservar agendamento, pending/janela, contato, crédito, cobrança e callbacks
  no Commerce: apenas a escolha do template muda de dono.
- Ativar a promoção principal→reserva somente para vínculos que tenham reserva
  aprovada.

Saída: RDC não possui dependência externa de template Meta.

### Etapa 4 — retirada do legado

- Com métricas sem produtores legados e sem backlog pendente, remover adaptador,
  endpoint/default global e rotação baseada em sufixos.
- Atualizar o mapa técnico e a documentação operacional confirmada.

## Testes e aceite

- O mesmo payload resolve o mesmo vínculo vencedor dentre os N pré-definidos.
- Critérios inválidos, empate e ausência de fallback falham de forma observável.
- Um produtor não consegue alterar template ao enviar nome ou ID no novo contrato.
- A mensagem persiste o template e vínculo efetivamente resolvidos antes do sender.
- Falha qualificada com reserva promove-a para principal e limpa a reserva.
- Nova falha sem reserva mantém o principal oficial e não rotaciona.
- A troca de um vínculo não altera qualquer outro, mesmo que ambos referenciem o
  mesmo template físico.
- Outcomes, idempotência comercial, holds, consumo e liberação do RDC mantêm seus
  contratos atuais.

## Decisões pendentes

- Taxonomia final dos N pré-templates e a precedência de cada regra.
- Política que qualifica “cair” (falha imediata, limiar consecutivo etc.); o plano
  pressupõe transição idempotente por vínculo.
- Comportamento para principal inativo/ausente ou payload sem cenário elegível.
- Interface administrativa: é parte posterior à API administrativa, não condição
  para a primeira migração de backend.

## Componentes afetados

| Componente | Papel |
| --- | --- |
| `services-notification` | Dono dos vínculos, resolução entre N pré-templates, template persistido, reserva, administração e observabilidade. |
| `services-commerce-v2` | Publica ação/contexto semântico e preserva regras comerciais de RDC. |
| `edge-public-api` e `edge-gateway` | Expõem administração autorizada de vínculos, sem decidir templates. |

## Referências confirmadas

- `services-commerce-v2/app/Application/UseCase/Sale/ExecuteSaleRecoveryDispatchUseCase.php`
- `services-commerce-v2/app/Queue/NotificationQueueService.php`
- `services-notification/app/Service/RegisterWhatsappMetaEvent.php`
- `services-notification/app/Service/WhatsappMetaSenderService.php`
- `services-notification/app/Service/SaleRecoveryTemplateRotationService.php`
- `services-notification/app/Process/DeliveryHealthProcess.php`
