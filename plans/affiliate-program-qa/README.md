# Plano de QA — Programa de Afiliados

> Status: proposto para execução em homologação
> Última atualização: 2026-10-02
> Público: Direção, Produto, QA, Engenharia e Operações

## 1. Decisão solicitada

Autorizar uma rodada formal de qualidade e carga controlada do programa de afiliados antes de ampliar seu uso comercial. A funcionalidade está em produção, mas ainda não recebeu validação integrada em escala depois das evoluções recentes. Esta rodada não altera regras de negócio nem publica código; ela mede e comprova o comportamento já entregue.

O resultado esperado é um parecer objetivo de **go**, **go com ressalvas** ou **no-go**, acompanhado de evidências e dos defeitos priorizados.

## 2. Objetivo

Comprovar, de ponta a ponta, que uma venda atribuída a afiliado:

1. nasce de um programa e de uma afiliação válidos;
2. respeita as permissões de produtor, afiliado e terceiros;
3. registra a atribuição, a comissão e as taxas corretas;
4. é processada uma única vez quando eventos ou webhooks são repetidos;
5. segue a liquidação aplicável — carteira ou split de gateway — sem perda ou duplicidade financeira;
6. aparece de forma consistente nas telas, notificações e relatórios.

## 3. Escopo

### Incluído

- Criação, edição, ativação e desativação do programa de afiliados por produto.
- Aprovação automática e manual, convite, aprovação, cancelamento e bloqueio de afiliado.
- Comissão, ofertas permitidas, dados do comprador e remuneração de upsell.
- Links de divulgação e atribuição no checkout.
- Pix e cartão nos gateways disponíveis em sandbox/homologação.
- Estados de venda pendente, paga, recusada, cancelada e estornada, quando suportados pelo ambiente.
- Comissão em retenção, liberação, carteira e split de gateway.
- Notificações de venda e configuração de recuperação pelo afiliado.
- Dashboard, detalhes de venda, listagens e relatórios.
- Autorização, privacidade, idempotência, filas e carga controlada.

### Fora de escopo

- Teste de carga diretamente em produção.
- Pagamentos, mensagens ou dados pessoais reais.
- Mudança de regra financeira, migração de dados ou correção manual de saldo para aprovar testes.
- Certificação de disponibilidade de provedores externos fora do sandbox.

## 4. Riscos que a rodada deve reduzir

| Risco | Impacto | Evidência exigida |
| --- | --- | --- |
| Comissão duplicada ou ausente | Financeiro e confiança comercial | Uma única comissão por venda e conciliação de valor. |
| Afiliação indevida ou vazamento de dados | Segurança e LGPD | Tentativas entre contas retornam bloqueio e não expõem dados. |
| Link de afiliado atribui venda errada | Financeiro e suporte | Venda aponta para o afiliado do link válido. |
| Alteração posterior muda venda histórica | Financeiro e auditoria | Comissão registrada na venda permanece estável. |
| Reprocessamento de evento duplica crédito | Financeiro | Reenvio controlado não cria novo lançamento ou notificação. |
| Relatórios divergem da operação | Decisão gerencial | Totais conciliam com vendas e comissões de teste. |
| Volume degrada consulta ou processamento | Operação | Métricas de latência, erros e filas dentro dos limites acordados. |

## 5. Componentes cobertos

```text
Dashboard Seller
  -> Edge Public API (JWT e roteamento)
  -> Commerce V2 (programa, afiliação, venda e comissão)
  -> banco, filas, carteira e/ou gateway split
  -> notificações, detalhes e relatórios
```

O Commerce V2 persiste a venda com `affiliate_id` e mantém a comissão em `sales_affiliates`. A comissão pode usar `wallet` ou `gateway_split`. No fluxo de carteira, o pagamento coloca a comissão em retenção e uma rotina posterior faz a liberação; no split, a venda é liquidada pelo gateway e o registro é marcado como liberado. Esses dois caminhos devem ser testados separadamente quando habilitados no ambiente.

## 6. Controles antes de iniciar

1. Executar somente em homologação ou sandbox com dados exclusivos de teste.
2. Confirmar que todos os componentes participantes estão saudáveis e na versão que será avaliada.
3. Nomear um responsável de QA, um responsável técnico e um aprovador de Produto/Financeiro.
4. Criar uma planilha de rastreabilidade com os IDs de usuário, produto, programa, afiliação, pedido, venda, evento e operação financeira usados.
5. Confirmar acesso somente de leitura a logs, filas, banco e dashboards operacionais necessários para evidência.
6. Definir antes da carga o limite aprovado de usuários simultâneos e transações simuladas; parar imediatamente se houver impacto fora do ambiente de teste.
7. Não reutilizar telefones, e-mails, cartões, chaves, tokens ou compradores reais.

## 7. Massa de teste mínima

| Tipo | Quantidade | Finalidade |
| --- | ---: | --- |
| Produtor | 2 | Isolar autorização entre proprietários. |
| Afiliado elegível | 10 | Fluxos de convite, concorrência e listagem. |
| Usuário não elegível | 1 | Bloqueio de convite. |
| Terceiro sem vínculo | 2 | Tentativas de acesso indevido. |
| Comprador de teste | 3 | Compras, privacidade e conciliação. |
| Produto | 5 | Ticket elegível, ticket inválido, ofertas, bump/upsell e assinatura quando disponível. |

Para carga, ampliar temporariamente para **50 a 100 afiliações** e pelo menos **50 vendas/eventos simulados**, preservando rastreabilidade. A quantidade final deve respeitar a capacidade homologada e a autorização operacional.

## 8. Etapas e casos de aceite

### Etapa A — Configuração do programa

| ID | Procedimento | Resultado esperado |
| --- | --- | --- |
| AF-001 | Criar programa com aprovação automática. | Programa criado; nova solicitação elegível fica aprovada. |
| AF-002 | Criar programa com aprovação manual. | Solicitação fica pendente até ação do produtor. |
| AF-003 | Editar comissão antes de novas solicitações. | Configuração é persistida e exibida de forma consistente. |
| AF-004 | Ativar e desativar o programa. | Estado é refletido nas telas e novas entradas seguem a regra do estado. |
| AF-005 | Definir ofertas permitidas a afiliados. | Apenas as ofertas autorizadas ficam disponíveis ao afiliado. |
| AF-006 | Configurar ticket ou oferta abaixo do mínimo. | Operação é recusada com erro explícito, sem gravação parcial. |
| AF-007 | Enviar dados inválidos e comissão fora das regras aceitas. | Validação recusa a operação e preserva a configuração anterior. |
| AF-008 | Alternar exposição de dados do comprador e pagamento de upsell. | Preferências persistem e afetam somente as novas operações aplicáveis. |

### Etapa B — Convite e ciclo de vida

| ID | Procedimento | Resultado esperado |
| --- | --- | --- |
| AF-009 | Abrir convite válido como afiliado elegível. | Produto, comissão e condição de aprovação são apresentados corretamente. |
| AF-010 | Solicitar afiliação automática. | Afiliação aprovada e acesso ao link de divulgação. |
| AF-011 | Solicitar afiliação manual e aprová-la como produtor. | Transição pendente → aprovada, auditável nas telas. |
| AF-012 | Repetir solicitação para a mesma combinação produto/usuários. | Sistema bloqueia duplicidade ativa ou pendente. |
| AF-013 | Solicitar o próprio convite. | Sistema bloqueia autoafiliação. |
| AF-014 | Solicitar convite com usuário inelegível. | Sistema bloqueia a solicitação. |
| AF-015 | Cancelar como afiliado e bloquear como produtor. | Acesso e novas atribuições deixam de ser permitidos conforme o estado final. |

### Etapa C — Autorização e privacidade

| ID | Procedimento | Resultado esperado |
| --- | --- | --- |
| AF-016 | Afiliado A consulta detalhes, configuração ou vendas do afiliado B. | Bloqueio sem vazamento de dados. |
| AF-017 | Usuário externo tenta aprovar, bloquear, mudar comissão ou ofertas. | Bloqueio por autorização. |
| AF-018 | Afiliado tenta alterar a própria comissão ou aprovar a própria solicitação. | Bloqueio. |
| AF-019 | Produtor A acessa afiliação pertencente ao produtor B. | Bloqueio. |
| AF-020 | Manipular IDs e parâmetros na requisição autenticada. | Identidade do token prevalece; não há escalonamento de acesso. |
| AF-021 | Abrir detalhe de venda como afiliado com e sem exposição de dados. | Dados do comprador só aparecem quando o programa permite. |

### Etapa D — Checkout e atribuição

| ID | Procedimento | Resultado esperado |
| --- | --- | --- |
| AF-022 | Concluir venda sem link de afiliado. | Venda não possui afiliado nem comissão. |
| AF-023 | Concluir venda por link de afiliado aprovado. | Venda registra o afiliado correto e cria a comissão esperada. |
| AF-024 | Tentar comprar com afiliado pendente, cancelado ou bloqueado. | Não há atribuição ou comissão indevida. |
| AF-025 | Comprar oferta fora do acesso autorizado do afiliado. | Checkout é bloqueado ou não atribui comissão, conforme o contrato da oferta. |
| AF-026 | Repetir para Pix e cartão disponíveis. | Atribuição, status e valores permanecem corretos por meio de pagamento. |
| AF-027 | Comprar com bump/upsell, alternando a opção de remuneração. | Comissão inclui ou exclui o upsell conforme configuração. |
| AF-028 | Alterar a comissão após criar uma venda. | Venda e comissão históricas preservam o percentual/valor originalmente gravado. |

### Etapa E — Financeiro, eventos e idempotência

| ID | Procedimento | Resultado esperado |
| --- | --- | --- |
| AF-029 | Criar venda pendente atribuída. | Há no máximo um registro de comissão para a venda; não há crédito final antecipado. |
| AF-030 | Confirmar o pagamento. | Comissão segue o estado de retenção ou split aplicável e as notificações esperadas são geradas. |
| AF-031 | Reenviar o mesmo evento/webhook de pagamento. | Não cria comissão, crédito, operação ou notificação duplicada. |
| AF-032 | Executar a liberação da comissão em carteira após o prazo configurado. | Comissão é liberada uma única vez e fica conciliável com a venda. |
| AF-033 | Validar pagamento via gateway split. | Produtor + afiliado + taxas conciliam exatamente com o valor cobrado. |
| AF-034 | Simular recusa, cancelamento e estorno. | Não há liberação financeira indevida; estado final é consistente. |
| AF-035 | Simular falha transitória de consumidor e reprocessar de forma controlada. | Retentativa recupera o processamento sem duplicar efeitos financeiros. |

### Etapa F — Notificações e recuperação

| ID | Procedimento | Resultado esperado |
| --- | --- | --- |
| AF-036 | Habilitar/desabilitar entrega por WhatsApp para uma afiliação. | Configuração persiste e não altera a configuração do produtor ou de outros afiliados. |
| AF-037 | Configurar a régua de recuperação com etapas, atraso e canais válidos. | Regras são salvas e recuperadas corretamente. |
| AF-038 | Tentar etapas, atrasos ou canais inválidos. | Validação recusa a configuração sem efeito parcial. |
| AF-039 | Disparar evento de venda. | Destinatário, canal e quantidade de notificações obedecem às preferências e não duplicam. |

### Etapa G — Telas, dados e relatórios

| ID | Procedimento | Resultado esperado |
| --- | --- | --- |
| AF-040 | Consultar produtos afiliados como cada usuário. | Lista contém somente afiliações do usuário autenticado. |
| AF-041 | Consultar “Meus afiliados” como produtor. | Status, produto, comissão e indicadores correspondem à massa de teste. |
| AF-042 | Conferir detalhe da venda pelo produtor e afiliado. | Contexto da afiliação e valores respeitam papel e privacidade. |
| AF-043 | Conferir relatórios e filtros. | Quantidade de vendas, receita, comissão e ranking conciliam com os registros de teste. |
| AF-044 | Validar estados vazios, erros e indisponibilidade controlada de dependência. | Interface informa o problema sem quebrar e sem apresentar dado incorreto como definitivo. |

### Etapa H — Escala controlada

1. Criar 50 a 100 afiliações em produtos distintos, incluindo estados aprovado, pendente e cancelado.
2. Executar acessos concorrentes às listas, detalhes e relatórios com contas de teste.
3. Criar ao menos 50 vendas/eventos simulados, incluindo uma parcela de reprocessamentos idempotentes.
4. Acompanhar latência, taxa de erro, uso de filas, mensagens em fila de erro e consistência dos totais.
5. Reconciliar amostra de 100% das vendas financeiras da carga; não basta validar apenas a tela.

O volume, concorrência e limites de aprovação devem ser registrados no relatório de execução. Sem uma linha de base homologada, o teste deve reportar métricas observadas, e não declarar um SLA não aprovado.

## 9. Evidências obrigatórias

Para cada caso, registrar:

- identificador do caso e responsável pela execução;
- data/hora, ambiente e versão dos componentes;
- IDs exclusivamente de teste envolvidos;
- resultado esperado, resultado obtido e status: aprovado, falhou, bloqueado ou não executado;
- URL, resposta HTTP ou captura de tela quando relevante;
- `order_id`, `sale_id`, `affiliate_id`, evento e operação financeira para cenários de venda;
- consultas ou logs que comprovem ausência de duplicidade;
- severidade e impacto para cada falha.

O relatório final não deve conter token, senha, número de cartão, CPF, telefone ou qualquer dado pessoal de comprador.

## 10. Classificação de falhas e decisão

| Severidade | Definição | Decisão |
| --- | --- | --- |
| Crítica | Dinheiro duplicado/perdido, comissão errada, acesso indevido a dados pessoais ou quebra ampla do checkout. | No-go até correção e reteste. |
| Alta | Fluxo central bloqueado, estado inconsistente ou relatórios materialmente incorretos. | No-go, salvo aceite explícito da direção com mitigação documentada. |
| Média | Erro com contorno seguro, sem impacto financeiro ou vazamento. | Go com ressalva e plano de correção. |
| Baixa | Defeito visual, texto ou ergonomia sem efeito operacional. | Registrar e priorizar separadamente. |

O parecer será **go** somente se todos os casos críticos e altos forem aprovados, a conciliação financeira estiver completa, não houver duplicação sob reprocessamento e a carga não apresentar degradação ou erro sem análise. Será **go com ressalvas** quando restarem apenas falhas médias/baixas com responsável e prazo definidos. Qualquer falha crítica resulta em **no-go**.

## 11. Relatório executivo de encerramento

Entregar à direção um resumo de uma página contendo:

1. decisão recomendada: go, go com ressalvas ou no-go;
2. cobertura executada versus planejada;
3. número de casos aprovados, falhos, bloqueados e não executados;
4. resultados de conciliação financeira e idempotência;
5. resultados de carga: volume, concorrência, latência observada, erros e filas;
6. falhas críticas/altas, responsáveis, mitigação e prazo de reteste;
7. limitações conhecidas do ambiente de homologação.

## 12. Referências técnicas

- `dashboard-seller/app/services/ProductAffiliateProgramService.php`
- `dashboard-seller/app/services/AffiliateDashboardService.php`
- `edge-public-api/routes/api.php`
- `edge-public-api/app/Http/Controllers/AffiliateController.php`
- `services-commerce-v2/app/Http/Controller/ProductAffiliateProgramController.php`
- `services-commerce-v2/app/Http/Controller/AffiliateController.php`
- `services-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPendingSaleEventTransferAffiliateUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPaidSaleEventTransferUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ReleaseDueSaleAffiliateTransfersUseCase.php`
- `services-commerce-v2/app/Domain/Sale/Repository/SaleAffiliateRepository.php`
