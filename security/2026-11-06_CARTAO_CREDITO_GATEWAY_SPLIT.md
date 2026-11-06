# Cartão de crédito com Split

| Campo | Definição |
| --- | --- |
| Sistema | Lowify |
| Escopo | Venda avulsa por cartão de crédito com divisão de recebíveis |
| Processadores de cartão | Cielo E-commerce e Pagar.me PSP |
| Versão | 5.0 — 06/11/2026 |

## 1. Escopo e regra central

Este documento descreve o fluxo de cartão de crédito com Split para vendas avulsas da Lowify: criação da venda, autorização, divisão de recebíveis, confirmação e efeitos posteriores.

O processador recebe a instrução de divisão e realiza a liquidação entre os recebedores. Por isso, uma venda aprovada nesse fluxo não gera crédito adicional no extrato interno do vendedor. A venda pode liberar acesso, entrega e notificações, mas a compensação financeira ocorre exclusivamente no Split do processador.

Cobrança recorrente, estorno, disputa e repasse bancário posterior possuem fluxos próprios e não fazem parte deste documento.

## 2. Arquitetura e limites de confiança

| Camada | Entrada | Saída | Responsabilidade no fluxo |
| --- | --- | --- | --- |
| Checkout | Dados do comprador e do pagamento | Solicitação autenticada de compra | Coletar a compra e encaminhá-la à borda da plataforma. |
| Borda de integração | Solicitação do checkout | Solicitação interna assinada | Restringir o acesso à operação de compra e encaminhar a mensagem ao domínio de comércio. |
| Domínio de comércio | Dados de compra, produto e comprador | Instrução financeira com divisão | Validar a venda, selecionar o processador, calcular os valores e definir os destinatários. |
| Domínio financeiro | Instrução financeira | Requisição do processador e eventos de cobrança | Registrar a cobrança, validar a divisão, autorizar o cartão e manter seu estado. |
| Processador de pagamentos | Cobrança e instruções de Split | Status e identificador externo | Autorizar ou recusar a cobrança e executar a divisão de recebíveis. |
| Entrada de callbacks | Evento do processador | Atualização interna de cobrança | Autenticar o emissor do evento e atualizar o estado correspondente. |
| Persistência e eventos | Venda, cobrança e status | Conciliação e efeitos da venda | Manter a correlação entre pedido, venda, cobrança, evento e transação externa. |

O limite entre checkout e plataforma recebe dados de pagamento. A comunicação entre checkout e borda é assinada. Os callbacks dos processadores entram por rotas separadas, cada uma com autenticação própria; eles não compartilham o mesmo mecanismo de entrada do checkout.

## 3. Seleção do processador e habilitação do recebedor

O processador de cartão é selecionado pela configuração operacional do checkout. O canal de cartão reconhece dois valores: Cielo E-commerce e Pagar.me PSP.

Antes de uma cobrança ser criada, o sistema associa a venda ao processador selecionado e verifica se cada recebedor necessário possui conta ativa nesse mesmo processador. Uma conta Cielo não é utilizada para uma venda Pagar.me, e uma conta Pagar.me não é utilizada para uma venda Cielo.

A escolha do processador afeta apenas o adaptador financeiro e o contrato enviado ao provedor. Produto, pedido, comprador, regra de comissão e regra de entrega continuam sendo definidos pela venda.

## 4. Dados da solicitação de pagamento

Uma solicitação de cartão contém:

- identificadores de produto, pedido e vendedor;
- identificação e contato do comprador;
- valor total em centavos e quantidade de parcelas;
- lista de destinatários do Split;
- token de pagamento ou, quando não houver token, número do cartão, validade, código de segurança, titular e bandeira;
- endereço de cobrança e dados adicionais exigidos pelo processador;
- dados de autenticação 3DS quando a regra aplicável os exigir.

Quando há token de pagamento, ele substitui os dados brutos do cartão na instrução financeira. Quando não há token, os dados do cartão percorrem checkout, borda, domínio de comércio e domínio financeiro até a autorização. Esse percurso define o perímetro de dados de cartão da plataforma.

O registro de cobrança guarda referências de conciliação, estado, valor, parcelas, conta recebedora e, quando aplicável, o token de pagamento. Número do cartão, validade e código de segurança não compõem esse registro persistido. O código de segurança é utilizado somente para a autorização.

## 5. Formação da venda e do Split

Após validar produto, comprador e meio de pagamento, o domínio de comércio cria a venda e calcula a instrução financeira. Cada destinatário é representado por papel, conta recebedora e valor em centavos.

| Situação comercial | Destinatários |
| --- | --- |
| Venda sem afiliado elegível | Produtor. |
| Venda com afiliado elegível | Produtor e afiliado. |
| Cobrança com tarifa de plataforma | Composição aplicada conforme o contrato do processador. |

As regras de integridade são as seguintes:

- cada destinatário possui papel reconhecido e valor positivo;
- todos os destinatários possuem conta ativa no processador da venda;
- a composição reconciliada pelo adaptador corresponde ao valor total da cobrança;
- divergência de valor, papel ou conta bloqueia a criação da cobrança;
- pedido e identificador de idempotência impedem a criação de uma segunda cobrança para a mesma operação.

## 6. Contrato de cada processador

| Aspecto | Cielo E-commerce | Pagar.me PSP |
| --- | --- | --- |
| Tipo de operação | Venda de cartão com Split | Pedido com pagamento por cartão e Split |
| Recebedor | Conta subordinada habilitada na Cielo | Recipient habilitado na Pagar.me |
| Papéis aceitos | Produtor e afiliado | Produtor, afiliado e plataforma, quando há tarifa aplicável |
| Identificador externo | Identificador de pagamento retornado pela Cielo | Identificador de cobrança retornado pela Pagar.me |
| Repetição de cobrança | Referência do pedido e controle interno | Chave de idempotência derivada do pedido e controle interno |
| Atualização assíncrona | Callback autenticado por segredo exclusivo | Callback autenticado por credencial exclusiva |

Na Cielo, a cobrança é enviada como pagamento de cartão com Split e cada recebedor é identificado pela conta subordinada correspondente. Na Pagar.me, a cobrança é enviada como pedido com pagamento de cartão e lista de recipients; a plataforma pode constar nessa lista quando a tarifa for representada como destinatário.

Os adaptadores não compartilham campos de recebedor. Cada um traduz a mesma venda para o formato aceito pelo processador selecionado.

## 7. Ciclo de vida da cobrança e da venda

| Estado | Significado | Efeito na venda |
| --- | --- | --- |
| Criada | A cobrança foi registrada antes ou durante a submissão ao processador. | A venda ainda não é paga. |
| Pendente ou requer ação | A decisão depende de retorno posterior ou de autenticação adicional. | Não há entrega nem crédito financeiro. |
| Recusada ou falha | O processador não autorizou a operação ou a solicitação não pôde ser concluída. | A venda não é tratada como paga. |
| Paga | A autorização foi confirmada pelo processador ou por callback autenticado. | São aplicados os efeitos não financeiros da venda; não é criado crédito no extrato interno. |
| Estornada ou em disputa | O estado financeiro posterior foi alterado pelo processador. | O tratamento segue o fluxo específico de estorno ou disputa. |

O identificador retornado pelo processador é associado à cobrança e à venda. Pedido, identificador externo e eventos de status formam a chave de conciliação operacional.

## 8. Autenticação e confirmação de eventos

O processamento não confia apenas na resposta recebida no momento da compra. Os processadores também podem informar mudanças de estado por callback.

| Origem | Proteção de entrada | Tratamento |
| --- | --- | --- |
| Checkout | Assinatura da chamada para a borda | Solicitações sem assinatura válida não seguem para o domínio de comércio. |
| Cielo E-commerce | Segredo dedicado enviado em cabeçalho | O callback só é encaminhado após a validação do segredo. |
| Pagar.me PSP | Credencial exclusiva de callback | O callback só é encaminhado após a validação da credencial. |

O callback é correlacionado à cobrança existente pelo identificador do processador. Eventos repetidos não devem repetir entrega, atualização financeira ou efeitos de venda.

## 9. Autenticação adicional e prevenção a fraude

O fluxo aceita dados de autenticação 3DS para os dois processadores. Para Cielo, a regra de exigência de 3DS pode depender do valor da venda e da configuração operacional; os dados de autenticação são enviados junto da autorização. Para Pagar.me, o resultado da transação 3DS é associado à cobrança quando fornecido.

Na Cielo, dados de análise antifraude podem acompanhar a autorização quando essa capacidade está configurada. Esses dados incluem elementos de comprador e contexto de compra exigidos pelo provedor para a análise.

3DS e análise antifraude complementam a autorização do cartão; eles não substituem a validação de destinatários, a idempotência nem a confirmação autenticada do estado de pagamento.

## 10. Garantias de integridade financeira

As seguintes invariantes regem a operação:

1. Uma venda paga por cartão com Split possui uma cobrança e um identificador externo correlacionáveis.
2. Os valores enviados ao processador são calculados antes da autorização e não são recalculados silenciosamente após a cobrança.
3. A divisão ocorre no processador selecionado, entre contas habilitadas naquele processador.
4. A confirmação de pagamento libera os efeitos comerciais da venda, mas não cria crédito interno para o vendedor.
5. Uma repetição de requisição ou callback não pode produzir nova cobrança, nova entrega ou segundo efeito financeiro.

## 11. Falhas, repetição e reconciliação

| Situação | Conduta do fluxo |
| --- | --- |
| Recusa de cartão | A cobrança registra a recusa e a venda permanece não paga. |
| Indisponibilidade ou resposta inconclusiva | A cobrança permanece identificável pelo pedido; o estado externo deve ser consultado antes de uma nova tentativa. |
| Divergência de composição | A cobrança é bloqueada antes do envio ao processador. |
| Callback sem credencial válida | O evento é rejeitado na entrada. |
| Callback duplicado | O evento é correlacionado sem repetir os efeitos da venda. |
| Divergência entre venda e processador | Pedido, cobrança, evento e identificador externo são utilizados para reconciliação antes de qualquer ajuste. |

Uma nova tentativa após falha de comunicação depende da verificação da cobrança já associada ao pedido. A plataforma não presume que uma ausência de resposta seja uma recusa.

## 12. Requisitos de proteção operacional

- Credenciais dos processadores e segredos de callback são mantidos como segredos de ambiente, fora de código e de registros funcionais.
- Dados sensíveis de pagamento, tokens e credenciais não devem constar integralmente em logs, filas, mensagens de erro ou ferramentas de suporte.
- Os canais externos para processadores devem usar transporte criptografado e autenticação conforme o contrato de cada provedor.
- Acesso a alteração de processador, conta recebedora, tarifa e configuração de callback deve ser restrito e auditável.
- Alterações no fluxo devem preservar as invariantes de Split, idempotência, correlação e ausência de crédito interno duplicado.
