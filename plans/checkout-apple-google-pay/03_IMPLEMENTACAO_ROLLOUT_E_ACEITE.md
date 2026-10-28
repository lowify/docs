# Plano de implementação e homologação

## Etapa 1 — Habilitação e contrato

1. Confirmar, por ambiente, as contas Cielo e Pagar.me que processam o checkout.
2. Concluir credenciamento Apple Pay e Google Pay, domínios, certificados, chaves e identificadores de merchant.
3. Definir credenciais de homologação e produção no gerenciador de segredos.
4. Formalizar o contrato de capacidades e de autorização de carteira entre checkout, comércio e banking.
5. Definir métricas e códigos de erro normalizados para Apple Pay e Google Pay.
6. Formalizar a classificação persistida da origem: `NULL` para cartão convencional, `1` para Apple Pay e `2` para Google Pay.
7. Criar em `system_vars` as chaves globais `checkout_apple_pay_enabled` e `checkout_google_pay_enabled`, inicialmente desabilitadas.
8. Criar em `tbl_produtos` os campos `apple_pay_enabled` e `google_pay_enabled`, ambos com padrão `0`.

**Saída:** cada gateway possui ambiente de teste pronto e o checkout conhece quais carteiras pode oferecer sem expor dados privados.

## Etapa 2 — Capacidades e cobrança

1. Publicar, junto às opções de cartão, as capacidades de carteira do gateway ativo.
2. Incluir `apple_pay_enabled` e `google_pay_enabled` no modelo, nas requisições de criação e edição e na resposta de dados do formulário.
3. Validar a dependência das carteiras em relação a `credit_card_enabled` e normalizá-las para `0` quando cartão for desligado.
4. Consultar a seleção do produto e a ativação global da carteira antes de publicar a capacidade e antes de processar uma autorização.
5. Estender a entrada de pagamento para distinguir autorização por cartão digitado, Apple Pay e Google Pay.
6. Adicionar a migration, o modelo e os repositórios necessários para `charges_card.wallet_card_id`.
7. Atribuir a classificação somente depois da validação do tipo de autorização no Banking.
8. Implementar a tradução de Apple Pay e Google Pay no adaptador Cielo.
9. Implementar a tradução de Apple Pay e Google Pay no adaptador Pagar.me.
10. Ampliar o processamento de webhooks para atualizar a cobrança já classificada, sem registrar a autorização da carteira.
11. Reutilizar o fluxo existente de criação de pedido, cálculo de taxa, split, cobrança, idempotência, consulta e reembolso.
12. Validar no servidor a consistência entre a carteira solicitada, o gateway ativo e a configuração permitida.

**Saída:** uma autorização de carteira percorre o mesmo ciclo financeiro de uma venda por cartão, sem criar registros alternativos ou persistir material sensível.

## Etapa 3 — Interface do checkout

1. Carregar Apple Pay e Google Pay somente quando a capacidade correspondente estiver habilitada.
2. Validar suporte local antes de renderizar cada botão.
3. Abrir a sessão Apple Pay por intermédio do backend e confirmar a sessão no componente oficial.
4. Construir a requisição Google Pay com a configuração pública do gateway ativo.
5. Adicionar no Dashboard Seller os controles Apple Pay e Google Pay na seção de formas de pagamento, subordinados ao controle de cartão.
6. Estender o normalizador do Dashboard Seller, Edge Gateway e Public API com os contratos de edição, capacidade, autorização e sessão necessários.
7. Enviar o resultado da carteira pelo fluxo de finalização já utilizado pelo checkout.
8. Preservar cartão digitado e os demais meios de pagamento em todos os cenários.

**Saída:** o comprador vê apenas opções compatíveis e pode concluir a compra sem mudança na navegação posterior ao pagamento.

## Etapa 4 — Homologação

| Cenário | Critério de aceite |
| --- | --- |
| Cielo + Apple Pay | Autoriza, registra uma cobrança, preserva valores e permite consulta e reembolso. |
| Cielo + Google Pay | Autoriza, registra uma cobrança, preserva valores e permite consulta e reembolso. |
| Pagar.me + Apple Pay | Autoriza, registra uma cobrança, preserva valores e permite consulta e reembolso. |
| Pagar.me + Google Pay | Autoriza, registra uma cobrança, preserva valores e permite consulta e reembolso. |
| Sem suporte local | Botão não é mostrado; cartão digitado continua utilizável. |
| Produto sem carteira selecionada | A carteira não é publicada, mesmo que esteja habilitada globalmente. |
| Cartão desabilitado no produto | Apple Pay e Google Pay são gravados como desabilitados e não aparecem no checkout. |
| Edição do produto | Não é possível salvar Apple Pay ou Google Pay habilitado sem cartão habilitado. |
| Carteira desativada globalmente | A capacidade não é publicada e uma tentativa recebida após a desativação é rejeitada. |
| Desativação de emergência | Alterar a chave da carteira remove seu botão nas próximas respostas de checkout, sem indisponibilizar cartão convencional. |
| Cancelamento da carteira | Nenhuma cobrança ou pedido duplicado é criado. |
| Recusa do gateway | O checkout comunica a falha sem revelar detalhes sensíveis e permite nova tentativa. |
| Split e taxa | Os valores enviados e conciliados equivalem aos de uma venda de cartão convencional. |
| Classificação persistida | A cobrança usa `NULL`, `1` ou `2` conforme cartão convencional, Apple Pay ou Google Pay; nenhum token é salvo. |
| Webhook | A atualização assíncrona encontra a mesma cobrança, preserva a classificação e permanece idempotente. |
| Observabilidade | Eventos permitem identificar gateway, carteira e resultado sem conter dados de pagamento. |

## Etapa 5 — Liberação

1. Habilitar cada chave global de carteira de forma controlada, depois de homologar as combinações de gateway e carteira.
2. Acompanhar taxa de abertura, autorização, recusa, falha técnica e abandono.
3. Validar diariamente as primeiras conciliações e reembolsos.
4. Expandir a disponibilidade após estabilidade operacional.

## Reversão

A reversão altera para `0` a chave global da carteira em `system_vars`. Não exige migração de dados nem altera cobranças já criadas; cartão digitado continua como alternativa.

## Pontos de controle antes da produção

- Domínio Apple validado e certificados vigentes.
- Merchant e domínio Google aprovados para produção.
- Contas Cielo e Pagar.me habilitadas para as duas carteiras.
- Credenciais de produção separadas das de homologação.
- Chaves globais criadas, inicialmente em `0`, e procedimento operacional de desativação testado.
- Transações reais de homologação aprovadas e conciliadas.
- Equipe de operação com procedimento de renovação de certificado e desabilitação de emergência.
