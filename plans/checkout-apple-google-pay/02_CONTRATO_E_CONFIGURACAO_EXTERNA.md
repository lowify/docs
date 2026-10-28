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

Ao criar a cobrança, o Banking converte `authorization_type` em `wallet_card_id`: `NULL` para cartão convencional, `1` para Apple Pay e `2` para Google Pay. A classificação é determinada internamente; uma entrada incompatível com o gateway ou com a capacidade publicada é rejeitada.

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

## Edição do produto

A API de criação, leitura e atualização de produto passa a aceitar e devolver `apple_pay_enabled` e `google_pay_enabled`. O Dashboard Seller os apresenta como novas formas de pagamento, junto de Pix e cartão de crédito.

As duas opções são dependentes de `credit_card_enabled`:

- ao habilitar uma carteira, a API exige cartão habilitado;
- ao desabilitar cartão, a API normaliza as duas carteiras para `0`;
- se a integração de cartão do vendedor não estiver disponível, os controles permanecem indisponíveis;
- a resposta do formulário informa o estado salvo e a elegibilidade necessária para renderizar os controles corretamente.

A atualização não confia somente na interface. A validação é repetida no normalizador do Dashboard Seller, nas requisições da API de Comércio e no caso de uso que calcula as formas disponíveis no checkout.

## Controle global

O Comércio consulta as chaves `checkout_apple_pay_enabled` e `checkout_google_pay_enabled` em `system_vars` antes de publicar uma capacidade de carteira. A ausência, valor inválido ou `0` deve resultar em `enabled: false`, ainda que o produto tenha selecionado a carteira.

O controle não é enviado como credencial nem aceito como decisão do cliente. Ele é aplicado antes de iniciar Apple Pay, Google Pay ou criar a cobrança, para que uma mudança operacional remova a carteira do checkout e também rejeite uma tentativa tardia.

## Responsabilidades

| Camada | Responsabilidade |
| --- | --- |
| Dashboard Seller | Permite selecionar Pix, cartão, Apple Pay e Google Pay; aplica a dependência visual de carteira em relação ao cartão. |
| Comércio | Valida e persiste a seleção do produto, aplica a ativação global e publica as capacidades permitidas para o gateway ativo. |
| Checkout | Carrega os SDKs oficiais, avalia compatibilidade local, apresenta somente a carteira selecionada e envia a autorização sem inspecionar seus dados internos. |
| Borda/API | Autentica e valida o formato, tamanho e origem do pedido antes de encaminhá-lo ao serviço de comércio. |
| Comércio e Banking | Preservam o ciclo de pedido e cobrança, atribuem a classificação da carteira e encaminham a autorização ao adaptador correto. |
| Adaptador Cielo/Pagar.me | Traduz o payload da carteira para a API do provedor e normaliza sucesso, recusa e erro técnico. |
| Webhooks | Reutilizam a referência da cobrança para atualizar o mesmo registro e preservam sua classificação; não recebem nem persistem o payload da carteira. |
| Operação | Mantém habilitações, domínios, certificados, chaves, identificadores e ativações globais das carteiras. |

## Superfícies públicas

| Superfície | Responsabilidade |
| --- | --- |
| Checkout | Apresenta as carteiras, abre a sessão Apple Pay e envia a autorização. |
| Edge Gateway / Public API | Expõe somente os contratos necessários ao checkout, incluindo capacidades de carteira, criação da autorização e validação de sessão Apple Pay. |
| Banking | Registra `wallet_card_id`, executa a cobrança no gateway e recebe as atualizações assíncronas da cobrança. |

Não será criado um webhook paralelo apenas para a carteira. Quando Cielo ou Pagar.me notificarem uma cobrança, o webhook existente deve reconhecer a transação e atualizar o mesmo registro. Caso o contrato de algum gateway exija uma rota adicional para carteira, ela será tratada como extensão do mesmo ciclo de cobrança, com idempotência e validação de assinatura.

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
