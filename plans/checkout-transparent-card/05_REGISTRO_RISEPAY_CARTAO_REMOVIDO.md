# Registro - cartão RisePay removido

## Motivo deste registro

O cartão da RisePay foi retirado da branch de cartão para que a integração RisePay Pix siga em uma branch própria, criada a partir de `main`. Este arquivo preserva o desenho e os arquivos preparados para uma retomada posterior.

## Desenho preparado

O formulário do Checkout Transparente gerava um JWE Compact com `RSA-OAEP-256` e `A256GCM`. A chave pública e o identificador da chave vinham apenas na disponibilidade pública do checkout. O envelope levava número, validade, CVV e nome do titular.

Antes do envio do formulário, `card_number`, `card_expiry`, `card_cvv`, `card_holder` e `card_holder_document` eram removidos do `FormData`. O Edge recebia apenas o envelope e chamava uma rota específica da CT API. A CT API decifrava em memória, criava a cobrança diretamente na RisePay e publicava na fila existente somente o resultado normalizado.

Assim, PAN, CVV e validade completa não eram colocados em Redis, `charge_attempts`, auditorias, logs ou respostas HTTP. O caminho continuava usando a `charge`, a `charge_attempt` e a confirmação idempotente já existentes.

## Componentes preparados

| Camada | Preparação removida |
| --- | --- |
| Front Checkout | Provider `risepay` com Web Crypto, geração de JWE e remoção dos campos brutos do envio. |
| Edge Public API | Encaminhamento do envelope para `/risepay-card-attempts`, sem enviar o cartão ao Commerce V2. |
| CT API | Decriptador JWE, cliente direto RisePay, rota sensível, resultado normalizado e disponibilidade condicionada à configuração de chaves. |
| Dashboard Seller | Ação para habilitar `card_credit` reutilizando o `private_token` da integração RisePay. |
| Configuração | `CHECKOUT_RISEPAY_CARD_ENABLED`, identificador da chave, chave pública, chave privada e timeout. |

## Resposta da RisePay e falhas

O cliente seguia o mesmo formato já usado pelo Pix da RisePay: `success`, `data.object`, `identifier`, `externalReference` e `status`. Respostas aprovadas, pendentes e recusadas eram convertidas para o envelope consumido por `GatewayResultQueueProcess`.

Em timeout, erro de rede ou resposta `5xx`, a tentativa ficaria sem reenvio automático, pois a RisePay pode ter aceitado a cobrança antes da perda da resposta. A ativação exigiria confirmar uma consulta confiável por referência externa para reconciliar esse estado antes de liberar outra tentativa.

## Dependência e validação realizadas

A CT API recebeu `web-token/jwt-framework`. O JWE produzido com Web Crypto do navegador foi decriptado com sucesso pela biblioteca PHP em teste interno. A rota autenticada iniciou e a API foi reconstruída sem erros de sintaxe.

## Condições para retomar

1. Definir o armazenamento e a rotação da chave privada fora do repositório.
2. Validar os componentes de proxy, observabilidade e backup que possam capturar corpos HTTP.
3. Confirmar idempotência e reconciliação por referência externa com a RisePay.
4. Validar escopo PCI e privacidade antes de habilitar qualquer seller.

## Referências

- [RisePay API](https://docs.risepay.com.br/risepay-api)
- [LGPD, arts. 46 e 47](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm)
- [PCI SSC: CVV após autorização](https://www.pcisecuritystandards.org/faqs/are-merchants-allowed-to-request-card-verification-codes-values-from-cardholders/)
