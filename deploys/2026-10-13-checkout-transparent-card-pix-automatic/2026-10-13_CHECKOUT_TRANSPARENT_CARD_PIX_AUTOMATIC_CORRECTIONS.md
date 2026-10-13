# Checkout Transparente — revisão e ajustes para o dev

Data: 2026-10-13.

Objetivo: conferir o que já funciona e ajustar os pontos necessários para que cartão e Pix Automático operem conforme as regras combinadas. Este documento reúne o comportamento esperado, o problema observado e uma sugestão de correção.

A revisão inicial foi feita nas branches `feat/checkout-transparent-card`, nas versões registradas no [roteiro de revisão](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW.md). Ela não substitui a conferência do dev na versão que será entregue. Nenhuma correção nos serviços foi implementada por este documento.

## Como usar este documento

Antes de alterar cada item, o dev deve conferir o código atual e testar o comportamento. Se já estiver correto, registrar a evidência e não refazer a implementação. Se estiver diferente, explicar brevemente a diferença e aplicar o ajuste.

Para cada regra e item C01–C14, registrar:

- **Situação atual:** já atende, atende em parte, precisa de ajuste ou ainda não foi possível verificar.
- **Análise do dev:** como funciona hoje, com referência ao código e ao teste realizado.
- **Resultado:** o que foi alterado, os commits e o teste que comprova a correção; ou por que não foi necessário alterar.

As situações abaixo começam pendentes dessa análise. “Regra confirmada” significa que o comportamento foi combinado com o produto, não que já esteja implementado.

## Regras combinadas — conferir uma a uma

| Comportamento esperado | O que a revisão inicial indica | Item | Análise do dev |
| --- | --- | --- | --- |
| Enviar somente token ou dados criptografados quando o cartão em aberto não for necessário. Não guardar CVV. | Alguns fluxos ainda enviam campos do cartão junto do token. Não foi encontrada gravação explícita de CVV no caminho CT; registros do ambiente ainda precisam ser conferidos. | C02 | Pendente |
| Uma repetição da mesma tentativa não pode cobrar novamente. Usar um nonce: identificador aleatório mantido ao reenviar. | A identificação atual muda se o token ou os dados criptografados mudarem. | C03 | Pendente |
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

## C02 — não enviar dados de cartão sem necessidade

**O que revisar:** em alguns fluxos o navegador gera o token, mas ainda envia número, validade e CVV junto dele. Remover esses dados só antes do Commerce não evita que eles passem pelos componentes anteriores.

**Como ajustar:** depois de gerar o token, enviar apenas ele e os dados necessários à compra. Para RisePay, enviar o pacote criptografado, sem uma cópia do cartão em aberto. Manter uma exceção somente quando o fluxo realmente exigir, como algum caminho específico de autenticação do cartão; a exceção precisa ser validada no servidor, não apenas escolhida pelo navegador.

Não foi encontrada gravação explícita de CVV ou do pacote criptografado no caminho CT examinado. O dev também deve conferir se registros de erro ou ferramentas de monitoramento capturam esses dados.

**Como conferir:** revisar os dados enviados em cada fluxo de cartão e os registros gerados. Não pode haver CVV guardado, inclusive dentro de um pacote criptografado mantido como histórico. Os fluxos antigos que precisam de tratamento específico devem continuar funcionando.

## C03 — reconhecer a mesma tentativa quando houver reenvio

**O que revisar:** hoje a identificação da tentativa depende do token ou do pacote criptografado. Se eles mudarem durante um reenvio, a mesma intenção de compra pode parecer uma tentativa nova.

**Como ajustar:** gerar uma identificação aleatória, chamada nonce, uma vez por tentativa e mantê-la no duplo clique e nas repetições da requisição. Usá-la junto dos identificadores existentes de seller, cobrança e método. Quando houver pacote criptografado, incluir o nonce nele e conferir se corresponde ao enviado pela requisição.

Redis pode ajudar a impedir duas execuções ao mesmo tempo. O banco também deve guardar a identificação da tentativa, para que perder ou expirar esse controle no Redis não permita cobrar outra vez. Se o pagamento foi recusado de forma conhecida, uma nova tentativa pode receber outro nonce. Se a resposta ficou desconhecida, consultar o resultado antes de permitir outra cobrança.

**Como conferir:** duplo clique, dois envios simultâneos, nova criptografia com o mesmo nonce e reinício do Redis não duplicam a cobrança. Mudanças no valor ou nas parcelas não são aceitas silenciosamente como a mesma tentativa. Não exigir novos campos de tempo neste ajuste.

## C04 — usar a credencial renovada do Mercado Pago em todos os métodos

**O que revisar:** ao configurar Pix/cartão, o sistema guarda cópias da credencial de acesso. A renovação atualiza a integração, mas a cobrança pode continuar lendo a cópia antiga do método.

**Como ajustar:** na renovação, atualizar também as credenciais dos métodos que usam a mesma conta Mercado Pago. Fazer essas gravações juntas: ou todas são concluídas, ou nenhuma é aplicada. Atualizar a informação de validade e incluir métodos desabilitados, sem ativá-los automaticamente.

Para este pacote, essa alteração pode preservar a estrutura atual. Não é necessário redesenhar todo o armazenamento. Usar o mesmo cuidado na reconexão da conta, não alterar credenciais de outra conta e aceitar uma resposta de renovação repetida sem erro.

**Como conferir:** renovar uma credencial de teste e verificar que Pix e cartão usam a nova versão. Um método desabilitado também usa a versão nova quando voltar a ser habilitado. Nenhuma credencial aparece nos registros de erro.

## C05 — retomar operações que ficaram pela metade

**O que revisar:** uma assinatura pode ser salva, mas sua tarefa não ser enviada. Um processo também pode parar depois de retirar uma tarefa da fila. Na Efí, a criação possui várias etapas; repetir tudo pode criar recursos novamente.

**Como ajustar:** criar um processo de recuperação que leia as operações incompletas no banco, saiba qual etapa já terminou e retome a partir dela. Guardar o progresso e os identificadores retornados pelo gateway. Cada operação deve ser assumida por um processo de cada vez, com recuperação caso ele pare.

Redis pode continuar transportando tarefas, mas o banco deve permitir descobrir o que ainda falta. Incluir confirmação de venda e cobrança de serviço entre os efeitos a recuperar. Se a chamada ao gateway foi enviada e a resposta se perdeu, consultar antes de criar outra cobrança. Não guardar CVV para facilitar a retomada.

**Como conferir:** simular falha na publicação, reinício do processo e resposta perdida após sucesso no gateway. A operação é recuperada sem cobrança, venda ou custo duplicados.

## C06 — cancelar somente quando houver cancelamento explícito

**O que revisar:** o recebimento do cancelamento ainda não fecha todas as etapas. Além disso, um pagamento que chega depois pode reativar a assinatura, e uma resposta antiga pode sobrescrever o estado mais recente da parcela.

**Como ajustar:** tratar separadamente a situação da assinatura e a situação de cada pagamento. Atraso, falta de pagamento ou expiração de uma parcela não cancelam a assinatura.

Quando houver cancelamento explícito, impedir novas cobranças e cancelar as que ainda estiverem abertas, conforme o que o gateway permite. Conferir também tarefas já na fila. Se um pagamento antigo chegar depois, registrá-lo corretamente, mas manter a assinatura cancelada. Mensagens repetidas ou antigas não podem desfazer um pagamento ou cancelamento já confirmado.

**Como conferir:** cancelar antes e depois do agendamento e receber pagamento atrasado. Não há novos ciclos após o cancelamento; o histórico financeiro permanece correto; inadimplência não causa cancelamento automático.

## C07 — consultar os pagamentos por conta, sem deixar registros para trás

**O que revisar:** a consulta atual pode selecionar sempre as mesmas 100 assinaturas. A primeira cobrança Efí também é consultada como se fosse uma cobrança recorrente, embora tenha sido criada em outro tipo de operação.

**Como ajustar:** adotar consultas periódicas por conta/integração, aproveitando o padrão Banking V2. Conferir recebimentos, autorizações/cancelamentos e operações específicas que ficaram pendentes. Cada conta precisa de seu próprio progresso de consulta, para não misturar sellers nem permitir que uma conta bloqueie as demais.

Percorrer todas as páginas de resultados e guardar o que foi encontrado antes de avançar. Reconsultar um pequeno intervalo já visto ajuda a encontrar eventos que chegaram depois; as repetições não podem gerar efeitos duplicados. Pagamento de parcela antiga deve confirmar aquela parcela, não a mais recente.

Na Efí, a consulta específica da primeira cobrança usa `/v2/cob/{txid}`; as recorrentes usam `/v2/cobr/{txid}`. Continuar acompanhando operações antigas mesmo após trocar o gateway usado em novas vendas. O [mapa Banking V2](2026-10-13_CHECKOUT_TRANSPARENT_POLLING_BANKING_V2_MAP.md) contém os detalhes para implementar.

**Como conferir:** usar mais de 100 resultados por minuto, 250 ou mais registros e contas diferentes. Todas avançam, pagamentos antigos são encontrados e cada pagamento é aplicado uma vez. Conferir também cancelamento de uma autorização criada há meses.

## C08 — cobrar o serviço no momento certo e não confundir autorização com pagamento

**O que revisar:** não foi encontrado o caminho de cobrança do serviço da Lowify para cada pagamento recorrente Pix. A tela também pode mostrar pagamento confirmado apenas porque o cliente autorizou a assinatura.

**Como ajustar:** cartão gera a cobrança de serviço uma vez, na primeira parcela/confirmação elegível. Pix assinatura gera essa cobrança quando cada recorrência é paga, sem repetição por consulta ou notificação duplicada. Reaproveitar as regras de taxas existentes e guardar qual parcela originou cada custo.

Mostrar separadamente “assinatura autorizada” e “pagamento recebido”. Autorizar a assinatura permite seguir o fluxo previsto de agendamento, mas não significa que o dinheiro foi recebido. Conferir também como o pagamento inicial Pix entra na regra de cobrança do serviço.

**Como conferir:** uma compra de cartão em 12 parcelas gera um único custo conforme a regra combinada; cada recorrência Pix paga gera seu custo uma vez. Autorização ou agendamento não aparece como pagamento confirmado nem gera cobrança de serviço por si só.

## C09 — tratar corretamente vencimentos nos dias 30 e 31

**O que revisar:** o primeiro vencimento e os seguintes usam cálculos diferentes. Somar um mês ao dia 31 pode levar diretamente a março, pulando fevereiro.

**Como ajustar:** usar a mesma regra em todos os ciclos e guardar o dia originalmente escolhido. A proposta é usar o último dia disponível nos meses menores e voltar ao dia original depois: `31/jan → 28/fev → 31/mar`. Confirmar essa política antes de aplicá-la e considerar ano bissexto, fuso e ajustes de dia útil do gateway.

Uma resposta repetida não deve avançar o calendário duas vezes nem alterar uma parcela já paga.

**Como conferir:** testar dias 28 a 31, fevereiro, anos bissextos e frequências mensal/semestral/anual. Não pode pular mês, mudar o dia original indevidamente ou criar duas parcelas do mesmo ciclo.

## C10 — ativar só depois da aprovação e manter um gateway por método

**O que revisar:** o método pode ser habilitado antes de terminar sua validação. Escolher um gateway como padrão também não garante que cartão esteja desativado nos outros.

**Como ajustar:** só liberar o método quando sua integração e verificações necessárias estiverem aprovadas. Enquanto não estiver, mostrar um modal explicando que a integração ainda não foi aprovada; o servidor também deve impedir a ativação.

Para cada seller, cartão só pode estar ativo em um gateway. Ao trocar, desativar cartão no anterior e ativar no novo como uma única mudança, inclusive quando duas pessoas fizerem isso ao mesmo tempo. Pix pode usar outro gateway, mas também só um para esse método. Não transferir automaticamente assinaturas antigas; continuar acompanhando-as na conta original.

**Como conferir:** tentar ativar integração pendente e fazer duas ativações simultâneas. Nunca ficam dois gateways com cartão ativo. Pix e cartão em gateways diferentes continuam permitidos.

## C11 — permitir edição da integração e usar as regras de venda do Commerce

**O que revisar:** o dashboard chama uma rota de edição que não foi encontrada no gateway da feature. No cartão transparente, a informação de parcelas é retirada antes de chegar ao Commerce.

**Como ajustar:** completar o encaminhamento da edição com as mesmas verificações de acesso já usadas nas outras rotas. Enviar ao Commerce as informações comerciais necessárias, inclusive parcelas, sem dados sensíveis do cartão.

O Commerce V2 deve aplicar as mesmas regras de produto, preço e parcelamento já usadas nas vendas. O CT continua verificando exigências próprias do gateway, sem criar uma regra comercial diferente.

**Como conferir:** editar integração pelo dashboard e testar parcelas acima do limite ou valor alterado na requisição. O servidor rejeita escolhas inválidas, preserva o acesso de cada seller e mantém o checkout normal funcionando.

## C12 — disponibilizar RisePay e proteger informações nos erros

**O que revisar:** cartão RisePay já tem código, mas está desabilitado. Alguns caminhos de erro também podem guardar ou mostrar textos técnicos contendo informações que deveriam ser protegidas.

**Como ajustar:** concluir proteção dos dados, controle de repetição e recuperação antes de habilitar RisePay. Conferir criação, consulta, aprovação, recusa e resposta perdida; não considerar concluído apenas por ligar a configuração.

Nos erros, guardar apenas informações necessárias ao diagnóstico, retirando dados de cartão, credenciais e dados pessoais desnecessários antes de registrar ou mostrar. O relatório do seller também deve ser seguro e restrito às próprias integrações.

**Como conferir:** homologar os resultados RisePay, inclusive resposta desconhecida, sem cobrar novamente. Usar dados fictícios para verificar que informações protegidas não aparecem em registros, respostas ou painel.

## C13 — mostrar cartão também em Editar Produto

**O que revisar:** a edição usa suas próprias condições para mostrar cartão. O dev precisa conferir se elas reconhecem cartão aprovado no CT, mesmo sem integração de cartão no checkout normal.

**Como ajustar:** usar uma disponibilidade consistente entre checkout e Editar Produto. Se o seller tem cartão disponível e o produto permite esse pagamento, mostrar a opção de habilitar/desabilitar e configurar parcelas. Isso não significa ativar cartão automaticamente em todos os produtos.

Preservar as escolhas salvas e as regras do Commerce. Se a integração ficar temporariamente indisponível, explicar isso sem apagar a preferência de cartão ao salvar outra informação.

**Como conferir:** editar, salvar e reabrir o produto; o checkout deve refletir a escolha e as parcelas. Testar seller com apenas cartão CT, falha temporária de consulta e produtos que não permitem cartão.

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
5. Executa os grupos do [roteiro de testes](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW.md), incluindo checkout normal, repetições e falhas.

Entregar as regras e os itens com situação preenchida, evidências e alterações realizadas. Justificar quando não for necessária correção e registrar o que ainda depender de decisão ou teste.

Se precisar mudar o banco, criar uma alteração nova, sem reescrever migrations já commitadas. Conferir dados antigos, execução repetida e tempo de consulta com volume maior. Preservar alterações locais e correções recentes da `main`; não apagar filas ou operações para fazer testes passarem.

Atualizar o plano de entrega com todos os componentes e configurações necessários. A revisão inicial validou leitura de código e sintaxe PHP, não pagamentos reais, banco ou carga. A liberação depende da comprovação dos ajustes e dos testes em homologação.
