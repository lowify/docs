# Plano de QA — Programa de Afiliados

> Status: execução parcial em homologação; testes financeiros bloqueados pela configuração atual do gateway
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
| AF-005 | Vincular ofertas a uma afiliação já aprovada. | A afiliação inicia apenas com a oferta principal; somente ofertas vinculadas individualmente pelo produtor ficam disponíveis ao afiliado. |
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

## 12. Execução parcial em homologação — 02/10/2026

Ambiente: homologação na VPS, checkout `https://pay.statuslive.site`. Os registros abaixo descrevem somente verificações realmente executadas; não equivalem à aprovação do fluxo de compra ou financeiro.

| Caso/checagem | Resultado | Evidência e observações |
| --- | --- | --- |
| Abrir checkout do produto QA pela URL curta e referência de afiliado. | Aprovado, parcialmente. | HTTP 200; o formulário mostrou `QA Afiliados 20261002 — Produto Base` e preservou `ref=kAKv8B2p`. Isso confirma renderização e propagação do código, não atribuição de uma venda. |
| Abrir checkout sem informar produto. | Aprovado. | HTTP 404, conforme esperado para produto ausente. |
| Conferir configuração do produto/programa/afiliação. | Aprovado. | Produto QA `9900072`, produtor `900026`, Pix habilitado, cartão desabilitado; programa automático com comissão de 30%; afiliação `53`, usuário afiliado `900028`, aprovada. |
| Enviar forma de pagamento inválida ao endpoint do checkout, usando dados sintéticos. | Aprovado. | HTTP 422 (`validation.in`). A validação recusou a requisição antes do pagamento. Nenhuma venda QA foi encontrada após a tentativa. |
| Confirmar que a tentativa não acionou o mock Pagsmile. | Aprovado. | Nenhuma chamada nova apareceu nos logs recentes do container `pagsmile-mock`. |
| Conferir filas após a tentativa. | Sem efeito da tentativa observado. | Snapshot: `sales:events:pending=0`, `sales:events:paid=0`, `wallet:extract:events=0`, `wallet:extract:affiliate-releases=3`. As filas não foram alteradas nem consumidas por esta rodada; o backlog de 3 itens deve ser preservado e investigado separadamente antes de qualquer teste que execute o consumidor de liberação. |
| Autorizar/capturar Pix e confirmar evento pago. | Bloqueado; não executado. | O gateway Pix padrão é `efi_bank`, com `EFIBANK_SANDBOX=false` e endpoint de produção. O seller QA não tem gateway prioritário e não possui subconta Pagsmile; o produtor também está sem checkout transparente habilitado. Não foi criada cobrança nem forçado status pago. |

Não há compra válida nem comissão de venda gerada nesta rodada. Os casos AF-023 e AF-029–035 permanecem não executados até existir um caminho de pagamento sandbox comprovadamente isolado. Em particular, a presença de um mock Pagsmile na VPS não basta: o checkout padrão não o seleciona para o seller e falta a subconta de teste exigida pelo fluxo.

### Próximo teste manual — AF-QA-003: isolamento de acesso entre afiliados e produtores

Este é um teste somente de leitura no Dashboard Seller; não iniciar compra, não salvar configurações e não consumir filas.

**Contas de QA**

| Papel | ID | E-mail |
| --- | ---: | --- |
| Afiliado vinculado ao produto QA | 900028 | `qa-affiliate-20261002-affiliate-01@example.test` |
| Afiliado sem vínculo com esse produto | 900029 | `qa-affiliate-20261002-affiliate-02@example.test` |
| Produtor proprietário do produto | 900026 | `qa-affiliate-20261002-producer-01@example.test` |
| Outro produtor, sem propriedade sobre o produto | 900027 | `qa-affiliate-20261002-producer-02@example.test` |

As credenciais dessas contas são as já distribuídas para a massa QA; não registrar senhas neste documento. Faça logout e encerre a sessão entre cada conta, ou use perfis privados separados do navegador.

**Passos**

1. Acesse `https://dashboard.statuslive.site` como o afiliado `900028` e abra **Produtos afiliados** (rota `/products.php?view=affiliated`). Confirme que o produto `9900072` aparece com comissão de 30%.
2. Faça logout. Entre como o afiliado `900029` e abra a mesma tela. Confirme que o produto `9900072` não aparece.
3. Ainda como `900029`, tente abrir diretamente `/affiliate_product_detail.php?affiliate_id=53`. Confirme que a afiliação não é exibida nem seus dados/configurações são retornados.
4. Faça logout. Entre como o produtor `900026` e abra **Afiliados** (rota `/affiliates.php`). Confirme que somente o vínculo de teste aprovado (`affiliate_id=53`, usuário `900028`) aparece para o produto QA.
5. Faça logout. Entre como o produtor `900027` e tente abrir diretamente `/affiliate_detail.php?affiliate_id=53`. Confirme que não consegue ver nem alterar a afiliação pertencente ao produtor `900026`.
6. Registre para cada etapa o status observado (aprovado/falhou), horário, URL e captura de tela sem dados pessoais além dos e-mails de teste. Não use botões de aprovar, remover, bloquear ou salvar.

**Critério de aprovação:** o produto e a afiliação são visíveis apenas às contas autorizadas; tentativas diretas de acesso cruzado não exibem informações e não alteram registros. Se uma sessão não abrir ou uma rota apresentar resultado diferente, pare nessa etapa e registre a resposta sem tentar contornar permissões.

**Cobertura relacionada:** AF-016, AF-019 e AF-040, em escopo parcial de leitura. Esta execução manual não substitui teste de API/JWT nem valida as operações de alteração.

**Resultado da execução:** aprovado. O afiliado vinculado `900028` visualizou o produto com comissão de 30%; o afiliado sem vínculo `900029` não visualizou o produto e recebeu bloqueio sem exposição de informações ao acessar diretamente `affiliate_id=53`; o produtor proprietário `900026` visualizou corretamente a afiliação; e o produtor sem propriedade `900027` recebeu bloqueio ao acessar diretamente `affiliate_id=53`.

**Validação complementar:** aprovado. O afiliado autorizado `900028` abriu diretamente `/affiliate_product_detail.php?affiliate_id=53` e visualizou corretamente o detalhe do produto afiliado, sem alterar configurações.

**Relatório da afiliada:** aprovado. Como `900028`, a tela de relatórios de afiliados exibiu todos os indicadores zerados, coerentes com a inexistência de vendas QA válidas, comissões ou lançamentos financeiros para a massa de teste.

**Detalhe pelo produtor:** aprovado. Como `900026`, o detalhe da afiliação de `900028` exibiu corretamente a comissão configurada de 30% e indicadores de vendas/comissão zerados, coerentes com a massa QA sem compras válidas.

**Link de divulgação:** aprovado. Como `900028`, o link copiado do detalhe da afiliação continha `ref=kAKv8B2p`; aberto em janela anônima, carregou o checkout do produto `QA Afiliados 20261002 — Produto Base`. Nenhum pagamento foi iniciado.

**Afiliação automática por convite:** aprovado. A conta QA `qa-affiliate-20261002-affiliate-03@example.test` (`900030`), sem vínculo anterior, abriu o convite do programa automático do produto QA e teve a solicitação aprovada. O produto ficou disponível como afiliado com comissão de 30%.

**Solicitação duplicada:** aprovado. Ao abrir novamente o mesmo convite como `900030`, já aprovado, a tela exibiu “Afiliação aprovada” e não permitiu continuar com uma nova solicitação. Nenhuma afiliação duplicada foi criada.

**Autoafiliação:** aprovado. A conta proprietária do produto, `qa-affiliate-20261002-producer-01@example.test` (`900026`), abriu o convite e recebeu bloqueio, sem botão para solicitar afiliação.

**Usuário inelegível:** aprovado. A conta externa QA recebeu a mensagem “Este convite só pode ser acessado por um seller válido.” e não conseguiu solicitar afiliação.

**Cancelamento pela afiliada:** aprovado. A afiliação QA `54`, criada para `qa-affiliate-20261002-affiliate-03@example.test` (`900030`), foi cancelada pela própria afiliada; depois da confirmação, o produto deixou de aparecer em “Produtos afiliados”.

**Estado cancelado pelo produtor:** aprovado. Como `900026`, o produtor visualizou a afiliação `54` como desativada, sem acesso ativo ao produto/link pela afiliada cancelada.

**Acesso direto após cancelamento:** aprovado. A conta `900030` recebeu bloqueio ao abrir diretamente o detalhe de `affiliate_id=54`; os dados do produto não foram expostos.

**Recomposição da afiliação principal de QA:** concluída. Durante a navegação posterior, a afiliação inicial `53` de `900028` foi cancelada e deixou de ser utilizável; isso não corresponde ao caso planejado de bloqueio pelo produtor. A conta `900028` solicitou novamente a afiliação automática e recebeu o vínculo ativo `58`, com comissão de 30% e código de referência `VqJVhJoT`. Para testes futuros, usar `affiliate_id=58` e `ref=VqJVhJoT`; o vínculo `53` e a referência histórica `kAKv8B2p` permanecem cancelados.

**Bloqueio pelo produtor:** aprovado. O produtor `900026` confirmou que o detalhe `affiliate_id=57` pertencia a `qa-affiliate-20261002-affiliate-06@example.test` e cancelou o vínculo. A afiliação `57` foi persistida como `canceled`; como `900033`, o produto deixou de aparecer em “Produtos afiliados” e o acesso direto ao detalhe foi bloqueado sem exposição de dados.

**Reentrada após bloqueio pelo produtor:** comportamento observado. A mesma conta `900033` abriu o convite de um programa automático, recebeu a nova afiliação `59` como `approved` e voltou a visualizar o produto. O vínculo cancelado `57` foi preservado; não houve reativação nem duplicidade de vínculo ativo.

**Privacidade de dados do comprador:** aprovado, em escopo de configuração. O produtor ativou a opção de exposição de dados ao afiliado, salvou e confirmou a persistência ao reabrir o programa; em seguida desativou, salvou e confirmou o retorno ao estado original. Como não há venda QA válida, o efeito da opção no detalhe de venda permanece não executado.

**Remuneração de upsell:** bloqueado. A opção `pay_upsell` não está disponível na tela de configuração do programa de afiliados, embora o campo exista no modelo de dados. Não foi possível validar persistência, atribuição ou cálculo de comissão de upsell.

**Comissão abaixo do mínimo:** aprovado, com ressalva de experiência. A tentativa de salvar 5% foi recusada e a comissão vigente de 30% foi preservada. A mensagem veio da validação nativa do navegador, em vez do padrão visual da aplicação, o que pode ficar oculto quando o campo está em outra aba.

**Meios de pagamento exibidos no checkout:** aprovado, em escopo de apresentação. Com a referência ativa `VqJVhJoT`, o checkout carregou o produto QA corretamente e exibiu somente Pix; a opção de cartão não foi apresentada. Nenhum formulário foi enviado e nenhuma cobrança foi criada.

**Massa para testes de ofertas:** preparada. Foi criada a oferta ativa `3700` — `QA Oferta Afiliados 20261004`, R$ 197,00, slug `d15334ca` — para o produto QA `9900072`. Ela ainda não foi liberada no programa de afiliados.

**Oferta ao iniciar afiliação:** divergência registrada para hotfix. A regra de negócio definida durante o QA é que toda nova afiliação deve iniciar somente com a oferta principal. No comportamento atual, ao selecionar a oferta `3700` no programa, ela já apareceu no convite e no detalhe da nova afiliação `60` de `qa-affiliate-20261002-affiliate-07@example.test` (`900034`), antes de uma vinculação individual pelo produtor. O vínculo `affiliate_offers` foi criado automaticamente; este comportamento deve ser removido.

**Vinculação e remoção individual de oferta:** aprovado. Após o produtor vincular novamente a oferta `3700` à afiliação `60`, a afiliada `900034` voltou a vê-la na listagem. Ao removê-la, a afiliada passou a visualizar apenas a oferta principal. Com a oferta removida, a URL pública correta `go.php?offer=d15334ca&ref=CD6UOudC` exibiu “Oferta indisponível — O link de oferta informado não foi encontrado ou não está mais ativo.”, sem carregar checkout. Comissão e status não foram alterados. A compra/atribuição permanece bloqueada pela indisponibilidade de gateway sandbox.

**Oferta vinculada — acesso público:** aprovado, em escopo de carregamento. Após o produtor vincular novamente a oferta `3700` à afiliação `60`, a mesma URL pública com `ref=CD6UOudC` voltou a carregar o checkout da oferta. Nenhum pagamento foi iniciado. Este contraponto confirma a aplicação do vínculo individual para listagem e abertura do checkout.

**Checkout sem referência de afiliado:** aprovado, em escopo de carregamento. Em janela anônima, `checkout?product_id=lvJojy`, sem o parâmetro `ref`, abriu normalmente o checkout do produto QA. Nenhum pagamento foi iniciado; por não haver meio sandbox para concluir uma venda, a confirmação de ausência de atribuição/comissão permanece pendente.

**Isolamento entre afiliações ativas:** aprovado. Como `qa-affiliate-20261002-affiliate-07@example.test` (`900034`), a tentativa de abrir diretamente o detalhe da afiliação ativa `58`, pertencente a outra conta, exibiu “Produto afiliado não encontrado.” Nenhum detalhe, link, comissão ou configuração foi exposto.

**Gestão por seller sem propriedade:** aprovado. Como `qa-affiliate-20261002-affiliate-02@example.test` (`900029`), a tentativa de abrir diretamente a gestão da afiliação ativa `60` exibiu “Afiliado não encontrado.” Comissão, ofertas, status e ações de gestão não foram exibidos.

**Gestão por outro produtor:** aprovado. Como `qa-affiliate-20261002-producer-02@example.test` (`900027`), a tentativa de abrir diretamente a gestão da afiliação ativa `60`, pertencente ao produtor QA `900026`, exibiu “Afiliado não encontrado.” Não houve exposição de detalhes nem possibilidade de alteração.

**Manipulação de parâmetros autenticados:** aprovado. Ainda como o produtor sem propriedade `900027`, a URL da afiliação `60` foi aberta com `seller_id=900026` e `producer_id=900026` adicionados manualmente. A resposta permaneceu “Afiliado não encontrado.” Os parâmetros de URL não prevaleceram sobre a identidade da sessão.

**Manipulação de parâmetros autenticados:** aprovado, em escopo de URL. Ainda como o produtor sem propriedade `900027`, a URL de gestão de `60` recebeu adicionalmente `seller_id=900026&producer_id=900026`; a resposta permaneceu “Afiliado não encontrado.” Os parâmetros injetados não alteraram a identidade/autorização da sessão nem expuseram dados.

**Desativação do programa para afiliações existentes:** aprovado. Após o produtor desativar temporariamente o programa, a afiliada já aprovada `qa-affiliate-20261002-affiliate-07@example.test` não visualizou nenhum produto na aba “Produtos afiliados”. O comportamento vigente, portanto, suspende também a visibilidade/acesso de vínculos já aprovados enquanto o programa estiver desativado, além de impedir novas adesões. Reativar o programa antes dos próximos testes.

**Reativação do programa para afiliações existentes:** aprovado. Após a reativação pelo produtor, `qa-affiliate-20261002-affiliate-07@example.test` voltou a visualizar o produto na aba “Produtos afiliados”, sem recriar a afiliação. No detalhe, a oferta principal e `QA Oferta Afiliados 20261004` voltaram a ficar visíveis. O acesso e as ofertas vinculadas foram restaurados corretamente.

**Venda simulada, confirmação e entrega:** aprovado, com ressalva de comunicação. A venda QA `9901302` (`ord_5b299376eaa2347e`) foi criada pelo fluxo interno de checkout transparente, sem gateway, como `pending`, para o produto `9900072` e a afiliação `60`. A confirmação manual pelo processador interno a mudou para `paid` e gravou `confirmed_at`. Foi criado um único registro em `sales_affiliates`: comissão de 30%, R$ 58,11, status `pending`, método `wallet`; não houve duplicidade. O evento de entrega gerou registros para WhatsApp e e-mail, ambos `skipped` com `communication_credit_unavailable`, o que impede validar o envio efetivo sem crédito/configuração de comunicação.

**Idempotência da confirmação de pagamento:** aprovado. A mesma confirmação da venda `9901302` foi reaplicada após o status `paid`; o processador recusou a operação porque não havia venda pendente para o `transaction_id` QA. Antes e depois, permaneceram exatamente uma comissão em `sales_affiliates` (R$ 58,11) e duas tentativas de entrega; não houve nova comissão, crédito ou entrega.

**Liberação de comissão em carteira:** aprovado, em simulação controlada. A comissão QA `245` da venda `9901302` foi colocada em retenção com data de liberação vencida e processada pelo caso de uso oficial de liberação. O processo encontrou um item, liberou um item e não apresentou falhas; a comissão mudou de `held` para `released`. Foi necessário usar uma data explicitamente anterior no fuso de São Paulo, pois a primeira data calculada pelo banco em UTC ainda era futura para o processo.

**Idempotência da liberação:** aprovado. A execução imediata repetida do mesmo caso de uso encontrou zero itens elegíveis (`total=0`, `released=0`, `failed=0`); a comissão `245` permaneceu `released`, sem nova liberação.

**Venda sem referência de afiliado:** aprovado, em simulação controlada. A venda QA `9901304` foi criada e confirmada pelo fluxo interno sem o parâmetro `ref`. Ela permaneceu com `affiliate_id = NULL` e não criou registro em `sales_affiliates`, confirmando ausência de atribuição/comissão.

**Estorno após pagamento:** bloqueado no caminho manual atual. A venda QA atribuída `9901303` foi criada, confirmada e gerou comissão pendente de R$ 58,11. A tentativa de transição para `refunded` pelo mesmo processador manual foi recusada, pois ele só atualiza vendas ainda `pending`; retornou HTTP 404 sem alterar a venda. É necessário acionar o fluxo específico de reembolso para validar AF-034 e a reversão financeira.

**Referência de afiliado cancelado:** aprovado, em simulação controlada. A venda QA `9901305` foi criada e confirmada informando a referência histórica cancelada `kAKv8B2p`. O checkout interno resolveu `affiliate_id = NULL` e não criou registro em `sales_affiliates`.

**Imutabilidade da comissão histórica:** aprovado. A venda `9901303` mantém comissão gravada de 30% e R$ 58,11. A comissão atual da afiliação `60` foi alterada temporariamente para 25% e a venda histórica não foi alterada; ao fim, a comissão da afiliação foi restaurada para 30%.

**Limite mínimo de oferta para afiliação:** aprovado. A oferta QA `3701` — `teste erro`, R$ 1,00 — foi criada ativa com sucesso, o que é válido para uma oferta Pix comum cujo mínimo é R$ 1,00. O mínimo específico para vincular uma oferta ao programa/afiliação é R$ 20,00 (`MINIMUM_TICKET_FOR_AFFILIATE=20.00`): na aba de afiliados, a oferta `3701` não foi exibida nas opções elegíveis e, portanto, não pôde ser vinculada. A limpeza da oferta não pôde ser concluída: a tentativa de remoção exibiu “Não foi possível salvar a oferta.”; a oferta permanece como massa residual até correção.

**Decisão de negócio pendente:** definir se um produtor que removeu uma afiliação deve impedir futuras solicitações do mesmo seller, ou se a reentrada automática atual deve continuar permitida. O comportamento vigente permite nova solicitação em programa automático; este ponto não deve ser classificado como falha sem decisão explícita de Produto/Operações.

**Aprovação manual:** aprovado. Após o programa QA ser alterado temporariamente para aprovação manual, `900030` reenviou uma solicitação e recebeu a afiliação pendente `55`. O produtor `900026` aprovou a solicitação com sucesso; como `900030`, o produto voltou a aparecer em “Produtos afiliados”. Restaurar o programa automático é a pendência de limpeza deste caso.

**Comissão após edição do programa:** aprovado. A comissão do programa QA foi alterada temporariamente de 30% para 35% e a tela exibiu o novo percentual. A inspeção confirmou que as afiliações existentes `53`, `54` e `55` também passaram para 35%, comportamento esperado: a comissão do programa é o valor default propagável para vínculos que ainda o utilizam. Não foi criada afiliação para `qa-affiliate-20261002-affiliate-05@example.test` (`900032`), portanto este caso não valida a criação de novo vínculo. Restaurar a comissão padrão de 30% é a pendência de limpeza deste caso.

**Nova afiliação após restauração da comissão:** aprovado. `qa-affiliate-20261002-affiliate-05@example.test` (`900032`) confirmou o convite automático, recebeu a afiliação e visualizou o produto com comissão de 30%.

**Programa desativado:** aprovado. O programa do produto QA foi desativado temporariamente. A conta sem vínculo `qa-affiliate-20261002-affiliate-06@example.test` (`900033`) abriu o convite e recebeu “Link de afiliação inválido e/ou expirado.”, sem opção de confirmar nem criação de afiliação. Reativar o programa é a pendência de limpeza deste caso.

**Programa reativado:** aprovado. O programa foi reativado com aprovação automática e comissão de 30%. A mesma conta `900033` abriu novamente o convite, teve a afiliação aprovada e visualizou o produto com 30%, comprovando a restauração imediata da elegibilidade.

**Comissão individual:** aprovado. O produtor alterou temporariamente a comissão da afiliação `53` de 30% para 25%. O programa e todas as demais afiliações QA permaneceram em 30%, confirmando o isolamento da edição individual. A comissão de `53` foi restaurada para 30% ao encerrar o caso.

**Gestão indevida pela afiliada:** aprovado. Como `900028`, o acesso direto a `/affiliate_detail?affiliate_id=53` falhou sem exibir detalhes ou campos de gestão do produtor; a afiliada não conseguiu alterar comissão, ofertas ou status.

**Configuração de entrega por WhatsApp:** falhou. Como `900028`, ao salvar a configuração de entrega para `affiliate_id=53`, a interface exibiu “Não foi possível salvar a configuração de entrega.” A requisição `PUT /api/affiliates/affiliated-products/53/sale-delivery` recebeu HTTP 404 no Edge Public API; as leituras de `sale-delivery` e `sale-recovery` para a mesma afiliação também retornaram HTTP 404. A configuração não foi persistida nem alterada. AF-036–039 ficam bloqueados até correção e reteste.

### Hotfixes identificados — pendentes de implementação

1. Na tela de detalhe do produto afiliado, a tabela de entrega está renderizada fora da aba correspondente. Corrigir a associação/estrutura de abas para que a tabela apareça somente na aba de entrega.
2. Exibir de forma explícita o percentual de comissão (`%`) em um ponto visível da página de detalhe do produto afiliado, além de qualquer valor monetário apresentado.
3. Corrigir/publicar no Edge Public API as rotas de entrega e recuperação de produto afiliado: `GET`/`PUT /api/affiliates/affiliated-products/{affiliate_id}/sale-delivery` e `GET`/`PUT /api/affiliates/affiliated-products/{affiliate_id}/sale-recovery`. Elas existem no contrato esperado pelo Dashboard e no Commerce V2, mas retornam HTTP 404 no ambiente homologado atual.
4. Preservar o `invite_code` quando o visitante do convite precisar autenticar. Após login/cadastro bem-sucedido, redirecionar para a tela do mesmo convite, em vez da home do Dashboard.
5. Substituir o aviso isolado de convite inelegível por um painel de erro completo, com explicação clara e botão para voltar ao início (ou à tela apropriada da conta), sem deixar o usuário em uma página sem ação disponível.
6. Em `affiliate_detail.php`, reutilizar o componente de seleção de tipo de produto (entrega única ou assinatura) dentro de “Editar afiliação” e deixar o botão de salvar com a variante visual `primary`.
7. Em “Editar comissão”, acrescentar um toggle para indicar comissão customizada. Com o toggle desligado, ocultar o campo numérico e restaurar o valor default do programa; com o toggle ligado, exibir o campo para informar o percentual customizado.
8. Expor na tela de configuração do programa de afiliados a opção de remunerar upsells (`pay_upsell`), persistindo o valor no programa e deixando claro o efeito sobre novas vendas. Sem essa opção, AF-008 e AF-027 permanecem bloqueados no escopo de upsell.
9. Substituir a validação nativa de navegador da comissão por validação no padrão da tela, com feedback em toast/alerta visível e foco na aba/campo inválido. O erro não pode ficar oculto quando a configuração de afiliados estiver em outra aba.
10. Ajustar a regra de ofertas por afiliação: toda afiliação nova deve iniciar somente com a oferta principal, sem herdar/exibir automaticamente ofertas adicionais configuradas no programa. Depois da aprovação, somente o produtor poderá vincular ofertas adicionais de forma individual. Ao desvincular uma oferta, ela deve desaparecer da listagem da afiliada e a URL dessa oferta com a referência da afiliada não deve carregar checkout nem permitir atribuição/comissão.
11. Corrigir a remoção de oferta no Dashboard: o modal de confirmação está sendo renderizado abaixo do modal de edição atual. Ao acionar a remoção, fechar o modal atual antes de abrir a confirmação. Além disso, a confirmação posterior falha com “Não foi possível salvar a oferta.”; corrigir a persistência e permitir a remoção/desativação efetiva da oferta.
12. Corrigir privacidade de dados do comprador nas telas da afiliada: com a exposição desativada no programa, a listagem de vendas ainda exibiu `QA Refund 20261005` e `qa-refund-20261005@example.com`. Ocultar nome, e-mail, telefone, documento e demais identificadores tanto na listagem quanto no detalhe; o produtor continua com acesso conforme sua permissão.

Os itens 1, 2, 4 e 5 são melhorias/correções de interface registradas para implementação posterior. O item 3 é falha funcional de integração e bloqueia a validação de entrega, recuperação e notificações da afiliada.

### Pré-condição pendente para retomar compras

Antes de executar AF-023 e AF-029–035, a equipe técnica deve fornecer um método de pagamento que comprove sandbox/mock de ponta a ponta para o seller QA (incluindo conta/subconta e confirmação de pagamento), ou habilitar um fluxo QA explicitamente isolado. Não alterar o gateway global para contornar a falta dessa pré-condição. Após a configuração, confirmar endpoint sandbox, identificar como simular pagamento e verificar que eventos e operações financeiras atingem somente registros QA. O backlog preexistente da fila de liberações precisa ser tratado pelo responsável técnico sem ser removido ou usado como massa do teste.

## 13. Referências técnicas

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
