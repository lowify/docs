# Plano — recuperação automática de operações incertas

## Decisão de escopo

Esta melhoria não faz parte do corte de deploy atual. O mecanismo já existente persiste operações de recuperação e impede que uma falha intermediária seja simplesmente esquecida; este plano cobre a próxima etapa: resolver automaticamente operações cujo pedido externo foi enviado, mas cuja resposta não chegou ao Checkout Transparente.

O objetivo não é repetir uma cobrança automaticamente. O objetivo é descobrir, por uma referência persistida, se o provedor já executou a operação antes de decidir entre concluir, retomar ou encaminhar para reconciliação manual.

## Caso que será resolvido

```text
Checkout Transparente envia criação de autorização/cobrança ao provedor
→ o provedor pode concluir a operação
→ a conexão expira antes da resposta chegar ao Checkout Transparente
→ a operação local fica em estado unknown
```

Nesse ponto, reenviar cegamente pode criar segunda autorização ou segunda cobrança. Não fazer nada deixa venda ou assinatura pendente indefinidamente.

## Estado atual confirmado

- `checkout_recovery_operations` registra operações de assinatura, cobrança e notificação, com status, tentativas e lease.
- O recuperador consegue retomar operações pendentes e evita dois processos assumirem a mesma operação ao mesmo tempo.
- Quando a criação externa ou uma notificação fica sem resposta, o registro pode permanecer `unknown`, aguardando reconciliação.
- A operação persistida não deve conter PAN, CVV, token de cartão, credenciais ou resposta bruta sensível do provedor.

## Desenho proposto

### 1. Referência de correlação persistida antes da chamada externa

Cada pedido ao provedor deve ter uma referência estável, criada antes do envio e gravada na operação local. A mesma referência deve ser usada no `idempotency key`, metadados ou campo de correlação aceito pelo provedor.

| Operação | Referência mínima de reconciliação |
| --- | --- |
| Criar autorização de Pix Automático | referência da assinatura local + chave de idempotência do pedido |
| Criar cobrança recorrente | assinatura + número da parcela + `txid` ou identificador determinístico da cobrança |
| Notificar pagamento ao Commerce | assinatura + número da parcela + `end_to_end_id`/ID único de pagamento |

### 2. Consulta antes de reenviar

Para uma operação `unknown`, o recuperador deve primeiro consultar o provedor pelo identificador persistido:

- **Encontrada e compatível:** persistir os IDs retornados, concluir a operação local e seguir apenas as próximas etapas ainda ausentes.
- **Não encontrada e dentro da janela segura de retentativa:** reenviar usando a mesma chave de idempotência; nunca gerar nova referência.
- **Resposta ambígua, indisponibilidade ou divergência:** manter em reconciliação, registrar diagnóstico seguro e gerar sinal operacional. Não criar outra autorização/cobrança.

O mesmo princípio vale para a notificação ao Commerce: consultar ou reprocessar o evento bruto com a identidade única do pagamento, sem recriar venda, acesso, entrega ou billing.

### 3. Estados e operação humana

Estados sugeridos:

```text
pending → published → unknown → reconciling → completed
                                  └────────→ manual_review
```

- `unknown`: não há confirmação suficiente após a tentativa externa.
- `reconciling`: uma consulta segura está em andamento.
- `manual_review`: esgotaram-se as tentativas ou houve divergência; exibir referência, componente e próximo passo, sem dados sensíveis.
- `completed`: efeito externo confirmado e efeitos locais aplicados de forma idempotente.

Definir limite de tentativas, janela de atraso e alerta operacional por provedor. A decisão de cancelar ou expirar uma venda pendente deve ser explícita e auditável; não apagar registros ou filas para encerrar o caso.

## Requisitos de idempotência e consistência

- Uma referência local corresponde a, no máximo, uma autorização e uma cobrança externa.
- Webhook, polling e recuperação usam a mesma identidade de pagamento; reentrega não duplica parcela, venda, acesso, entrega ou item de billing.
- A reconciliação de uma criação externa acontece antes de qualquer nova chamada de criação.
- Uma confirmação de pagamento só produz efeitos comerciais depois de validar assinatura, parcela e identificador único de pagamento.
- Operações canceladas não são reabertas pela reconciliação; um pagamento tardio segue a política de cancelamento definida separadamente.

## Critérios de aceite

| Cenário | Resultado esperado |
| --- | --- |
| Provedor criou a autorização, mas a resposta se perdeu | A consulta encontra a autorização; o CT salva o identificador e não cria outra. |
| Pedido não chegou ao provedor | O CT reenvia com a mesma referência/chave e cria somente uma autorização. |
| Criação de cobrança recorrente com resposta perdida | A consulta encontra ou confirma ausência da cobrança da parcela; nunca existem duas para a mesma assinatura/parcela. |
| Provedor indisponível durante reconciliação | A operação permanece rastreável e recebe alerta; nenhuma nova criação ocorre. |
| Reprocessamento após reinício | A operação converge para o mesmo estado, sem duplicar venda, acesso, entrega, billing ou cobrança externa. |
| Operação manual | O operador consegue localizar o caso por referência e entender se deve aguardar, corrigir integração ou encerrar conforme política. |

## Componentes prováveis

- `services-checkout-transparent-api`: operações de recuperação, correlação persistida, reconciliador e consultas de status.
- `services-checkout-transparent-worker`: instruções de consulta/criação idempotente quando o provedor exigir execução assíncrona.
- `edge-checkout-transparent-webhook` e `edge-webhook`: reprocessamento idempotente de eventos já persistidos.
- `services-commerce-v2`: somente se for necessário expor confirmação/reconciliação de ação de assinatura; não deve recriar venda fora do contrato idempotente existente.

## Fora do escopo

- Alterar dados de cartão, tokenização ou rate limit de cartão.
- Repetir cobranças ou autorizações sem primeiro consultar o provedor.
- Limpar Redis, apagar operações ou alterar estado financeiro manualmente para fazer uma operação desaparecer.
