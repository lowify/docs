# Provisionamento de credenciais — Apple Pay e Google Pay

> Guia para a equipe obter os artefatos de produção usados pelo Checkout. Não
> contém segredos, não autoriza ativação e não se aplica ao laboratório local.

## Limite importante

Isto não é sobre o serviço interno `services-wallet`, que mantém extrato,
saldo e saques após a venda. As credenciais abaixo pertencem às carteiras de
pagamento que o JavaScript do `front-checkout` abre e que Commerce/Banking
processam por Cielo ou Pagar.me.

Definir antes o domínio canônico de produção do checkout. A infraestrutura
aceita `checkout.statuslive.site` e `pay.statuslive.site`; todo host que de
fato mostrar o botão Apple Pay deve ser registrado na Apple. Publicar primeiro
em um host ou registrar todos os hosts que exibirem a carteira.

## Resultado que a equipe deve entregar

| Artefato | Quem obtém | Configuração Lowify |
| --- | --- | --- |
| Apple Merchant Identifier | Apple Account Holder/Admin | `APPLE_PAY_MERCHANT_IDENTIFIER` |
| Merchant Identity Certificate e chave privada | Apple Account Holder/Admin | caminhos privados `APPLE_PAY_MERCHANT_CERTIFICATE_PATH` e `APPLE_PAY_MERCHANT_PRIVATE_KEY_PATH` |
| Payment Processing Certificate | Apple + PSP | mantido/configurado pelo PSP |
| Google Pay Merchant ID | Google Pay & Wallet Console | `GOOGLE_PAY_MERCHANT_ID` |
| Cielo gatewayMerchantId | Cielo | `CIELO_GOOGLE_PAY_GATEWAY_MERCHANT_ID` |
| Pagar.me gatewayMerchantId | Pagar.me/Stone | `PAGARME_GOOGLE_PAY_GATEWAY_MERCHANT_ID` |

Não enviar CSR, CER, P12, chave privada, token de PSP ou `.env` por chat, e-mail
ou Git. A entrega ocorre apenas pelo cofre de segredos aprovado.

## 1. Apple Pay: Apple Developer

Requer perfil **Account Holder** ou **Admin** no Apple Developer Program.

1. Abrir [Configure Apple Pay on the web](https://developer.apple.com/help/account/capabilities/configure-apple-pay-on-the-web/).
2. Em **Certificates, Identifiers & Profiles → Identifiers → Merchant IDs**,
   criar o Merchant ID da Lowify. Guardar o identificador; ele não expira.
3. Abrir esse Merchant ID em **Merchant Domains → Add Domain**, cadastrar cada
   domínio HTTPS que exibirá Apple Pay, baixar o arquivo de associação,
   publicá-lo no caminho exato indicado e clicar em **Verify**.
4. No mesmo Merchant ID, abrir **Apple Pay Merchant Identity Certificate →
   Create Certificate**. Gerar CSR na máquina segura da equipe, enviar à Apple
   e baixar o `.cer`.
5. Entregar ao cofre o certificado de identidade **e a chave privada que gerou
   aquele CSR**. DevOps monta ambos com leitura exclusiva do Commerce V2 e
   informa somente os caminhos por variável de ambiente.
6. Registrar responsável e vencimentos: o Merchant ID não expira, mas
   certificados e verificação de domínio expiram.

### Dois certificados Apple, dois propósitos

- **Merchant Identity Certificate**: mTLS entre Commerce V2 e Apple para abrir
  a sessão Apple Pay na web. Este é o par certificado/chave usado pela Lowify.
- **Payment Processing Certificate**: permite ao PSP processar o token
  criptografado. Não substitui o certificado de identidade.

A separação é confirmada pela [documentação de ambiente Apple Pay](https://developer.apple.com/documentation/ApplePayontheWeb/configuring-your-environment).

## 2. Apple Pay no PSP

Executar para cada PSP que efetivamente processará vendas.

### Cielo E-commerce

1. No site Cielo, selecionar o EC: **E-commerce → Gestão API E-commerce →
   Meios de pagamento → Digital wallets**.
2. Habilitar Apple Pay para **plataforma própria**, informando domínio,
   Merchant Identifier e vencimento do certificado quando pedidos.
3. Baixar o CSR fornecido no fluxo Cielo, enviar esse CSR à Apple para emitir o
   **Payment Processing Certificate**, baixar o CER e concluir o fluxo da
   Cielo. Não criar um CSR local substituto quando a Cielo for quem o emitiu.
4. Aguardar a ativação antes da homologação.

Referências: [Digital wallets Cielo](https://docs.cielo.com.br/ecommerce-cielo/v3.0-en/docs/digital-wallets), [Merchant Identifier Cielo](https://docs.cielo.com.br/ecommerce-cielo/docs/configura%C3%A7%C3%A3o-do-merchant-identifier) e [Apple Pay Cielo](https://docs.cielo.com.br/ecommerce-cielo/docs/integra%C3%A7%C3%A3o-com-apple-pay).

### Pagar.me PSP

1. Gerar o CSR pelo endpoint Apple Pay da Pagar.me, autenticado somente pela
   chave secreta mantida pelo responsável Pagar.me.
2. Enviar o CSR à Apple para emitir o **Payment Processing Certificate**.
3. Fazer upload do CER na API Pagar.me e guardar o `externalId` para rotação.

O procedimento oficial, inclusive endpoints, está em [gestão de certificados Apple Pay da Pagar.me](https://docs.pagar.me/docs/apple-pay-gest%C3%A3o-de-certificados). Esse certificado é de processamento; o certificado de identidade da seção 1 continua necessário para a sessão web do Checkout.

## 3. Google Pay: Google Pay & Wallet Console

Neste Checkout, Google Pay usa `PAYMENT_GATEWAY`; não é integração `DIRECT`.
Logo, não existe chave privada Google para gerar. A equipe precisa obter IDs e
aprovações.

1. Abrir [Google Pay & Wallet Console](https://pay.google.com/business/console).
2. Criar/completar o **Business Profile** do tipo Merchant.
3. Abrir **Google Pay API**, aceitar os termos e registrar a integração Web.
4. Adicionar o domínio que chama a API, selecionar **Gateway**, enviar as
   capturas de tela do checkout e submeter para aprovação.
5. Copiar o **Google Pay Merchant ID**: `GOOGLE_PAY_MERCHANT_ID`.
6. Entregar o identificador do PSP usado por cada venda:
   - **Cielo E-commerce:** `gateway=cielo`; solicitar/obter da Cielo o
     `gatewayMerchantId`, um GUID de 36 caracteres.
   - **Pagar.me PSP:** `gateway=pagarme`; usar o `account_id` Pagar.me ou o
     `paymentProfileId` Stone aplicável à conta.

Referências: [publicação Google Pay Web](https://developers.google.com/pay/api/web/guides/test-and-deploy/publish-your-integration), [Google Pay Cielo](https://docs.cielo.com.br/ecommerce-cielo/docs/integracao-com-google-pay) e [Google Pay Pagar.me](https://docs.pagar.me/docs/google-pay-tm-guide).

## 4. Entrega e ativação pela Lowify

1. A equipe externa envia os IDs e o material Apple pelo cofre aprovado.
2. DevOps instala certificado/chave de identidade em volume privado do Commerce
   V2 e configura somente caminhos e IDs; o front-end nunca recebe segredo.
3. O Banking V2 continua com as credenciais normais existentes de Cielo/Pagar.me.
4. Em produção, manter `APPLE_PAY_MERCHANT_VALIDATION_MOCK_ENABLED=false` e
   `GOOGLE_PAY_TEST_MODE=false`.
5. Só após homologação por PSP/dispositivo real, habilitar
   `checkout_apple_pay_enabled` e `checkout_google_pay_enabled` e liberar
   produtos piloto.

## Conferência contra o código atual

- Commerce V2 exige Merchant Identifier, certificado e chave Apple fora de
  mock; se faltarem, a sessão é recusada sem conexão parcial.
- Checkout cria Google Pay com `PAYMENT_GATEWAY` e recebe `merchantId`,
  `gateway` e `gatewayMerchantId` do servidor.
- Cielo usa `gateway=cielo`; Pagar.me usa `gateway=pagarme`; identificador
  ausente deixa a carteira indisponível.
- Serviço Apple do Commerce, resolvedor de meios de pagamento e view de cartão
  passaram pela validação de sintaxe nos containers de teste.

## Não fazer

- Não gerar chave Google de integração `DIRECT`: esse não é o modo Lowify.
- Não colocar certificado/chave Apple em front-end, Dashboard, banco, Git ou logs.
- Não confundir o certificado de processamento Apple com o certificado de
  identidade mTLS.
- Não habilitar a wallet global antes de domínio, certificados, PSP, aprovação
  e homologação estarem concluídos.
