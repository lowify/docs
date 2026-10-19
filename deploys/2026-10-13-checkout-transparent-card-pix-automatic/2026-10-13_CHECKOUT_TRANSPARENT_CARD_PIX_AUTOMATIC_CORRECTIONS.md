# Checkout Transparente — revisão e ajustes para o dev

Data: 2026-10-13.

Objetivo: conferir o que já funciona e ajustar os pontos necessários para que cartão e Pix Automático operem conforme as regras combinadas. Este documento reúne o comportamento esperado, o problema observado e uma sugestão de correção.

A revisão inicial foi feita nas branches `feat/checkout-transparent-card`, nas versões registradas no [roteiro de revisão](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW.md). Ela não substitui a conferência do dev na versão que será entregue. Nenhuma correção nos serviços foi implementada por este documento.

## Como usar este documento

Antes de alterar cada item, o dev deve conferir o código atual e realizar as verificações técnicas pertinentes. Se já estiver correto, registrar a evidência e não refazer a implementação. Se estiver diferente, explicar brevemente a diferença e aplicar o ajuste.

As responsabilidades ficam separadas:

- **Dev:** analisar as regras no código, implementar os ajustes, fazer as verificações técnicas e registrar as mudanças. Preparar as condições necessárias para testar e corrigir os problemas encontrados.
- **Responsável pelo produto (solicitante):** executar o roteiro de testes funcionais, conferir o comportamento no checkout/dashboard e registrar o resultado de cada cenário. Essa execução não fica atribuída ao dev.

Os trechos “Como conferir” descrevem o resultado esperado. A conferência funcional fica com o responsável pelo produto; verificações de banco, filas, segurança, concorrência e simulação de falhas ficam com o dev. Quando um cenário exigir uma condição técnica, o dev a prepara em ambiente de teste e o responsável pelo produto confere o efeito visível, sem precisar operar banco ou filas.

Para cada regra e item C01–C14, registrar:

- **Situação atual:** já atende, atende em parte, precisa de ajuste ou ainda não foi possível verificar.
- **Análise do dev:** como funciona hoje, com referência ao código e ao teste realizado.
- **Resultado técnico do dev:** o que foi alterado, os commits e a verificação técnica realizada; ou por que não foi necessário alterar. A validação funcional pelo responsável do produto deve ser registrada separadamente, sem ser marcada como concluída antes da execução.

As situações abaixo começam pendentes dessa análise. “Regra confirmada” significa que o comportamento foi combinado com o produto, não que já esteja implementado.

## Regras combinadas — conferir uma a uma

| Comportamento esperado | O que a revisão inicial indica | Item | Análise do dev |
| --- | --- | --- | --- |
| Enviar somente token ou dados criptografados quando o cartão em aberto não for necessário. Não guardar CVV. | Alguns fluxos ainda enviam campos do cartão junto do token. Não foi encontrada gravação explícita de CVV no caminho CT; registros do ambiente ainda precisam ser conferidos. | C02 | Ajustado e verificado tecnicamente; validação funcional pendente. |
| Uma repetição da mesma tentativa não pode cobrar novamente. Usar um nonce: identificador aleatório mantido ao reenviar. | A identificação atual muda se o token ou os dados criptografados mudarem. | C03 | Ajustado e verificado tecnicamente; validação funcional pendente. |
| A assinatura só é cancelada por cancelamento explícito, nunca por atraso ou falta de pagamento. | O tratamento de cancelamento está incompleto; há situações que podem reativar uma assinatura cancelada. | C06 | Pendente |
| A cobrança de serviço da Lowify acontece uma vez no cartão, na primeira parcela/confirmação elegível, e no pagamento de cada recorrência Pix. | Há cobrança de serviço no fluxo avulso; não foi encontrado o caminho equivalente por parcela Pix recorrente. | C08 | Pendente |
| Cada método pode estar ativo em apenas um gateway por seller. Dois cartões de crédito ativos em gateways diferentes não são permitidos. | Escolher um padrão não garante que os demais estejam desativados. | C10 | Pendente |
| Só disponibilizar um método depois de aprovado. Enquanto não aprovado, explicar isso em um modal. | A habilitação pode ocorrer antes de terminar a validação. | C10 | Pendente |
| Usar no cartão as mesmas regras comerciais do Commerce V2, como valor e número de parcelas. | O caminho transparente remove a informação de parcelas antes de enviá-la ao Commerce. | C11 | Pendente |
| Disponibilizar cartão RisePay após concluir os ajustes e testes necessários. | O código existe, mas o cartão está desabilitado. | C12 | Pendente |
| Cartão disponível no checkout também aparece em Editar Produto, sem ativar automaticamente todos os produtos. | A edição usa condições próprias de disponibilidade; o dev precisa conferir a tela e o salvamento. | C13 | Pendente |
| Todos os erros de cartão têm mensagens compreensíveis e seguras, sem mostrar respostas técnicas do gateway. | Há tratamento diferente conforme a etapa; o Banking V2 tem um exemplo de padronização no fluxo Cielo. | C14 | Pendente |

## C01 — incluir todos os componentes na atualização

**O que revisar:** o plano original lista sete repositórios, mas a confirmação de uma recorrência também depende do edge-webhook principal e do Commerce V2.

**Como ajustar:** incluir esses componentes na atualização, ou comprovar que suas versões compatíveis já foram publicadas. A rota de confirmação já está na branch da feature do edge-webhook (`74be04f3`); não é necessário criá-la novamente. O problema é deixar essa etapa fora da atualização, não a existência de dois webhooks.

**Como conferir:** um pagamento recebido pelo webhook próprio do CT chega ao Commerce e confirma a venda correta. Ao integrar a branch do Commerce, preservar as correções mais novas de valor bruto e taxas da `main`.

### Registro do dev — C01

- **Situação atual:** atende em parte; o roteiro de atualização foi corrigido e a conferência funcional entre webhook e Commerce permanece pendente.
- **Análise do dev:** o plano de deploy tratava apenas sete componentes, embora a confirmação de assinatura também atravesse o `edge-webhook` principal e o Commerce V2. A rota necessária já existia na feature do webhook; a lacuna era operacional, no roteiro de publicação.
- **Resultado técnico do dev:** atualizado o roteiro de deploy para incluir Commerce V2 e `edge-webhook`, sua ordem de publicação, validação da fila `commerce_subscription_actions_queue` e rollback compatível. Registrado que o Commerce V2 deve partir da `main` com a feature integrada, preservando as correções recentes de valor bruto e taxas. Nenhuma rota foi recriada. Commit pendente de consolidação; o responsável do produto ainda deve confirmar o fluxo visível de uma assinatura ponta a ponta.

## C02 — não enviar dados de cartão sem necessidade

**O que revisar:** em alguns fluxos o navegador gera o token, mas ainda envia número, validade e CVV junto dele. Remover esses dados só antes do Commerce não evita que eles passem pelos componentes anteriores.

**Como ajustar:** depois de gerar o token, enviar apenas ele e os dados necessários à compra. Para RisePay, enviar o pacote criptografado, sem uma cópia do cartão em aberto. Manter uma exceção somente quando o fluxo realmente exigir, como algum caminho específico de autenticação do cartão; a exceção precisa ser validada no servidor, não apenas escolhida pelo navegador.

Não foi encontrada gravação explícita de CVV ou do pacote criptografado no caminho CT examinado. O dev também deve conferir se registros de erro ou ferramentas de monitoramento capturam esses dados.

**Como conferir:** revisar os dados enviados em cada fluxo de cartão e os registros gerados. Não pode haver CVV guardado, inclusive dentro de um pacote criptografado mantido como histórico. Os fluxos antigos que precisam de tratamento específico devem continuar funcionando.

### Registro do dev — C02

- **Situação atual:** atende após ajuste técnico; a conferência funcional pelo responsável do produto permanece pendente.
- **Análise do dev:** o checkout tokenizava o cartão, porém alguns campos em aberto ainda seguiam na requisição. O CT não precisa deles para tentativas transparentes tokenizadas; no caminho RisePay, o cartão continua dentro do pacote criptografado exigido pelo provedor.
- **Resultado técnico do dev:** o Front Checkout remove número, validade, CVV e dados do titular antes do envio de qualquer tentativa de cartão. A Edge Public API passou a recusar esses campos quando recebidos diretamente e não os encaminha ao Commerce. Foi exercitada uma requisição direta com dados em aberto: recebeu `422` antes de criar venda. A revisão do fluxo não encontrou persistência explícita de CVV; a validação funcional e a revisão de observabilidade no ambiente seguem pendentes. Commit pendente de consolidação.

## C03 — reconhecer a mesma tentativa quando houver reenvio

**O que revisar:** hoje a identificação da tentativa depende do token ou do pacote criptografado. Se eles mudarem durante um reenvio, a mesma intenção de compra pode parecer uma tentativa nova.

**Como ajustar:** gerar uma identificação aleatória, chamada nonce, uma vez por tentativa e mantê-la no duplo clique e nas repetições da requisição. Usá-la junto dos identificadores existentes de seller, cobrança e método. Quando houver pacote criptografado, incluir o nonce nele e conferir se corresponde ao enviado pela requisição.

Redis pode ajudar a impedir duas execuções ao mesmo tempo. O banco também deve guardar a identificação da tentativa, para que perder ou expirar esse controle no Redis não permita cobrar outra vez. Se o pagamento foi recusado de forma conhecida, uma nova tentativa pode receber outro nonce. Se a resposta ficou desconhecida, consultar o resultado antes de permitir outra cobrança.

**Como conferir:** duplo clique, dois envios simultâneos, nova criptografia com o mesmo nonce e reinício do Redis não duplicam a cobrança. Mudanças no valor ou nas parcelas não são aceitas silenciosamente como a mesma tentativa. Não exigir novos campos de tempo neste ajuste.

### Registro do dev — C03

- **Situação atual:** atende após ajuste técnico; a conferência funcional pelo responsável do produto permanece pendente.
- **Análise do dev:** a chave de idempotência era derivada do token ou do pacote criptografado, que pode mudar no reenvio. O checkout agora gera um nonce UUID por intenção de pagamento; a Edge o usa como chave de idempotência e o CT confere a mesma informação dentro do pacote RisePay.
- **Resultado técnico do dev:** atualizados Front Checkout, Edge Public API e CT API para exigir e propagar `card_attempt_nonce`; a tentativa RisePay exige que o nonce externo seja igual ao nonce do pacote criptografado. Em integração local com o mock Pagar.me, uma tentativa válida foi aprovada e a repetição com o mesmo nonce retornou a mesma tentativa, sem uma segunda cobrança. A validação rejeita nonce inválido e não aceita divergência entre nonce e chave de idempotência. Commit pendente de consolidação; ainda faltam os cenários funcionais de duplo clique, concorrência e reinício de Redis conduzidos pelo responsável do produto.

## C04 — usar a credencial renovada do Mercado Pago em todos os métodos

**O que revisar:** ao configurar Pix/cartão, o sistema guarda cópias da credencial de acesso. A renovação atualiza a integração, mas a cobrança pode continuar lendo a cópia antiga do método.

**Como ajustar:** na renovação, atualizar também as credenciais dos métodos que usam a mesma conta Mercado Pago. Fazer essas gravações juntas: ou todas são concluídas, ou nenhuma é aplicada. Atualizar a informação de validade e incluir métodos desabilitados, sem ativá-los automaticamente.

Para este pacote, essa alteração pode preservar a estrutura atual. Não é necessário redesenhar todo o armazenamento. Usar o mesmo cuidado na reconexão da conta, não alterar credenciais de outra conta e aceitar uma resposta de renovação repetida sem erro.

**Como conferir:** renovar uma credencial de teste e verificar que Pix e cartão usam a nova versão. Um método desabilitado também usa a versão nova quando voltar a ser habilitado. Nenhuma credencial aparece nos registros de erro.

### Registro do dev — C04

- **Situação atual:** atende após ajuste e homologação técnica de token manual válido; o teste funcional visual dos caminhos manual e OAuth no Dashboard permanece separado, para registro pelo responsável do produto.
- **Análise do dev:** a renovação por fila atualizava apenas as chaves da integração. O ajuste propaga a nova versão para Pix, cartão e os demais métodos da mesma integração, inclusive os desabilitados, dentro da mesma transação. Na edição Mercado Pago, o seller escolhe OAuth **ou** `access_token` manual no mesmo padrão visual da criação; ambos atuam na integração existente. OAuth confere o identificador da conta retornado pelo Mercado Pago antes de gravar qualquer credencial. Durante a reprodução do token inválido, o Dashboard recebeu o campo, porém o container ativo da Edge Public API ainda usava uma versão anterior de `UpdateIntegrationUseCase` que encaminhava apenas `user_id` e `name`; assim, descartava `access_token` e respondia sucesso.
- **Resultado técnico do dev:** CT, Edge e Dashboard passam a propagar a credencial renovada em transação; token manual inválido retorna `422` sem gravar ou alterar o nome. A propagação para Pix/cartão, preservação de métodos desabilitados, `php -l`, inicialização do Hyperf e `git diff --check` foram verificados; o teste visual manual/OAuth no Dashboard permanece pendente.

## C05 — retomar operações que ficaram pela metade

**O que revisar:** uma assinatura pode ser salva, mas sua tarefa não ser enviada. Um processo também pode parar depois de retirar uma tarefa da fila. Na Efí, a criação possui várias etapas; repetir tudo pode criar recursos novamente.

**Como ajustar:** criar um processo de recuperação que leia as operações incompletas no banco, saiba qual etapa já terminou e retome a partir dela. Guardar o progresso e os identificadores retornados pelo gateway. Cada operação deve ser assumida por um processo de cada vez, com recuperação caso ele pare.

Redis pode continuar transportando tarefas, mas o banco deve permitir descobrir o que ainda falta. Incluir confirmação de venda e cobrança de serviço entre os efeitos a recuperar. Se a chamada ao gateway foi enviada e a resposta se perdeu, consultar antes de criar outra cobrança. Não guardar CVV para facilitar a retomada.

**Como conferir:** simular falha na publicação, reinício do processo e resposta perdida após sucesso no gateway. A operação é recuperada sem cobrança, venda ou custo duplicados.

### Registro do dev — C05

- **Situação atual:** atende parcialmente: persistência, lease e recuperação segura estão implementados, mas criação de assinatura e notificação ao Commerce sem resposta ainda aguardam a consulta por correlação para retomada automática; a recarga funcional da tela de pagamento foi validada pelo responsável do produto sem duplicidade e os demais cenários funcionais continuam pendentes.
- **Análise do dev:** a CT API criava `checkout_subscriptions` e as parcelas recorrentes antes de publicar no Redis, sem registrar o trabalho pendente. Uma queda entre esses passos perdia a operação. O worker consome com `BLPOP`, portanto a publicação concluída sem resposta também precisava ser distinguida de uma falha anterior ao envio. A confirmação de pagamento chamava Commerce de forma síncrona antes de persistir uma recuperação, expondo a venda a resposta perdida. Não há CVV no journal novo: ele contém apenas identificadores, estado, prazo de lease e payload mínimo de assinatura/Pix.
- **Resultado técnico do dev:** criada a migration `20261014000000_create_checkout_recovery_operations`; assinatura, parcela e notificação ao Commerce gravam a operação na mesma transação e o recuperador usa lease/idempotência. API, worker e Front foram rebuildados/recriados; migration, `php -l` e `git diff --check` passaram. Em teste controlado, resposta perdida ficou `unknown` sem repetição; no checkout Pix, a criação persistiu uma assinatura, uma parcela e uma operação concluída. Permanecem pendentes os cenários funcionais de falha/reinício.

## C06 — cancelar somente quando houver cancelamento explícito

**O que revisar:** o recebimento do cancelamento ainda não fecha todas as etapas. Além disso, um pagamento que chega depois pode reativar a assinatura, e uma resposta antiga pode sobrescrever o estado mais recente da parcela.

**Como ajustar:** tratar separadamente a situação da assinatura e a situação de cada pagamento. Atraso, falta de pagamento ou expiração de uma parcela não cancelam a assinatura.

Quando houver cancelamento explícito, impedir novas cobranças e cancelar as que ainda estiverem abertas, conforme o que o gateway permite. Conferir também tarefas já na fila. Se um pagamento antigo chegar depois, registrá-lo corretamente, mas manter a assinatura cancelada. Mensagens repetidas ou antigas não podem desfazer um pagamento ou cancelamento já confirmado.

**Como conferir:** cancelar antes e depois do agendamento e receber pagamento atrasado. Não há novos ciclos após o cancelamento; o histórico financeiro permanece correto; inadimplência não causa cancelamento automático.

### Registro do dev — C06

- **Situação atual:** atende após ajuste técnico e confirmação funcional de cancelamento explícito pelo app do pagador; os cenários separados de cancelamento antes e depois da criação de uma parcela futura permanecem para a cobertura completa do roteiro.
- **Análise do dev:** o resultado da consulta Efí tratava `CANCELADA` e `EXPIRADA` como cancelamento da assinatura. Além de cancelar por uma parcela vencida, isso deixava operações que já estavam na fila seguirem seu curso. A confirmação tardia de uma parcela também podia recolocar a assinatura em `active` durante a notificação posterior ao Commerce.
- **Resultado técnico do dev:** criado `CancelCheckoutSubscriptionUseCase`, transacional e idempotente: `CANCELADA` encerra a assinatura, cancela apenas parcelas abertas e fecha operações pendentes; `EXPIRADA` só expira a parcela. Confirmação tardia preserva `canceled`. API rebuildada/recriada; `php -l` e `git diff --check` passaram.
- **Teste técnico e funcional:** fixture confirmou que cancelamento não reativa com pagamento tardio e expiração não cancela. O responsável cancelou uma autorização paga no app do pagador; a Efí retornou `CANCELADA`, o CT preservou a parcela paga e não deixou operação aberta. O reembolso manual posterior retornou `DEVOLVIDO` e não alterou o histórico.

## C07 — consultar os pagamentos por conta, sem deixar registros para trás

**O que revisar:** a consulta atual pode selecionar sempre as mesmas 100 assinaturas. A primeira cobrança Efí também é consultada como se fosse uma cobrança recorrente, embora tenha sido criada em outro tipo de operação.

**Como ajustar:** adotar consultas periódicas por conta/integração, aproveitando o padrão Banking V2. Conferir recebimentos, autorizações/cancelamentos e operações específicas que ficaram pendentes. Cada conta precisa de seu próprio progresso de consulta, para não misturar sellers nem permitir que uma conta bloqueie as demais.

Percorrer todas as páginas de resultados e guardar o que foi encontrado antes de avançar. Reconsultar um pequeno intervalo já visto ajuda a encontrar eventos que chegaram depois; as repetições não podem gerar efeitos duplicados. Pagamento de parcela antiga deve confirmar aquela parcela, não a mais recente.

Na Efí, a consulta específica da primeira cobrança usa `/v2/cob/{txid}`; as recorrentes usam `/v2/cobr/{txid}`. Continuar acompanhando operações antigas mesmo após trocar o gateway usado em novas vendas. O [mapa Banking V2](2026-10-13_CHECKOUT_TRANSPARENT_POLLING_BANKING_V2_MAP.md) contém os detalhes para implementar.

**Como conferir:** usar mais de 100 resultados por minuto, 250 ou mais registros e contas diferentes. Todas avançam, pagamentos antigos são encontrados e cada pagamento é aplicado uma vez. Conferir também cancelamento de uma autorização criada há meses.

- **Resultado técnico do dev (2026-10-14):** o polling deixou de aplicar um `LIMIT 100` global. Ele percorre cada `integration_id` Efí de forma independente, com cursores duráveis separados para recorrências e parcelas em `checkout_subscription_polling_states`; uma conta com lote grande ou falha não bloqueia as demais. Antes de avançar qualquer cursor, cada consulta específica é persistida em `checkout_recovery_operations`; o recuperador publica e republica somente leituras seguras até o resultado ser aplicado. A primeira cobrança agora gera instrução `initial_charge`, consultada pelo worker em `/v2/cob/{txid}`; parcelas recorrentes continuam em `/v2/cobr/{txid}`. A consulta real da cobrança inicial `60136d389971486eacec9f2a8fb66dd8` retornou `CONCLUIDA`, com o mesmo `endToEndId` e horário de liquidação da Efí. Em transação revertida, 251 assinaturas e 251 parcelas da mesma conta foram lidas em páginas locais `100 + 100 + 51` para as duas trilhas; não restou fixture. Após rebuild/recreate de API e worker, a rodada real persistiu e completou oito verificações de status sem erro.

## C08 — cobrar o serviço no momento certo e não confundir autorização com pagamento

**O que revisar:** não foi encontrado o caminho de cobrança do serviço da Lowify para cada pagamento recorrente Pix. A tela também pode mostrar pagamento confirmado apenas porque o cliente autorizou a assinatura.

**Como ajustar:** cartão gera a cobrança de serviço uma vez, na primeira parcela/confirmação elegível. Pix assinatura gera essa cobrança quando cada recorrência é paga, sem repetição por consulta ou notificação duplicada. Reaproveitar as regras de taxas existentes e guardar qual parcela originou cada custo.

Mostrar separadamente “assinatura autorizada” e “pagamento recebido”. Autorizar a assinatura permite seguir o fluxo previsto de agendamento, mas não significa que o dinheiro foi recebido. Conferir também como o pagamento inicial Pix entra na regra de cobrança do serviço.

**Como conferir:** uma compra de cartão em 12 parcelas gera um único custo conforme a regra combinada; cada recorrência Pix paga gera seu custo uma vez. Autorização ou agendamento não aparece como pagamento confirmado nem gera cobrança de serviço por si só.

### Registro do dev — C08

- **Situação atual:** concluído. A prova técnica do cartão RisePay usa o mock interno previsto para este ambiente, pois a conta de teste não permite pagamentos de cartão; Pix pago, idempotência e a conferência visual do checkout foram realizados.
- **Análise do dev:** o cartão já cria o snapshot de taxas em `CreateChargeUseCase` e só publica itens de billing na primeira confirmação `paid`, portanto as parcelas do cartão não repetem esse custo. Já o Pix Automático confirmava a parcela e notificava o Commerce, mas não tinha snapshot nem publicação de billing vinculados à `checkout_subscription_charge`. Além disso, a tela tratava a autorização Efí `active` como pagamento confirmado.
- **Resultado técnico do dev (2026-10-15):** criada a migration `20261015000000_create_checkout_subscription_charge_fees`; Pix publica `billing.items.create` somente após `paid`, com unicidade por `subscription_charge`. O checkout mantém `active` como autorização, não pagamento. API e Front foram rebuildados/recriados; migration, `php -l` e `git diff --check` passaram.
- **Teste técnico e visual (2026-10-15):** o mock RisePay aprovou R$ 54,00 em 12x e a charge `186` chegou a `paid`, com exatamente um item `charge/186/fixed` de R$ 0,99; as consultas repetidas do verificador não criaram outro item. Recusa, pendência e erro temporário também permaneceram nos estados esperados. A autorização Pix não criou billing; a parcela Pix paga `269` criou exatamente um item `subscription_charge/269/fixed` de R$ 0,99. Dois reenvios do mesmo resultado `CONCLUIDA` preservaram a contagem em um. A assinatura e o pagamento de R$ 5,00 foram depois cancelados/devolvidos integralmente para limpeza. No checkout normal, o responsável confirmou o produto de R$ 54,00, cartão RisePay e `12x de R$ 4,50 sem juros`. O mock foi removido da configuração da API antes da entrega; a API voltou ao endpoint RisePay normal.

## C09 — tratar corretamente vencimentos nos dias 30 e 31

**O que revisar:** o primeiro vencimento e os seguintes usam cálculos diferentes. Somar um mês ao dia 31 pode levar diretamente a março, pulando fevereiro.

**Como ajustar:** usar a mesma regra em todos os ciclos e guardar o dia originalmente escolhido. A proposta é usar o último dia disponível nos meses menores e voltar ao dia original depois: `31/jan → 28/fev → 31/mar`. Confirmar essa política antes de aplicá-la e considerar ano bissexto, fuso e ajustes de dia útil do gateway.

Uma resposta repetida não deve avançar o calendário duas vezes nem alterar uma parcela já paga.

**Como conferir:** testar dias 28 a 31, fevereiro, anos bissextos e frequências mensal/semestral/anual. Não pode pular mês, mudar o dia original indevidamente ou criar duas parcelas do mesmo ciclo.

### Registro do dev — C09

- **Situação atual:** concluído tecnicamente.
- **Análise do dev:** a criação Efí já limitava a primeira data ao último dia do mês, mas a API calculava as próximas datas com `modify('+1 month')` a partir da parcela anterior. Isso fazia `31/jan → 28/fev → 28/mar`, em vez de recuperar o dia 31.
- **Resultado técnico do dev (2026-10-15):** adicionada a migration `20261016000000_add_checkout_subscription_billing_day`, que guarda e retropreenche o dia-base de cada assinatura. A API usa esse dia em todos os ciclos posteriores; o worker Efí mantém a mesma regra para a primeira data. API rebuildada/recriada e migration aplicada; as 25 assinaturas existentes ficaram com `billing_day` preenchido.
- **Teste técnico:** uma assinatura de fixture criada no banco (`281`, dia-base 31) percorreu a fila real `gateway:results`: o resultado da parcela `270` em `31/jan/2027` deixou a parcela `pending` e gravou `28/fev/2027`; o resultado da parcela `272` em `28/fev/2027` gravou `31/mar/2027`. O mesmo resultado foi reenviado e permaneceu uma única parcela em 28/fev, sem novo avanço. Também foram validados `31/jan → 29/fev` em ano bissexto, semestral `31/ago → 29/fev`, anual `29/fev → 28/fev` e semanal. `php -l`, `git diff --check` e inicialização dos processos passaram. A fixture ficou em `processing`, sem operação de recuperação, portanto não disparou cobrança externa.

## C10 — ativar só depois da aprovação e manter um gateway por método

**O que revisar:** o método pode ser habilitado antes de terminar sua validação. Escolher um gateway como padrão também não garante que cartão esteja desativado nos outros.

**Como ajustar:** só liberar o método quando sua integração e verificações necessárias estiverem aprovadas. Enquanto não estiver, mostrar um modal explicando que a integração ainda não foi aprovada; o servidor também deve impedir a ativação.

Para cada seller, cartão só pode estar ativo em um gateway. Ao trocar, desativar cartão no anterior e ativar no novo como uma única mudança, inclusive quando duas pessoas fizerem isso ao mesmo tempo. Pix pode usar outro gateway, mas também só um para esse método. Não transferir automaticamente assinaturas antigas; continuar acompanhando-as na conta original.

**Como conferir:** tentar ativar integração pendente e fazer duas ativações simultâneas. Nunca ficam dois gateways com cartão ativo. Pix e cartão em gateways diferentes continuam permitidos.

### Registro do dev — C10

- **Situação atual:** concluído tecnicamente e validado contra a API, banco e Dashboard no ambiente de teste.
- **Análise do dev:** a atualização de método conferia credenciais e o padrão, mas não exigia que a integração estivesse `active` e não desativava o mesmo método nas demais integrações do seller. Assim, duas requisições concorrentes podiam terminar com mais de um gateway habilitado.
- **Resultado técnico do dev (2026-10-15):** a API agora bloqueia a ativação de integração que não esteja `active` dentro da mesma transação que grava o método. Para ativar um método, bloqueia em ordem determinística todas as integrações do seller e os métodos correspondentes; desabilita os demais e ativa o escolhido na mesma transação. A regra é comum a `pix`, `card_credit` e aos demais métodos, sem mover assinatura nem cobrança entre integrações. O Dashboard abre o modal “Integração em validação” ao tentar configurar métodos de integração não aprovada, sem abrir o modal de métodos.
- **Teste técnico:** a fixture pendente `66` recebeu tentativa real de ativação de Pix e retornou `422` (“Approve the integration before enabling this payment method”), sem criar método; ao fim foi marcada `removed`. Em duas chamadas simultâneas reais para Pix (integrações `44` e `58`), ambas responderam `200`, porém a consulta final retornou apenas a `58` habilitada. O mesmo teste simultâneo para cartão (`card_credit`, integrações `40` e `44`) respondeu `200` nas duas chamadas e manteve somente a `40` habilitada; o estado anterior foi restaurado na integração `58`. Também foi habilitado Pix na Mercado Pago `40` enquanto o cartão permaneceu na RisePay `58`, comprovando que os métodos podem ficar em gateways diferentes; Pix foi restaurado na `58`. A validação visual com Playwright criou a fixture `67`, clicou em “Métodos de pagamento” e confirmou o modal de aprovação, com o modal de métodos fechado; a fixture foi removida pelo endpoint do próprio Dashboard. No encerramento, a consulta do banco retornou exatamente um Pix e um cartão ativos para o seller de teste. `php -l` nos arquivos da API e Dashboard e `git diff --check` passaram.

## C11 — permitir edição da integração e usar as regras de venda do Commerce

**O que revisar:** o dashboard chama uma rota de edição que não foi encontrada no gateway da feature. No cartão transparente, a informação de parcelas é retirada antes de chegar ao Commerce.

**Como ajustar:** completar o encaminhamento da edição com as mesmas verificações de acesso já usadas nas outras rotas. Enviar ao Commerce as informações comerciais necessárias, inclusive parcelas, sem dados sensíveis do cartão.

O Commerce V2 deve aplicar as mesmas regras de produto, preço e parcelamento já usadas nas vendas. O CT continua verificando exigências próprias do gateway, sem criar uma regra comercial diferente.

**Como conferir:** editar integração pelo dashboard e testar parcelas acima do limite ou valor alterado na requisição. O servidor rejeita escolhas inválidas, preserva o acesso de cada seller e mantém o checkout normal funcionando.

### Registro do dev — C11

- **Situação atual:** concluído tecnicamente e com o checkout manual confirmado em ambiente de teste.
- **Análise do dev:** na versão atual, a rota `PATCH /integrations/{id}` já está presente no Gateway, na Public API e na CT API, com `user_id` derivado do JWT antes da CT consultar a integração por seller. A falha efetiva era o caminho de checkout transparente: a Public API removia `installments` junto com os dados sensíveis do cartão antes de chamar o Commerce. O Commerce recebia a ausência como `1x`, sem conseguir aplicar a regra comercial da parcela escolhida.
- **Resultado técnico do dev (2026-10-15):** a Public API preserva somente `installments` para o Commerce e continua removendo número, validade, CVV, token, envelope, nonce e demais dados sensíveis. O Commerce V2 usa o produto/oferta para resolver preço e métodos, e agora exige que a parcela de cartão seja um inteiro entre `1` e o limite comercial do produto antes de criar a venda. O CT continua recebendo a mesma escolha apenas para as restrições técnicas do gateway.
- **Teste técnico e manual (2026-10-15):** a edição real pelo Dashboard criou a fixture `68`, alterou o nome por Dashboard → Gateway → Public API → CT e o banco confirmou `user_id=900011` e o novo nome; a fixture foi marcada `removed`. Com o produto real `9900071` (R$ 54,00 e máximo 12x), a rota pública transparente rejeitou `13x` com `422 checkout_card_installments_unavailable` antes de tentativa de cartão; `0x` também retornou `422`. Uma chamada direta ao Commerce aceitou `12x`, criando a venda-fixture `9901326`. Outra chamada enviou `amount=0.01` com `12x` e o Commerce criou a venda-fixture `9901327` com valor bruto e item de R$ 54,00, comprovando que o preço vem do produto, não da requisição. Na conferência manual, o pedido `ord_6c45060d437872be` criou a venda `9901331`, pagou R$ 54,00 em `1x`, ficou `paid` e recebeu redirecionamento ao conteúdo; a área de membros respondeu `200`. Public API e Commerce foram reiniciados com o código testado; `php -l` e `git diff --check` passaram.

## C12 — disponibilizar RisePay e proteger informações nos erros

**O que revisar:** cartão RisePay já tem código, mas está desabilitado. Alguns caminhos de erro também podem guardar ou mostrar textos técnicos contendo informações que deveriam ser protegidas.

**Como ajustar:** concluir proteção dos dados, controle de repetição e recuperação antes de habilitar RisePay. Conferir criação, consulta, aprovação, recusa e resposta perdida; não considerar concluído apenas por ligar a configuração.

Nos erros, guardar apenas informações necessárias ao diagnóstico, retirando dados de cartão, credenciais e dados pessoais desnecessários antes de registrar ou mostrar. O relatório do seller também deve ser seguro e restrito às próprias integrações.

**Como conferir:** homologar os resultados RisePay, inclusive resposta desconhecida, sem cobrar novamente. Usar dados fictícios para verificar que informações protegidas não aparecem em registros, respostas ou painel.

### Registro do dev — C12

- **Situação atual:** concluído tecnicamente em ambiente de teste; a homologação com uma cobrança real RisePay permanece indisponível porque a conta de teste não permite pagamentos por cartão.
- **Análise do dev:** a tentativa da venda `ord_9532e0b04943ce5c` alcançou a RisePay e recebeu `400` classificado como cartão, sem identificador de transação ou cobrança. O adaptador passou a enviar `expirationDate` em `MM/AAAA`, além de mês e ano. A disponibilidade só é publicada quando a configuração de proteção JWE e o método RisePay estão disponíveis; no ambiente de teste ela foi habilitada exclusivamente contra o mock interno.
- **Resultado técnico do dev (2026-10-16):** Front Checkout, Public API, Commerce, CT API e worker foram conferidos/reconstruídos a partir das branches da entrega antes da homologação. O checkout transparente exibiu Cartão RisePay, criptografou os dados no navegador e aprovou a compra `ord_cc5d4e4c7eaba896` em `12x`: a charge `195` ficou `paid`, a tentativa `188` ficou `success` e o navegador chegou à área de membros. O mock também confirmou recusa conhecida (`charge 196`, `failed`), resposta desconhecida (`charge 197`, tentativa pendente sem nova cobrança) e pendência seguida de webhook/consulta (`charge 198`, `paid`, origem `webhook`). A resposta persistida da tentativa aprovada contém apenas identificadores, valor, status e data; buscas pelos dados fictícios usados no teste não encontraram cartão, CVV, CPF, nome ou e-mail nos logs da API nem em `integration_errors`. `php -l` dos caminhos RisePay/processador de resultados e `git diff --check` passaram. O mock não persiste cartão; ele deve continuar restrito ao ambiente de teste e a configuração de produção deve usar o endpoint RisePay real.

## C13 — mostrar cartão também em Editar Produto

**O que revisar:** a edição usa suas próprias condições para mostrar cartão. O dev precisa conferir se elas reconhecem cartão aprovado no CT, mesmo sem integração de cartão no checkout normal.

**Como ajustar:** usar uma disponibilidade consistente entre checkout e Editar Produto. Se o seller tem cartão disponível e o produto permite esse pagamento, mostrar a opção de habilitar/desabilitar e configurar parcelas. Isso não significa ativar cartão automaticamente em todos os produtos.

Preservar as escolhas salvas e as regras do Commerce. Se a integração ficar temporariamente indisponível, explicar isso sem apagar a preferência de cartão ao salvar outra informação.

**Como conferir:** editar, salvar e reabrir o produto; o checkout deve refletir a escolha e as parcelas. Testar seller com apenas cartão CT, falha temporária de consulta e produtos que não permitem cartão.

### Registro do dev — C13

- **Situação atual:** concluído tecnicamente; a conferência visual autenticada do Dashboard permanece para o responsável do produto.
- **Análise do dev:** a tela de produto consulta o Commerce para separar duas informações: a disponibilidade de cartão do seller e a preferência salva no produto. O cartão não é ativado por essa consulta. Foi encontrado um teto interno antigo de 10 parcelas, apesar de o Commerce estar configurado para 12, e também o risco de uma falha temporária de consulta substituir a preferência salva por `0` ao salvar outra alteração.
- **Resultado técnico do dev (2026-10-16):** a regra comercial da faixa de preço alta agora respeita `COMMERCE_PRODUCT_CARD_MAX_INSTALLMENTS` (12 no ambiente), em vez de limitar silenciosamente a 10. O formulário preserva `credit_card_enabled` já salvo quando a integração estiver indisponível; nesse caso o controle fica bloqueado e a mensagem de configuração continua visível, mas um salvamento não desabilita o cartão. A fixture inativa `9900084` (seller `900011`, R$100,00) retornou cartão disponível, `12x` e regras até `12x`; foi atualizada pela API mantendo cartão e `12x`. A fixture `9900085`, do mesmo seller com integração disponível, permaneceu com cartão desativado, comprovando que a disponibilidade não ativa produtos automaticamente. A API rejeitou `13x` com `422 product_card_installments_invalid`. `php -l`, `git diff --check` e a resposta da rota `GET /products/{id}/form-data` no container reconstruído passaram. A validação visual precisa ser feita no Dashboard local/autenticado, pois o domínio público resolve por Cloudflare e não é uma sessão confiável deste ambiente.

## C14 — mostrar erros de cartão de forma simples e consistente

**O que revisar:** tokenização, criação, consulta e processamento posterior tratam erros de maneiras diferentes. Uma mensagem genérica apenas na tela final não cobre os erros das etapas anteriores.

**Como ajustar:** montar uma lista dos erros de Mercado Pago, Pagar.me, Efí e RisePay e definir a mensagem segura de cada grupo. Incluir geração do token, autenticação do cartão (3DS), dados inválidos, recusa, integração indisponível, falha interna, consulta e resposta desconhecida. Incluir fluxos antigos se compartilharem os componentes alterados.

Usar como referência o `CieloEcommerceCheckoutErrorMapper` do Banking V2: ele transforma os códigos do gateway em mensagens próprias do checkout. Esse padrão está no fluxo Cielo; os códigos precisam ser conferidos separadamente nos outros gateways. Não copiar o tratamento geral de exceções que ainda retorna a mensagem técnica.

| Situação | Exemplo de retorno ao comprador |
| --- | --- |
| Dados inválidos ou cartão vencido | “Confira os dados do cartão e tente novamente”, ou orientação específica aprovada. |
| Pagamento recusado | “Pagamento não autorizado. Utilize outro cartão ou meio de pagamento.” |
| Autenticação do cartão não concluída | “Não foi possível concluir a autenticação do cartão.” |
| Integração ou serviço indisponível | “Pagamento por cartão indisponível no momento. Utilize outro meio de pagamento.” |
| Chamada enviada, mas resultado ainda desconhecido | “Estamos verificando seu pagamento. Aguarde a confirmação.” Não incentivar outra cobrança. |
| Consulta temporariamente indisponível | Explicar que a consulta falhou, sem declarar que o pagamento foi recusado. |
| Erro ainda não catalogado | Mensagem genérica segura, nunca a resposta técnica recebida do gateway. |

Padronizar as mensagens no servidor e tratar também erros que acontecem no navegador antes do envio. A consulta posterior deve mostrar a mesma situação da tentativa. Manter o diagnóstico técnico separado, com dados protegidos, sem copiá-lo para o comprador ou relatório do seller.

**Como conferir:** o dev entrega a lista de erros mapeados e testes dos grupos conhecidos e desconhecidos. Nenhuma etapa mostra dados sensíveis ou respostas brutas. Uma consulta falha não transforma pagamento aprovado em recusa; resposta desconhecida continua em acompanhamento.

### Registro do dev — C14

- **Situação atual:** atende tecnicamente no ambiente de teste; a conferência visual final pelo responsável do produto permanece pendente. Mercado Pago e Pagar.me foram acionados com suas integrações reais; a Efí foi exercitada até a validação real de tokenização, que bloqueou por conta de cartão inválida na configuração existente.
- **Análise do dev:** a criação RisePay mantinha o diagnóstico operacional protegido na tentativa, mas a consulta pública devolvia apenas o status. Assim, uma recusa conhecida e uma resposta incerta acabavam visualmente iguais. A tokenização no navegador também tinha textos inconsistentes para indisponibilidade, bandeira e autenticação. Durante a retestagem foi encontrada uma configuração de ambiente incorreta: a API CT havia sido recriada sem o compose complementar do mock e, portanto, usava o endpoint padrão de RisePay. A composição foi corrigida antes dos testes finais com `docker-compose.risepay-card-mock.yml`.
- **Resultado técnico e testes (2026-10-16):** criado o contrato público seguro de cartão (`code`, `alert_title`, `alert_message`) e mantido o retorno bruto exclusivamente no registro operacional. O mapeador cobre dados inválidos, recusa, 3DS, indisponibilidade, transporte/resultado desconhecido e erro não catalogado; o front também normaliza tokenização, 3DS, bandeira, indisponibilidade e erro de criação. A consulta que falhar repetidamente passou a informar que a consulta não foi possível e orienta a não pagar novamente. No navegador, com campos nativos preenchidos e JWE gerado, foram realizados contra o mock Docker: (1) recusa `4000000000009995`, pedido `ord_1f9eee8e191b447a`, que retornou `card_payment_rejected`; (2) resultado incerto `4000000000000101`, pedido `ord_879dcf8b48a19546`, que ficou `processing` com `card_payment_verifying`; e (3) aprovação `4111111111111111`, pedido `ord_b688d90db06a8682`, que terminou `paid`. Mercado Pago foi tokenizado no navegador e chamado de verdade: a recusa por risco retornou HTTP 402 e passou a ser publicada como `card_payment_rejected`, sem resposta bruta. Pagar.me também foi tokenizado e chamado de verdade; a recusa retornada pelo gateway foi publicada com a mesma mensagem segura. A tentativa Efí chegou ao SDK real, que recusou a conta de cartão configurada antes de criar token; o front agora a classifica como indisponibilidade, sem expor o texto do provedor. Foi encontrada e corrigida a possibilidade de um token dentro de uma mensagem JSON técnica ser persistido no diagnóstico operacional; a mensagem é sanitizada antes de salvar. As configurações temporárias de método usadas nos testes foram restauradas. `php -l` de todos os PHP alterados e `git diff --check` passaram. A autenticação 3DS real continua dependente de uma conta/cenário que a solicite.

## Referências rápidas para o dev

Os caminhos e exemplos completos estão no [detalhamento da revisão](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW_DETAILS.md). Para localizar os principais ajustes:

- **C02/C03:** formulário e envio no front; `ProductController::createTransparentCardAttempt` na public-api; tentativas e proteção do cartão no CT-API.
- **C04:** `ApplyMercadoPagoOAuthTokenRefreshResultUseCase::persistTokens`, criação de integração/métodos e `GetGatewayContextUseCase` no CT-API.
- **C05–C09:** criação/confirmação de assinatura, processos de resultado/agendamento/consulta no CT-API; `EfiBankSubscriptionClient` no worker; resolvedor Efí no ct-webhook.
- **C10/C11:** métodos e disponibilidade no CT; rotas do gateway/public-api; regras de produto e checkout no Commerce.
- **C12/C14:** criação RisePay no CT-API, clientes dos gateways no worker, respostas HTTP e mensagens do front. Referência Banking: mapper e exceção Cielo de checkout e `ChargeCardController`.
- **C13:** `product_form.php`, `product_edit.php` e `views/dashboard/products/form/_components/checkout.php` no dashboard.

## Ordem sugerida e retorno esperado

1. O dev preenche a análise das regras e confere os itens na branch que será entregue.
2. Ajusta os dados enviados, o controle de repetição, as credenciais e a recuperação de operações.
3. Fecha consultas por conta, cancelamento, calendário e cobrança de serviço.
4. Confere ativação, edição de integração/produto, mensagens de erro e RisePay.
5. O dev entrega as mudanças com as verificações técnicas e condições de teste documentadas. O responsável pelo produto executa os cenários funcionais do [roteiro de testes](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW.md), incluindo checkout normal e repetição de ações; o dev prepara as simulações técnicas de falha quando necessárias.

O dev entrega as regras e os itens com análise técnica preenchida, evidências e alterações realizadas. Justificar quando não for necessária correção e registrar o que ainda depender de decisão ou teste. A conclusão funcional é preenchida pelo responsável pelo produto após executar o roteiro; até lá, permanece pendente.

Se precisar mudar o banco, criar uma alteração nova, sem reescrever migrations já commitadas. Conferir dados antigos, execução repetida e tempo de consulta com volume maior. Preservar alterações locais e correções recentes da `main`; não apagar filas ou operações para fazer testes passarem.

Atualizar o plano de entrega com todos os componentes e configurações necessários. A revisão inicial validou leitura de código e sintaxe PHP, não pagamentos reais, banco ou carga. A liberação depende da comprovação dos ajustes e dos testes em homologação.
