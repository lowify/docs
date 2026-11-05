# Deploy — rateio de reembolso entre produtor e afiliado

## Objetivo

Publicar o ajuste de reembolso para vendas com afiliado. Quando a venda tiver sido liquidada na carteira Lowify, o reembolso aprovado debita cada participante pela parcela que recebeu; em reembolso parcial, a divisão é proporcional. Para cartão Cielo ou Pagar.me, o estorno é integralmente tratado pelo gateway e não consulta nem grava débitos na carteira Lowify.

Ficam fora do escopo a correção histórica de lançamentos anteriores e a integração UTMify.

## Componentes e referências

| Repositório | Branch de deploy | Commit | Papel |
| --- | --- | --- | --- |
| `services-commerce-v2` | `fix/card-refund-wallet-allocation` | `ce59d2f` | Decide o tratamento de reembolso, publica as operações de carteira quando aplicáveis e ignora carteira em cartão Cielo/Pagar.me. |

Não há alteração em edge, frontend, Banking V2, Wallet, banco ou infraestrutura.

## Alterações incluídas

- O evento de reembolso aprovado calcula a parcela do afiliado a partir de `sales_affiliates.amount` e debita o saldo do afiliado com a operação `sale_affiliate_refunded` (tipo de extrato `18`).
- O produtor recebe a operação `refund_approved` (tipo `12`) somente pelo restante do valor reembolsado; a taxa de reembolso existente continua associada ao produtor.
- As mensagens possuem idempotência por `banking_refund_id`: `refund-approved:<id>` para produtor e `sale-affiliate-refunded:affiliate:<id>:refund:<id>` para afiliado.
- Para cartão Cielo/Pagar.me, a solicitação não verifica disponibilidade da carteira Lowify e a confirmação não publica mensagens para `wallet:extract:events` nem `wallet:extract:affiliate:events`.
- Para vendas com `gateway_split`, não há operação interna de carteira: a reversão pertence ao gateway.

## Pré-requisitos

- A branch `fix/card-refund-wallet-allocation` deve estar publicada no remoto antes da operação.
- O container do Commerce V2 deve possuir a configuração existente de Redis e de assinatura para as filas de extrato.
- Para validar cartão, usar conta e transação de sandbox/homologação da Cielo ou Pagar.me; não usar cartão ou cliente real.
- Registrar o commit atualmente implantado antes da atualização para permitir rollback preciso.

## Banco de dados

Não há migration, DDL ou DML nesta entrega.

## Filas e compatibilidade

O produtor continua publicando em `wallet:extract:events`, consumida pelo processo de extrato padrão do `services-wallet`. O afiliado usa `wallet:extract:affiliate:events`, consumida pelo processo de extrato de afiliados. Os contratos existentes permanecem compatíveis; a mudança está no usuário, valor e identificador de idempotência do lançamento de afiliado.

Para cartão Cielo/Pagar.me, o Commerce V2 não publica nenhuma dessas mensagens após o reembolso confirmado. O Banking V2 continua responsável pela requisição e confirmação junto ao gateway.

## Sequência de deploy

### 1. Atualizar o Commerce V2

```bash
cd /opt/lowify/services/service-commerce-v2
git status --short
git rev-parse --short HEAD
git fetch origin --prune
git switch fix/card-refund-wallet-allocation
git pull --ff-only origin fix/card-refund-wallet-allocation
git rev-parse --short HEAD
docker compose up -d --build service-commerce-v2
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

Antes de trocar a branch, `git status --short` deve estar vazio. O commit final deve ser `ce59d2f` ou descendente aprovado explicitamente. Confirmar que o container iniciou sem erro de Redis, assinatura ou injeção de dependências.

## Testes de compatibilidade em homologação

Executar depois do deploy em homologação, com o `service-commerce-v2` na branch desta entrega e o `services-wallet` saudável. Não limpar filas nem apagar extratos durante o teste.

1. Criar uma venda de teste liquidada na carteira Lowify com afiliado e aguardar a comissão ser liberada.
2. Solicitar um reembolso parcial. Confirmar nos extratos que produtor e afiliado receberam um débito, cuja soma é igual ao valor do produto reembolsado; a taxa de reembolso, se configurada, aparece apenas para o produtor.
3. Repetir com reembolso total em outra venda de teste e confirmar a mesma separação.
4. Reenviar a mesma confirmação de reembolso. Não pode surgir um segundo lançamento para produtor nem afiliado.
5. Criar uma venda de cartão Cielo/Pagar.me com split e afiliado, solicitar o reembolso no sandbox e confirmar que o gateway reverte os recebedores. Os extratos Lowify do produtor e afiliado não devem receber lançamento desse reembolso.

## Validação pós-deploy

1. Abra uma venda de teste com afiliado que foi reembolsada pela carteira Lowify. O produtor deve ver somente a parte dele debitada e o afiliado deve ver somente a comissão dele debitada.
2. Abra uma venda de cartão Cielo/Pagar.me reembolsada. Nenhum dos dois deve ver um novo débito na carteira Lowify; a reversão deve aparecer na conta do gateway.
3. Se algum valor estiver duplicado, diferente da parcela recebida ou ausente, interrompa novos testes e preserve os IDs da venda e do reembolso para conciliação. Não faça ajustes manuais de saldo.

Como conferência técnica opcional, verificar os logs do Commerce V2 e dos consumidores de extrato pelos IDs da venda e do reembolso. Não é necessário interpretar filas para concluir a validação visual.

## Rollback

1. Registrar o commit ativo antes do passo de atualização.
2. No `service-commerce-v2`, retornar à referência previamente registrada e reconstruir somente esse container.
3. Não apagar mensagens Redis, extratos, `sales_refund` ou registros de gateway. O rollback restaura o código; quaisquer efeitos financeiros já processados exigem conciliação manual.

## Riscos e pendências

- O serviço de Wallet usa idempotência em Redis para impedir reentrega durante sua janela configurada. Não há nova restrição de unicidade de banco nesta entrega.
- A correção não altera lançamentos emitidos antes da publicação. Qualquer estorno histórico deve ser analisado e regularizado separadamente.
