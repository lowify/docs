# Deploy — Correção do método de pagamento de cartão na UTMify

## Objetivo

Publicar a conversão do método interno `card` para `credit_card` na integração de vendas com a UTMify. A API externa aceita `credit_card`; antes deste ajuste, vendas de cartão podiam ser enviadas com o valor não suportado `card`.

O escopo limita-se ao payload externo enviado pelo `services-sale-integrations`. Não há alteração no checkout, Commerce V2, banco de dados, Redis, filas, tokens ou rotas públicas.

## Componentes e referências

| Componente | Host de produção | Repositório | Branch de deploy | Commit |
| --- | --- | --- | --- | --- |
| Integrações de venda | `147.93.180.183` | `services-sale-integrations` | `master` | `86d664c` |

O repositório usa `master` como branch principal; não há branch `main`. Nenhum outro componente faz parte deste deploy.

## Alterações incluídas

- O `UtmifySender` converte `card` para `credit_card` antes de criar o campo `paymentMethod` da requisição HTTP para a UTMify.
- Mantém o mapeamento existente de `pix_automatic` para `pix`.
- Inclui teste de integração do sender para uma venda interna com `payment_method: card` e payload externo com `paymentMethod: credit_card`.

Fluxo afetado:

```text
services-commerce-v2 grava payment_method=card
-> evento em sales:integration:utmify
-> services-sale-integrations / UtmifySender
-> paymentMethod=credit_card
-> API UTMify
```

## Pré-requisitos

1. Confirmar que o commit `86d664c` está disponível em `origin/master`.
2. Confirmar que a árvore Git do serviço na VPS `147.93.180.183` está limpa e que `origin` aponta para o repositório oficial.
3. Registrar o commit atualmente em produção para eventual rollback.
4. Preservar os valores existentes de `SALE_INTEGRATIONS_UTMIFY_*`, especialmente endpoint e token. Não imprimir nem alterar segredos.

## Banco de dados

Não há migration, DDL, DML ou alteração de schema.

## Sequência de deploy

Modo de rebuild: incremental.

1. Acessar a VPS de produção `147.93.180.183` e abrir o diretório do serviço:

   ```bash
   cd /opt/lowify/services/services-sale-integrations
   git status --short
   git fetch origin --prune
   git switch master
   git pull --ff-only origin master
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   ```

2. Confirmar que o commit exibido é `86d664c` (ou um descendente aprovado) e que o processo `sale_integrations_utmify` está ativo.

3. Não consumir, apagar, reordenar ou reenfileirar mensagens de `sales:integration:utmify` durante o deploy.

## Validação pós-deploy

1. No checkout de teste, faça uma compra de cartão usando um produto com integração UTMify configurada.
   - Resultado esperado: a compra é concluída normalmente e a venda aparece no painel da UTMify como cartão de crédito.
2. Abra a venda correspondente no painel da UTMify.
   - Resultado esperado: o método de pagamento é exibido como cartão de crédito; não há erro de validação do método.
3. Faça uma compra Pix de teste na mesma configuração.
   - Resultado esperado: a venda Pix continua chegando normalmente, sem regressão.
4. Como conferência técnica opcional, verificar os logs do serviço após as compras.
   - Resultado esperado: não há resposta HTTP de erro atribuída a `paymentMethod`.
5. Se a venda não aparecer, registrar horário, `order_id` e resposta da UTMify; não apagar nem reenfileirar mensagens para forçar nova tentativa.

## Rollback

1. Na VPS `147.93.180.183`, retornar `services-sale-integrations` ao commit anterior registrado no pré-requisito e reconstruir o container:

   ```bash
   cd /opt/lowify/services/services-sale-integrations
   git fetch origin --prune
   git switch master
   git checkout <commit-anterior-aprovado>
   docker compose up -d --build
   docker compose ps
   ```

2. O rollback restaura somente a serialização de novos payloads. Não altera vendas já enviadas, logs, configurações, banco de dados ou mensagens já presentes em filas.

## Fora de escopo

- Alteração do valor interno `payment_method` persistido pelo Commerce V2.
- Reenvio de vendas históricas.
- Alteração de credenciais, endpoint UTMify, Redis, banco de dados ou infraestrutura da VPS.
