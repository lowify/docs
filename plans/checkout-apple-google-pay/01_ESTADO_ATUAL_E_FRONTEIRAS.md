# Decisão de produto e fronteiras

## Decisão

Apple Pay e Google Pay serão oferecidos como autorizações de cartão no checkout normal. A escolha do gateway da venda continua centralizada na configuração de checkout existente; a carteira não escolhe, troca ou cria um processador.

A implantação se limita a Cielo e-commerce e Pagar.me PSP. Ambos suportam as duas carteiras em suas ofertas de e-commerce. Outros provedores não fazem parte desta entrega porque o objetivo é ampliar os meios de autorização onde o cartão já é oferecido, e não construir uma nova operação de cartão.

## Comportamento da venda

| Aspecto | Comportamento preservado |
| --- | --- |
| Elegibilidade | A carteira só é apresentada se o pagamento por cartão já estiver disponível para a oferta e o vendedor. |
| Gateway | A cobrança é enviada ao mesmo gateway definido para o checkout. |
| Pedido e cobrança | Continuam sendo criados uma única vez, com a mesma idempotência e estados de pagamento. |
| Valores | Valor, moeda, taxa, split e dados de cobrança seguem as regras atuais de cartão. |
| Pós-venda | Consulta, reembolso, conciliação e atendimento usam a referência de cobrança já adotada pelo gateway. |
| Alternativa | Cartão digitado permanece disponível se a carteira não estiver elegível, não for suportada ou falhar antes da autorização. |

## Capacidades por gateway

| Gateway | Apple Pay | Google Pay | Preparação externa necessária |
| --- | --- | --- | --- |
| Cielo e-commerce | A API recebe o payload criptografado da carteira. | A API recebe o token de pagamento gerado pelo Google Pay. | Habilitação comercial/técnica da carteira na conta Cielo e credenciais de produção. |
| Pagar.me PSP | O Pagar.me fornece gestão de chave e certificado e processa o token Apple Pay. | O Google Pay usa o gateway Pagar.me e o identificador da conta Pagar.me. | Habilitação na conta Pagar.me, Merchant ID Apple e cadastro/validação Google. |

## Fronteiras de experiência

- Apple Pay aparece somente em ambiente Apple compatível, após a verificação de domínio e a sessão de comerciante exigidas pela Apple.
- Google Pay aparece somente quando o navegador, a carteira e a configuração do merchant puderem atender ao pedido de pagamento.
- A decisão de mostrar cada botão combina: método cartão habilitado, gateway elegível, carteira habilitada para a conta e capacidade do dispositivo.
- A primeira versão solicita pagamento à vista. Essa limitação evita declarar uma modalidade de parcelamento que ainda não tenha sido aprovada em homologação para cada combinação de gateway e carteira.

## Requisitos operacionais

Antes da produção, a operação deverá:

1. Habilitar Apple Pay e Google Pay nas contas Cielo e Pagar.me usadas pelo checkout.
2. Criar e manter o Apple Merchant Identifier, os certificados e a associação do domínio do checkout.
3. Concluir o cadastro, a aprovação e a configuração de produção no Google Pay & Wallet Console, incluindo domínio e perfil comercial quando aplicável.
4. Disponibilizar as chaves, identificadores e credenciais exclusivamente na camada de servidor ou no cofre de segredos apropriado.
5. Homologar uma transação de cada carteira para cada gateway antes de liberar tráfego.

Essas providências são etapas de ativação e configuração da entrega; não constituem restrições arquiteturais para a implementação.

## Referências de capacidade

- [Cielo — carteiras digitais](https://docs.cielo.com.br/ecommerce-cielo/docs/e-wallets)
- [Cielo — Apple Pay](https://docs.cielo.com.br/ecommerce-cielo/docs/integra%C3%A7%C3%A3o-com-apple-pay)
- [Cielo — Google Pay](https://docs.cielo.com.br/ecommerce-cielo/docs/google-pay)
- [Pagar.me — Apple Pay](https://docs.pagar.me/docs/apple-pay-1)
- [Pagar.me — certificados Apple Pay](https://docs.pagar.me/docs/apple-pay-gest%C3%A3o-de-certificados)
- [Pagar.me — Google Pay](https://docs.pagar.me/docs/google-pay-tm-guide)
- [Apple Developer — Apple Pay on the Web](https://developer.apple.com/documentation/applepayontheweb)
- [Google Pay — integração web](https://developers.google.com/pay/api/web/guides/tutorial)
