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

## Formas de pagamento do produto

Apple Pay e Google Pay entram na edição do produto como opções próprias dentro de **Formas de pagamento**. Elas são opções derivadas do cartão: o produto continua usando o mesmo fluxo financeiro de cartão, mas o vendedor decide se aceita cada carteira naquele produto.

| Campo em `tbl_produtos` | Padrão | Regra |
| --- | --- | --- |
| `credit_card_enabled` | Existente | É o pré-requisito para as duas carteiras. |
| `apple_pay_enabled` | `0` | Só pode permanecer habilitado se cartão estiver habilitado. |
| `google_pay_enabled` | `0` | Só pode permanecer habilitado se cartão estiver habilitado. |

Produtos existentes e novos começam com as carteiras desabilitadas. Isso torna a adesão explícita e evita oferecer uma nova forma de pagamento sem escolha do responsável pelo produto.

Ao desabilitar cartão no produto, Apple Pay e Google Pay são automaticamente desabilitados. A interface não permite ativar uma carteira se cartão estiver indisponível para o vendedor ou para aquele produto.

## Regra de disponibilidade

Um botão de carteira só é publicado quando todas as condições abaixo forem verdadeiras:

1. Cartão está habilitado para o produto e para o vendedor.
2. A respectiva carteira está habilitada na edição do produto.
3. A chave global da carteira está ativa em `system_vars`.
4. O gateway selecionado e a conta processadora aceitam a carteira.
5. O dispositivo do comprador é compatível.

Assim, a chave global funciona como freio operacional e a configuração do produto define a oferta comercial. Nenhuma delas substitui a outra.

## Identificação da origem da cobrança

Cada cobrança de cartão conservará a classificação da origem em `charges_card.wallet_card_id`:

| Valor | Origem |
| --- | --- |
| `NULL` | Cartão convencional; preserva todas as cobranças atuais. |
| `1` | Apple Pay. |
| `2` | Google Pay. |

O valor é definido no servidor a partir do tipo de autorização validado para a venda. Ele não é um identificador de cartão, cliente, dispositivo ou token, e não substitui a referência da transação no gateway.

A classificação permite distinguir carteiras em consulta operacional, conciliação, reembolso, suporte e eventos de webhook, sem armazenar o conteúdo da autorização.

## Capacidades por gateway

| Gateway | Apple Pay | Google Pay | Preparação externa necessária |
| --- | --- | --- | --- |
| Cielo e-commerce | A API recebe o payload criptografado da carteira. | A API recebe o token de pagamento gerado pelo Google Pay. | Habilitação comercial/técnica da carteira na conta Cielo e credenciais de produção. |
| Pagar.me PSP | O Pagar.me fornece gestão de chave e certificado e processa o token Apple Pay. | O Google Pay usa o gateway Pagar.me e o identificador da conta Pagar.me. | Habilitação na conta Pagar.me, Merchant ID Apple e cadastro/validação Google. |

## Fronteiras de experiência

- Apple Pay aparece somente em ambiente Apple compatível, após a verificação de domínio e a sessão de comerciante exigidas pela Apple.
- Google Pay aparece somente quando o navegador, a carteira e a configuração do merchant puderem atender ao pedido de pagamento.
- A decisão de mostrar cada botão combina: método cartão habilitado, gateway elegível, ativação global da carteira, carteira habilitada para a conta e capacidade do dispositivo.
- A primeira versão solicita pagamento à vista. Essa limitação evita declarar uma modalidade de parcelamento que ainda não tenha sido aprovada em homologação para cada combinação de gateway e carteira.

## Ativação global e desativação de emergência

As carteiras terão chaves próprias na tabela `system_vars`:

| Chave | Valor | Efeito |
| --- | --- | --- |
| `checkout_apple_pay_enabled` | `0` ou `1` | Controla Apple Pay para todos os checkouts. |
| `checkout_google_pay_enabled` | `0` ou `1` | Controla Google Pay para todos os checkouts. |

As chaves começam desabilitadas e são avaliadas pelo servidor ao publicar as opções de pagamento. Chave ausente, inválida ou desabilitada equivale a não oferecer a carteira.

Esse controle é global: não depende de produto, vendedor nem gateway. Se houver incidente com certificado, domínio, SDK ou configuração de uma carteira, a operação desativa apenas a chave correspondente; nas próximas respostas de checkout o botão deixa de ser oferecido, preservando cartão digitado e os demais meios.

## Requisitos operacionais

Antes da produção, a operação deverá:

1. Habilitar Apple Pay e Google Pay nas contas Cielo e Pagar.me usadas pelo checkout.
2. Criar e manter o Apple Merchant Identifier, os certificados e a associação do domínio do checkout.
3. Concluir o cadastro, a aprovação e a configuração de produção no Google Pay & Wallet Console, incluindo domínio e perfil comercial quando aplicável.
4. Disponibilizar as chaves, identificadores e credenciais exclusivamente na camada de servidor ou no cofre de segredos apropriado.
5. Homologar uma transação de cada carteira para cada gateway antes de liberar tráfego.
6. Habilitar a chave global correspondente somente após a homologação e manter procedimento operacional para desabilitá-la em incidente.

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
