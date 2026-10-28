# Contrato de carteira e responsabilidades

## Modelo de integração

A interface inicia a carteira oficial e recebe uma autorização criptografada. Essa autorização é encaminhada ao backend junto com o pedido de compra e convertida, no adaptador do gateway selecionado, para a requisição própria da Cielo ou do Pagar.me.

O contrato separa a intenção de pagamento do formato particular de cada provedor:

| Campo lógico | Finalidade |
| --- | --- |
| payment_method | Mantém cartão como método comercial da venda. |
| authorization_type | Distingue cartão digitado, Apple Pay e Google Pay. |
| wallet_payload | Carrega exclusivamente a autorização retornada pela carteira. |
| billing_address | Mantém os dados de cobrança exigidos pela antifraude ou pelo gateway. |
| installments | Será fixado em uma parcela na primeira versão. |

O payload de carteira é de uso único e sensível. Ele não deve ser salvo no banco, exposto em resposta pública, registrado em observabilidade ou repetido em retentativas fora do mecanismo normal de idempotência.

## Disponibilidade enviada ao checkout

A resposta de opções de pagamento passa a informar capacidades, sem entregar credenciais privadas:

    {
      "card": {
        "enabled": true,
        "provider": "cielo_ecommerce",
        "wallets": {
          "apple_pay": { "enabled": true },
          "google_pay": { "enabled": true, "merchant_id": "public-merchant-id" }
        }
      }
    }

O contrato definitivo usará nomes consistentes com a API atual. Informar uma carteira como habilitada significa que a conta e o gateway podem recebê-la; o cliente ainda deve confirmar suporte no dispositivo antes de exibir o botão.

## Responsabilidades

| Camada | Responsabilidade |
| --- | --- |
| Comércio | Define se cartão está disponível para a venda e publica as capacidades permitidas para o gateway ativo. |
| Checkout | Carrega os SDKs oficiais, avalia compatibilidade local, apresenta o botão correto e envia a autorização sem inspecionar seus dados internos. |
| Borda/API | Autentica e valida o formato, tamanho e origem do pedido antes de encaminhá-lo ao serviço de comércio. |
| Comércio e Banking | Preservam o ciclo de pedido e cobrança e encaminham a autorização ao adaptador correto. |
| Adaptador Cielo/Pagar.me | Traduz o payload da carteira para a API do provedor e normaliza sucesso, recusa e erro técnico. |
| Operação | Mantém habilitações, domínios, certificados, chaves e identificadores das carteiras. |

## Apple Pay

O checkout utiliza Apple Pay JS. A sessão de pagamento exige validação de comerciante no servidor, em domínio HTTPS previamente registrado. O backend responde à interface somente com a sessão necessária e encaminha o token de pagamento ao gateway.

Para Pagar.me, a gestão de chave e certificado é feita pelas APIs específicas de Apple Pay da própria plataforma. Para Cielo, a configuração seguirá o credenciamento de carteira e o contrato da API e-commerce. Em ambos os casos, a renovação de certificados e a troca de credenciais devem ocorrer sem interrupção, mantendo material novo e vigente durante a transição.

## Google Pay

O checkout utiliza a biblioteca Google Pay Web. A configuração pública informa o gateway e os identificadores autorizados para a conta que processará a venda. O token gerado pelo Google Pay é encaminhado sem alteração semântica ao adaptador.

O modo de produção depende de aprovação e configuração de merchant no Google, além da ativação correspondente no gateway. A interface deve usar ambiente de teste apenas nas rotas e credenciais de homologação.

## Falhas e segurança

- Cancelamento pelo comprador encerra somente a tentativa da carteira; não cria nova cobrança.
- Recusa do gateway é apresentada como recusa de pagamento e mantém as demais opções de cartão disponíveis.
- Erro de configuração, sessão ou SDK oculta a carteira naquela tentativa e gera evento técnico sem dados sensíveis.
- A autorização é transmitida por HTTPS e manipulada apenas pelo tempo necessário para realizar a cobrança.
- Logs e métricas registram gateway, carteira, resultado e correlação da tentativa, nunca token, PAN, criptograma, certificado ou endereço completo.
