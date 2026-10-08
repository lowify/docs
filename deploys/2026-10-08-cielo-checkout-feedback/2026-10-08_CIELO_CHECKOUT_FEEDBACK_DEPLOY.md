# Deploy — Retorno de erro Cielo no Checkout e taxa fixa do cartão

## Objetivo

Exibir no Checkout uma mensagem segura e acionável quando um pagamento de cartão Cielo for recusado ou falhar. O retorno técnico integral da Cielo continua registrado internamente; o comprador recebe somente um código estável e uma mensagem mapeada.

Também ajustar a taxa de cartão para somar a taxa fixa do seller (`taxa_seller`) à taxa percentual/MDR. A alteração preserva o fluxo de Pix.

## Componentes e referências

| Repositório | Diretório na VPS | Branch de deploy | Entrega |
| --- | --- | --- | --- |
| `services-banking-v2` | `/opt/lowify/services/services-banking-v2` | `fix/cielo-integration` | Mapeia a falha Cielo, grava log ordinário e devolve referência segura para o Checkout. |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `fix/cielo-integration` | Propaga a referência segura e soma taxa fixa do seller ao MDR do cartão. |
| `front-checkout` | `/opt/lowify/front/front-checkout` | `fix/cielo-integration` | Exibe a mensagem segura devolvida pelo Checkout. |

O `edge-gateway` não recebe alteração: o envelope de resposta já preserva o campo `meta` entre Commerce e Checkout.

## Alterações relevantes

1. Cartão Cielo recusado/falho retorna uma mensagem própria para situações como saldo insuficiente, cartão vencido, senha inválida, cartão restrito ou indisponibilidade temporária. Casos sem código detalhado recebem uma mensagem genérica segura.
2. O retorno bruto da Cielo permanece em `charge_card_events`; falhas também registram um `ordinary_log` do tipo `cielo_payment_failure`, sem expor esses dados ao comprador.
3. A referência percorre Banking → Commerce → Checkout em `meta.reference`. Pix e outros adquirentes não passam pelo novo mapeamento de mensagens Cielo.
4. Para cartão, a tarifa de plataforma passa a ser `taxa_seller + percentual/MDR`. No split Cielo, os valores continuam enviados separadamente como taxa fixa e MDR.

## Pré-requisitos

1. Publicar as alterações da branch `fix/cielo-integration` no repositório remoto antes de iniciar o deploy.
2. Confirmar que as árvores de trabalho da VPS estão limpas. Não sobrescrever alterações locais.
3. Manter as configurações Cielo existentes. Não há variável de ambiente nova.
4. A tabela `ordinary_logs` já deve existir, como nas instalações atuais do Banking V2.

## Banco de dados

Não há migration nem DDL neste deploy. Os novos registros usam a tabela existente `ordinary_logs`; eventos brutos continuam na tabela já existente `charge_card_events`.

## Sequência de deploy

Publicar nesta ordem: Banking, Commerce e Checkout. Assim, o produtor da nova referência segura entra antes dos consumidores.

1. Publicar `services-banking-v2`.

   Atualizar a revisão:

   ```bash
   cd /opt/lowify/services/services-banking-v2
   git status --porcelain=v1
   git fetch origin --prune
   git switch fix/cielo-integration
   git pull --ff-only origin fix/cielo-integration
   git rev-parse --short HEAD
   ```

   Construir e iniciar o serviço:

   ```bash
   docker compose build
   docker compose up -d
   docker compose ps
   docker compose logs --tail=100
   ```

2. Publicar `services-commerce-v2`.

   Atualizar a revisão:

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git status --porcelain=v1
   git fetch origin --prune
   git switch fix/cielo-integration
   git pull --ff-only origin fix/cielo-integration
   git rev-parse --short HEAD
   ```

   Construir e iniciar o serviço:

   ```bash
   docker compose build
   docker compose up -d
   docker compose ps
   docker compose logs --tail=100
   ```

3. Publicar `front-checkout`:

   ```bash
   cd /opt/lowify/front/front-checkout
   git status --porcelain=v1
   git fetch origin --prune
   git switch fix/cielo-integration
   git pull --ff-only origin fix/cielo-integration
   git rev-parse --short HEAD
   ```

## Validação pós-deploy

1. Em ambiente de teste ou com uma cobrança controlada, provocar uma recusa Cielo conhecida, como saldo insuficiente. O Checkout deve mostrar mensagem compreensível ao comprador, sem `ReturnCode`, `ReturnMessage`, credenciais ou resposta bruta da adquirente.
2. Fazer uma compra aprovada por cartão Cielo e confirmar a conclusão normal da venda, captura e split.
3. Em uma cobrança de cartão de R$ 100,00 com `taxa_seller` de R$ 0,99 e MDR de 8%, conferir no split/registro financeiro que a taxa de plataforma é R$ 8,99 (R$ 0,99 + R$ 8,00).
4. Gerar um Pix de teste e concluir o fluxo usual, confirmando que não houve alteração no comportamento de Pix.
5. Para uma falha Cielo, conferir internamente que existe evento em `charge_card_events` e um `ordinary_log` `cielo_payment_failure` associado à charge. Esses dados são apenas operacionais e não devem ser exibidos ao comprador.

## Rollback

1. Se necessário, retornar os componentes na ordem inversa: `front-checkout`, `services-commerce-v2` e `services-banking-v2`. Reconstruir os containers somente dos dois serviços após mudar a revisão.
2. Não executar alterações no banco: não há migration a desfazer.
3. Preservar `ordinary_logs`, `charge_card_events`, cobranças e vendas já registradas. O rollback não altera a taxa registrada em transações criadas enquanto esta versão esteve ativa.
4. Antes de reabrir o Checkout, verificar cobranças de cartão pendentes ou em processamento para evitar duplicação de tentativas.

## Referências

- `services-banking-v2/app/Application/Service/CieloEcommerce/CieloEcommerceCheckoutErrorMapper.php`
- `services-banking-v2/app/Application/UseCase/CieloEcommerce/ChargeCard/CreateChargeCardUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `front-checkout/views/checkout/form/index.php`
- [Cielo — códigos de status e HTTP](https://docs.cielo.com.br/ecommerce-cielo/reference/introapi-codes-status-http)
