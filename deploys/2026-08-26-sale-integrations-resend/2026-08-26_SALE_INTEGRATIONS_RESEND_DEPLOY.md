# Deploy — reenvio seletivo de integrações da venda

## Objetivo

Publicar a consulta e o reenvio manual das integrações vinculadas à venda atual, disponíveis em `sale_detail.php` e `admin_sale_detail.php`.

O operador pode selecionar uma ou mais integrações no modal. O backend valida a seleção contra as integrações elegíveis para o status atual da venda e publica somente as plataformas escolhidas.

```text
dashboard-seller
  -> edge-gateway
  -> edge-public-api
  -> services-commerce-v2
  -> Redis (fila específica da integração)
```

O reenvio aceita vendas nos estados `pending`, `paid` e `refunded`. Há uma trava Redis por venda de 3 minutos; durante esse período a resposta é HTTP 429, apresentada ao usuário como `Aguarde alguns instantes e tente novamente.`

## Containers alterados

| Container | Branch |
|---|---|
| `services-commerce-v2` | `feat/sale-integrations-resend` |
| `edge-public-api` | `feat/sale-integrations-resend` |
| `edge-gateway` | `feat/sale-integrations-resend` |
| `dashboard-seller` | `feat/sale-integrations-resend` |

Não há migration nesta entrega.

## Pré-requisitos

1. Confirmar que `USE_SALE_EVENTS_ONLY` está configurado como `true` no `services-commerce-v2`:

   - Com essa configuração, Webhook e Utmify também podem ser retornados quando configurados e compatíveis com o evento.

## Sequência de deploy

1. Publicar `services-commerce-v2` na branch `feat/sale-integrations-resend`.
2. No diretório do commerce-v2, atualizar o código e recriar o container:

   ```bash
   git pull --ff-only
   docker compose up -d --build
   ```

3. Confirmar que o serviço iniciou e está escutando normalmente:

   ```bash
   docker compose ps
   docker compose logs --tail=200 service-commerce-v2
   ```

4. Publicar `edge-public-api` na mesma branch. Ele extrai o usuário/permissão do JWT e encaminha a seleção de integrações ao commerce-v2.
5. Atualizar e recriar o public API:

   ```bash
   git pull --ff-only
   docker compose up -d --build
   ```

6. Publicar `edge-gateway` na mesma branch. Ele expõe as rotas:

   ```text
   GET  /sales/{saleId}/integrations/overview
   POST /sales/{saleId}/integrations/resend
   ```

7. Atualizar e recriar o gateway:

   ```bash
   git pull --ff-only
   docker compose up -d --build
   ```

8. Publicar `dashboard-seller` na mesma branch e atualizar o container:

   ```bash
   git pull --ff-only
   docker compose up -d --build
   ```

   Se o dashboard usar o diretório do projeto montado como volume, o `git pull` já atualiza o código em execução; manter o build/restart para também atualizar os workers e evitar divergência entre processos.

## Validação pós-deploy

1. Abrir uma venda elegível no seller ou no admin. O overview é carregado no PHP no início da página, antes do HTML, para permitir renovação do cookie JWT do Gateway.
2. Confirmar que o botão **Reenviar integrações** aparece na `Linha do Tempo`, ao lado de **Reembolsar**, somente quando há integrações elegíveis.
3. Abrir o modal e conferir os `SettingToggle` das integrações. Todas iniciam selecionadas; desmarcar uma e reenviar apenas outra.
4. Confirmar que o toast informa apenas as integrações selecionadas e publicadas.
5. Tentar reenviar novamente a mesma venda logo após o primeiro envio. A resposta deve ser HTTP 429 e o toast deve exibir:

   ```text
   Aguarde alguns instantes e tente novamente.
   ```

6. Em `admin_sale_detail`, confirmar o painel **Diagnóstico do reenvio de integrações**. Ele mostra a resposta sanitizada do overview e também grava uma entrada no log PHP com a tag:

   ```text
   [admin_sale_detail][sale_integrations_overview]
   ```

7. Conferir, sem consumir mensagens, as filas Redis correspondentes às plataformas selecionadas. Exemplos de chaves:

   ```text
   sales:integration:appsell
   sales:integration:spedy
   sales:integration:webhook
   sales:integration:utmify
   sales:integration:huskyapp:v2
   sales:integration:lowtrack
   ```

   O tamanho da fila escolhida deve aumentar após o reenvio. A consulta deve usar a autenticação Redis configurada no ambiente, sem expor o segredo:

   ```bash
   redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --user default --askpass LLEN sales:integration:appsell
   ```

## Regras de autorização e seleção

- Permissões `1`, `2` e `4` são tratadas como admin para a consulta.
- Seller não-admin só pode consultar/re-enviar integração de venda cujo `id_usuario` seja o mesmo do JWT.
- O dashboard envia os nomes selecionados; o `services-commerce-v2` converte os nomes para plataformas internas e recusa itens não elegíveis com HTTP 422.
- Nenhuma integração selecionada resulta em erro de validação; o botão de confirmação do modal permanece desabilitado enquanto não houver seleção.

## Rollback

1. Se o dashboard apresentar erro visual, retornar somente `dashboard-seller` ao commit/branch anterior e recriar o container. Isso remove o botão, sem afetar o processamento normal de eventos de venda.
2. Se houver falha no encaminhamento, retornar `edge-public-api` e `edge-gateway` juntos à versão anterior.
3. Se houver falha na publicação das filas, retornar `services-commerce-v2` à versão anterior. Não limpar as filas Redis como ação de rollback; mensagens já enfileiradas devem ser analisadas e tratadas conforme o processo operacional da integração.
4. Não usar `git reset --hard`, `push --force` ou exclusão de chaves Redis como procedimento de rollback.
