# Deploy — cadastro de webhook para venda reembolsada

## Objetivo

Publicar o evento **Venda Reembolsada** na tela de integrações de webhook do `dashboard-seller`.

O seller passa a poder cadastrar e editar endpoints para o evento `sale.refunded`. O mesmo identificador é usado pelo worker de webhooks quando uma venda é confirmada como reembolsada.

Não há migration, alteração de dados ou nova variável de ambiente nesta entrega.

## Componente alterado

| Componente | Branch | Commit |
|---|---|---|
| `dashboard-seller` | `main` | `b9bd57e` |

## Alterações incluídas

- Adicionada a opção **Venda Reembolsada** no formulário de criação e edição de webhooks.
- O endpoint de cadastro aceita `sale.refunded` para criar e atualizar registros em `product_webhooks`.
- O exemplo de payload usa `sale.refunded`, em vez do identificador divergente `sale.refund`.
- A listagem mostra o evento como **Reembolsada**, com identificação visual própria.

## Pré-requisitos

1. Confirmar que o clone de produção não possui alterações locais que possam impedir a atualização da branch `main`.
2. Confirmar que o container `front-dashboard-seller` está saudável antes da atualização.

## Sequência de deploy

1. No diretório de produção do `dashboard-seller`, atualizar a `main`:

   ```bash
   cd /opt/lowify/front/dashboard-seller
   git status --short
   git switch main
   git pull --ff-only origin main
   git log -1 --oneline
   ```

   O último commit deve ser `b9bd57e feat: add refunded webhook event`.

2. Recriar o container web para carregar a revisão atualizada:

   ```bash
   docker compose up -d --build front-dashboard-seller
   ```

3. Confirmar que o container voltou a ficar saudável:

   ```bash
   docker compose ps front-dashboard-seller
   ```

## Validação pós-deploy

1. Acessar **Integrações → Webhooks** com uma conta seller que tenha produto ativo.
2. Confirmar que o seletor de evento oferece **Venda Reembolsada**.
3. Cadastrar um endpoint HTTPS de teste, selecionando pelo menos um produto, e concluir a validação da senha financeira.
4. Confirmar que o webhook aparece na listagem com o status **Reembolsada**.
5. Executar um reembolso aprovado de uma venda de teste vinculada ao produto e confirmar o recebimento de um POST com `event: "sale.refunded"` no endpoint cadastrado.

> A solicitação de reembolso pendente não deve disparar o evento. O disparo ocorre após a aprovação do reembolso.

## Rollback

1. Retornar o `dashboard-seller` para a revisão anterior ao commit `b9bd57e`.
2. Recriar o container:

   ```bash
   docker compose up -d --build front-dashboard-seller
   ```

3. Os registros `product_webhooks` já criados com `event_type = 'sale.refunded'` permanecem no banco; removê-los somente se a reversão também exigir a retirada dessas configurações.
