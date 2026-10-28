# Plano de implementação e homologação

## Etapa 1 — Habilitação e contrato

1. Confirmar, por ambiente, as contas Cielo e Pagar.me que processam o checkout.
2. Concluir credenciamento Apple Pay e Google Pay, domínios, certificados, chaves e identificadores de merchant.
3. Definir credenciais de homologação e produção no gerenciador de segredos.
4. Formalizar o contrato de capacidades e de autorização de carteira entre checkout, comércio e banking.
5. Definir métricas e códigos de erro normalizados para Apple Pay e Google Pay.

**Saída:** cada gateway possui ambiente de teste pronto e o checkout conhece quais carteiras pode oferecer sem expor dados privados.

## Etapa 2 — Capacidades e cobrança

1. Publicar, junto às opções de cartão, as capacidades de carteira do gateway ativo.
2. Estender a entrada de pagamento para distinguir autorização por cartão digitado, Apple Pay e Google Pay.
3. Implementar a tradução de Apple Pay e Google Pay no adaptador Cielo.
4. Implementar a tradução de Apple Pay e Google Pay no adaptador Pagar.me.
5. Reutilizar o fluxo existente de criação de pedido, cálculo de taxa, split, cobrança, idempotência, consulta e reembolso.
6. Validar no servidor a consistência entre a carteira solicitada, o gateway ativo e a configuração permitida.

**Saída:** uma autorização de carteira percorre o mesmo ciclo financeiro de uma venda por cartão, sem criar registros alternativos ou persistir material sensível.

## Etapa 3 — Interface do checkout

1. Carregar Apple Pay e Google Pay somente quando a capacidade correspondente estiver habilitada.
2. Validar suporte local antes de renderizar cada botão.
3. Abrir a sessão Apple Pay por intermédio do backend e confirmar a sessão no componente oficial.
4. Construir a requisição Google Pay com a configuração pública do gateway ativo.
5. Enviar o resultado da carteira pelo fluxo de finalização já utilizado pelo checkout.
6. Preservar cartão digitado e os demais meios de pagamento em todos os cenários.

**Saída:** o comprador vê apenas opções compatíveis e pode concluir a compra sem mudança na navegação posterior ao pagamento.

## Etapa 4 — Homologação

| Cenário | Critério de aceite |
| --- | --- |
| Cielo + Apple Pay | Autoriza, registra uma cobrança, preserva valores e permite consulta e reembolso. |
| Cielo + Google Pay | Autoriza, registra uma cobrança, preserva valores e permite consulta e reembolso. |
| Pagar.me + Apple Pay | Autoriza, registra uma cobrança, preserva valores e permite consulta e reembolso. |
| Pagar.me + Google Pay | Autoriza, registra uma cobrança, preserva valores e permite consulta e reembolso. |
| Sem suporte local | Botão não é mostrado; cartão digitado continua utilizável. |
| Cancelamento da carteira | Nenhuma cobrança ou pedido duplicado é criado. |
| Recusa do gateway | O checkout comunica a falha sem revelar detalhes sensíveis e permite nova tentativa. |
| Split e taxa | Os valores enviados e conciliados equivalem aos de uma venda de cartão convencional. |
| Observabilidade | Eventos permitem identificar gateway, carteira e resultado sem conter dados de pagamento. |

## Etapa 5 — Liberação

1. Liberar por gateway e por carteira, inicialmente com configuração controlada.
2. Acompanhar taxa de abertura, autorização, recusa, falha técnica e abandono.
3. Validar diariamente as primeiras conciliações e reembolsos.
4. Expandir a disponibilidade após estabilidade operacional.

## Reversão

A reversão desabilita a capacidade da carteira na configuração do checkout. Não exige migração de dados nem altera cobranças já criadas; cartão digitado continua como alternativa.

## Pontos de controle antes da produção

- Domínio Apple validado e certificados vigentes.
- Merchant e domínio Google aprovados para produção.
- Contas Cielo e Pagar.me habilitadas para as duas carteiras.
- Credenciais de produção separadas das de homologação.
- Transações reais de homologação aprovadas e conciliadas.
- Equipe de operação com procedimento de renovação de certificado e desabilitação de emergência.
