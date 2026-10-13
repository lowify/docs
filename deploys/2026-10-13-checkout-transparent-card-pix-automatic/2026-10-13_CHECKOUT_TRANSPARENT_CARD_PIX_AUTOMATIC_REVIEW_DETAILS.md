# Checkout Transparente — esclarecimentos e regras de aceite

Data: 2026-10-13. Complemento ao [roteiro de revisão](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW.md), em resposta aos pontos 1–9 discutidos com o responsável pelo produto. Mesmas versões de código do roteiro original. Este documento registra diagnóstico e requisitos; não indica que as correções foram implementadas.

## 1. Por que aparecem dois webhooks?

O CT tem, sim, seu webhook próprio: `services-checkout-transparent/edge-checkout-transparent-webhook`. Ele recebe eventos externos, resolve integração/cobrança e publica a confirmação no Redis isolado do CT. Foi incluído na revisão.

O caminho implementado para confirmar uma recorrência na plataforma principal é:

```text
Efí/Woovi → ct-webhook → Redis CT → CT-API
→ HTTP /api/checkout-transparent/subscription-paid no edge-webhook principal
→ Redis principal: sales:subscriptions:actions → Commerce V2
```

Isso está explícito em `CommerceWebhookClient::notifySubscriptionPayment`. O edge-webhook principal adiciona a rota em `routes/api.php` e, em `CheckoutTransparentWebhookHandler`, encaminha `subscription.charge.paid` para a fila do Commerce.

Portanto, o problema não é ausência de webhook do CT: é que o plano original não publica a segunda etapa, adicionada na branch do edge-webhook principal. Se o desenho desejado for eliminar essa dependência, é necessário mudar o contrato de saída do CT e o consumidor; ela não desaparece só por existir o ct-webhook.

## 2. Token no checkout, descriptografia no CT e duplicidade

### O que está implementado

| Provider | Navegador | CT-API / execução |
| --- | --- | --- |
| Mercado Pago | `createCardToken` do SDK retorna `payment_token`. | Não abre dados do cartão; encaminha o token para a instrução do worker. |
| Pagar.me | Envia cartão diretamente ao endpoint de tokenização e recebe um ID. | Encaminha o token ao worker. O caminho 3DS existente é uma exceção que exige revisão separada. |
| Efí | SDK gera `payment_token`. | Encaminha ao worker; não existe descriptografia local desse token para obter PAN/CVV. |
| RisePay | `buildRisePayJweProvider` monta `encrypted_card` com os dados do cartão. | `RisePayCardJweDecryptor` abre o envelope; `CreateRisePayCardAttemptUseCase` chama a RisePay diretamente, sem enviar PAN/CVV pela fila do worker. |

Token do provedor é uma referência opaca, não uma cifra que a Lowify deve abrir. O modelo descrito pelo produto — navegador cifra e CT abre — já existe especificamente na RisePay.

Na RisePay, o navegador usa RSA-OAEP-256 para proteger uma chave AES aleatória e AES-256-GCM para o conteúdo. Há chave AES e IV aleatórios a cada envelope. O CT valida `alg`, `enc`, `kid`, tamanho e descriptografia autenticada. A chave privada fica no CT; só a pública é enviada ao checkout.

**Lacunas confirmadas:** o conteúdo possui número, CVV, validade e titular, mas não `issued_at`, expiração, nonce, identificação da operação ou vínculo com integração/venda. O decryptor não confere esses vínculos. A cifra já varia por aleatoriedade, mas isso não fornece validade temporal nem impede replay.

O transporte interno tem HMAC com timestamp e o middleware exige uma chave de idempotência. Isso não substitui a validade/vinculação do envelope nem implementa, por si só, a deduplicação da operação.

Outra lacuna: o formulário só exclui campos brutos do `FormData` para alguns providers; tokens MP/Pagar.me/Efí podem seguir acompanhados do cartão em aberto. Todo caminho tokenizado deve enviar somente o token/envelope e os campos permitidos. Criptografar um campo não protege uma cópia enviada em paralelo.

### Como fechar o desenho pretendido

Separar três identidades, porque têm funções diferentes:

| Identidade | Função | Comportamento em repetição |
| --- | --- | --- |
| ID da operação/tentativa | Impedir duas cobranças da mesma intenção. | Mantido no duplo clique, retry HTTP e retomada de timeout. |
| Nonce/JTI do envelope | Identificar o envelope e detectar replay indevido. | Novo envelope pode ter outro nonce, mas não deve virar nova operação automaticamente. |
| `issued_at` / `expires_at` | Restringir o período de uso inicial. | Validado com relógio do servidor e tolerância limitada; não é uma chave de deduplicação. |

O contrato do envelope deve vincular operação, sessão/checkout e integração/método esperados. O CT valida esse contexto contra uma operação autorizada pelo servidor. Preço, seller, produto e parcelas não se tornam confiáveis só porque vieram criptografados: qualquer pessoa com a chave pública consegue gerar um JWE. A autorização continua nas rotas e a regra da venda continua no Commerce.

Persistir no CT a identidade da operação, escopo, fingerprint dos campos de negócio permitidos, estado (`received`, `processing`, resultado conhecido ou `unknown`), IDs externos, timestamps e resposta segura. Usar constraint única para a identidade e locking/transação para concorrer com outra requisição.

- Mesma identidade e mesmo negócio: retornar a tentativa existente; não chamar o provider novamente.
- Mesma identidade com valor, parcelas ou escopo incompatíveis: rejeitar conflito.
- Timeout após enviar: marcar resultado desconhecido e reconciliar. Não cobrar de novo sem saber o resultado anterior.
- Nova tentativa após recusa conhecida: criar outro ID de tentativa, vinculado à mesma venda, conforme a regra de negócio.
- A política de envelope expirado e retry deve permitir consultar um resultado já existente por uma rota autorizada; recuperar resultado não exige reutilizar cartão/CVV.

**Problema atual de identidade:** a public-api deriva a chave de tentativa de `orderId + paymentToken` ou `orderId + encryptedCard`. Se uma repetição gera outro token/envelope, a chave muda. Adicionar hora ao token pode agravar isso: o payload fica único, mas o pagamento repetido deixa de parecer a mesma operação. O ID da operação deve ser independente da cifra e sobreviver à repetição.

O código já grava tentativas e possui busca por cobrança/chave de idempotência. É uma base útil, mas o middleware apenas verifica presença do header, e não foi encontrado fingerprint equivalente para detectar mudança de negócio sob a mesma chave.

### O que persistir, e o que não persistir

Para deduplicação, guardar metadados operacionais, não os dados brutos do cartão. Não guardar CVV nem o JWE contendo CVV como histórico após autorização. Essa proibição inclui dados criptografados, conforme o [PCI SSC](https://www.pcisecuritystandards.org/faqs/1319/). A criptografia própria não remove o backend do escopo de segurança de cartão: ele passa a processar PAN/CVV ao abrir o envelope.

Um token de provedor não é equivalente ao CVV, mas sua retenção depende do contrato, finalidade e proteção aplicáveis. Não estabelecer retenção genérica sem essa análise. Evitar também hash de PAN/CVV como mecanismo de deduplicação. O roteiro recomenda não persistir o envelope sensível e consultar a operação pelos IDs externos em recuperação.

**Aceite:** duplo clique, duas requisições concorrentes, novo envelope para o mesmo ID e timeout depois de sucesso produzem no máximo uma cobrança lógica; envelope expirado, adulterado ou de outro contexto é rejeitado; nenhum log/fila/auditoria armazena cartão/CVV.

## 3. O problema do refresh Mercado Pago, em um exemplo

1. Ao configurar a integração, o token `A` fica nas chaves da integração e é copiado para as chaves de Pix/cartão.
2. O processo OAuth renova o token e grava `B` nas chaves da integração.
3. As cópias dos métodos continuam com `A`.
4. O worker de uma cobrança lê as chaves do método em `GetGatewayContextUseCase::execute`, então continua recebendo `A`.

Quando o token antigo expirar/for rejeitado, as cobranças podem falhar apesar do refresh registrado como sucesso. `executeByIntegrationId` também pode sobrepor a credencial atual da integração com a cópia do método, quando recebe o método.

**Aceite:** uma única fonte para credenciais OAuth compartilhadas, ou atualização consistente das cópias e da expiração; nenhuma renovação deixa Pix/cartão presos a um token antigo. Validar com credenciais sintéticas e homologação sem imprimir tokens.

## 4. O problema das filas e da criação parcial, em exemplos

**Caso A — assinatura salva, tarefa não enviada:** o CT grava a assinatura; Redis falha ao publicar a criação; a requisição seguinte encontra a assinatura existente e retorna sem republicar. O cadastro existe, mas não há operação no provider. O polling pula assinaturas sem ID externo.

**Caso B — tarefa retirada, processo cai:** `BLPOP` remove a mensagem da fila. Se o worker cair antes de gravar/publicar resultado, não há mensagem pendente para outro worker recuperar. Os retries atuais são em memória e não cobrem morte do processo.

**Caso C — criação Efí pela metade:** criação de location e cobrança imediata funciona, criação/consulta da recorrência falha. Recomeçar toda a sequência pode criar outros recursos; o código não persiste checkpoints de cada etapa para retomá-la com segurança.

Isso não significa que toda requisição duplica, nem que não existe retry. Significa que os retries atuais não cobrem esses intervalos de falha.

**Aceite:** registrar a intenção de publicação junto do cadastro (outbox ou mecanismo equivalente), retomar as operações incompletas e consumir com reserva/ACK e recuperação após queda. Persistir etapas/IDs externos e usar idempotência do provider quando disponível. Falha de publicação, kill do worker e timeout intermediário não podem abandonar nem recriar cegamente a operação.

## 5. Cancelamento deve parar autorização, cobrança e novos ciclos

**Regra definida pelo produto:** identificar o cancelamento, cancelar a cobrança ainda não liquidada e impedir geração de novos valores.

Hoje o polling Efí reconhece `CANCELADA`/`EXPIRADA` e altera o estado da assinatura. O resolvedor do ct-webhook trata pagamento inicial e parcela concluída, mas não fecha o fluxo de cancelamento da autorização. A confirmação de uma parcela também pode transformar uma assinatura cancelada em `active`, pois atualiza o estado sem proteger o cancelamento anterior.

O tratamento deve abranger:

- Receber cancelamento por webhook e usar consulta como recuperação, não depender somente da rodada horária.
- Marcar a assinatura como terminal para novos ciclos; impedir novas instruções no scheduler e impedir execução de uma instrução antiga já enfileirada.
- Cancelar localmente parcelas não enviadas e solicitar cancelamento das cobranças abertas no provider conforme o contrato. Persistir confirmação ou pendência de reconciliação do cancelamento.
- Tratar a corrida: se o pagamento já ocorreu, registrar a liquidação real sem reativar a assinatura. Cancelamento não é estorno automático de parcela paga.
- Preservar pagamentos e custos históricos; não apagar venda, autorização ou parcela para representar cancelamento.

**Aceite:** cancelamento antes do agendamento, depois da publicação e durante chamada externa não produz ciclos futuros; pagamento atrasado de parcela anterior é conciliado sem ressuscitar a assinatura.

## 6. Consulta de recuperação da primeira cobrança Efí

O fluxo atual cria a primeira cobrança como Pix imediato (`POST /v2/cob`). As posteriores são Pix recorrente (`PUT /v2/cobr/{txid}`). O polling consulta toda parcela em `/v2/cobr/{id}`, inclusive a primeira.

Exemplo: cliente paga a primeira cobrança, mas o webhook não chega. O CT tenta consultar o pagamento no recurso das cobranças recorrentes; aquele txid foi criado no recurso imediato. O pagamento existe, mas esse fallback não recupera o estado pelo caminho correto.

**Aceite:** persistir/distinguir tipo da parcela; consultar a inicial em `/v2/cob/{txid}` e as posteriores em `/v2/cobr/{txid}`, interpretando a resposta correta de cada contrato. Não confundir `/v2/rec/{idRec}`, que consulta a autorização, com pagamento. Referências: [Efí — cobrança imediata](https://dev.efipay.com.br/docs/api-pix/cobrancas-imediatas/) e [Pix Automático](https://dev.efipay.com.br/docs/api-pix/pix-automatico/).

## 7. Quando gerar a cobrança de billing

Aqui, “billing” significa o custo/cobrança da Lowify pelo processamento, não uma nova cobrança do cartão do comprador. O provider já cobra o valor da compra segundo o parcelamento contratado.

**Regra definida pelo produto:** cartão gera billing uma vez, na primeira parcela/primeira confirmação elegível da compra parcelada; Pix assinatura gera billing quando o pagamento de cada recorrência é confirmado. Não cobrar novamente só por consultar status ou receber webhook repetido.

O caminho avulso/cartão já tem snapshot de taxas e publicação em `ConfirmChargePaymentUseCase`. O caminho de `ConfirmCheckoutSubscriptionPaymentUseCase` não possui a publicação equivalente para cada parcela recorrente. Esse é o achado, e não uma proposta de cobrar cartão a cada prestação.

**Aceite:** compra de cartão em 12 parcelas gera um único item/evento de custo conforme a política; Pix recorrente gera um por pagamento elegível, com chave de deduplicação por assinatura/parcela/tipo de custo. Autorização ativa, parcela agendada, pagamento falho e eventos duplicados não geram custo adicional. Documentar também o enquadramento do pagamento inicial da jornada Pix na política financeira.

## 8. Por que o limite de 100 pode bloquear outros registros?

O limite é normal; o problema é não avançar o lote. A consulta seleciona os 100 registros mais antigos por `updated_at`. Uma assinatura ativa que continua ativa não avança necessariamente esse campo. Na rodada seguinte, as mesmas 100 podem ser selecionadas de novo, e a 101ª fica de fora indefinidamente.

Além disso, a consulta seleciona antes de filtrar o provider. Registros Woovi podem ocupar o lote de uma rotina Efí, e o processo depois simplesmente os pula. Há padrão semelhante para parcelas pendentes.

**Aceite:** filtrar provider no banco e controlar `next_poll_at`/`last_polled_at` ou cursor justo, com índice adequado. Verificar 250+ registros, providers misturados e estados que não mudam: todos os elegíveis recebem consulta dentro do SLA. Acompanhar idade do registro sem consulta, não somente quantidade de requests. Concorrência dos workers deve respeitar limites do provider e não multiplicar cobranças.

## 9. Regras adicionais definidas pelo produto

| Requisito | Tratamento / critério de aceite |
| --- | --- |
| Dias 31, 30 e fevereiro | Usar um calendário único no primeiro e nos próximos vencimentos, preservando dia-âncora. Proposta: limitar ao último dia do mês e recuperar o dia-âncora no mês seguinte (`31/jan → 28/fev → 31/mar`). Política proposta, ainda não homologada; testar ano bissexto e ajuste de dia útil do provider. |
| Ativar só depois de validar | Método não fica disponível enquanto integração/credenciais/escopos/webhooks exigidos estiverem pendentes ou reprovados. Tentativa de ativação mostra modal de “integração não aprovada”, com motivo seguro. Backend também rejeita; não basta ocultar botão. |
| Um gateway ativo por método | Confirmado pelo usuário: exclusividade por seller + método. Pix na Efí e cartão na RisePay podem coexistir; dois gateways para cartão não. `is_default` sozinho não basta: preservar no máximo um método efetivamente habilitado/disponível em concorrência, em todos os endpoints. |
| Regra de cartão centralizada no Commerce V2 | Commerce é a fonte das regras da venda: produto, valor, parcelas, limites e elegibilidade. CT mantém segurança e restrições técnicas do provider, mas não cria outra regra comercial independente. Encaminhar parcelas ao Commerce e validar o contrato autoritativo antes da execução. |
| Habilitar RisePay | Entra no escopo de aceite, em vez de permanecer excluído. Código já possui provider JWE, decryptor e caminho de cobrança, mas está sob flag desabilitada. Habilitar exige chave pública/privada, validade/vínculo do envelope, idempotência estável, confirmação/reconciliação de timeout e homologação das rotas. Não considerar cumprido apenas por alterar a flag. |

Ao trocar o gateway ativo, não perder a associação das assinaturas/obrigações existentes com a integração original. Desabilitar novas vendas não pode impedir reconciliação e cancelamento de operações antigas. Definir explicitamente se assinaturas antigas continuam até cancelamento; não migrá-las automaticamente para outro provider.

## Sequência sugerida de implementação e revisão

1. Fechar contratos: identidade da operação, envelope, estados de autorização/pagamento/cancelamento, exclusividade por método e regras Commerce.
2. Corrigir persistência/idempotência, publicação e recuperação; atualizar credenciais compartilhadas e calendário.
3. Fechar callbacks, cancelamento, consulta inicial/recorrente e billing no momento definido.
4. Completar rotas/painel, aprovação antes da ativação e RisePay.
5. Executar os oito grupos do roteiro original, incluindo cenários de queda/duplicação e mais de um lote de polling.

Nenhum código de serviço, flag de ambiente, migration, deploy ou chamada financeira foi alterado por este registro. A implementação deve preservar as alterações locais e as correções mais novas de `main`, em especial no Commerce V2.
