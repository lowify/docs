# Homologação — Referência externa da venda

## Objetivo

Preparar a VPS de homologação para a feature `external_reference`, atualizando somente Checkout, Commerce V2 e Dashboard Seller para a branch `feat/external-reference-seller-refund`.

Esta operação prepara repositórios e containers; não executa a migration de banco, não realiza compra de teste e não publica em produção.

## Participantes

| Chave do mapa | Repositório | Branch |
| --- | --- | --- |
| `front-checkout` | `front-checkout` | `feat/external-reference-seller-refund` |
| `services-commerce-v2` | `services-commerce-v2` | `feat/external-reference-seller-refund` |
| `dashboard-seller` | `dashboard-seller` | `feat/external-reference-seller-refund` |

Modo de rebuild: incremental.

## Targets mantidos como estão

Todos os demais targets operáveis do `homologation-map.yaml` são explicitamente mantidos como estão, conforme solicitado. Não recebem pré-checagem, Git ou Docker nesta operação. `data_layer` e `checkout-transparent-infra` permanecem protegidos por `default_action: hold`.

`services-sale-integrations` está listado como ausente da VPS no mapa oficial. Portanto, não participa desta homologação e o envio do campo no consumer de webhook não será validado neste ambiente.

## Alterações incluídas

- Checkout recebe `external_reference` por GET, valida-o, inclui-o no formulário e o preserva ao redirecionar URLs com `offer`.
- Commerce V2 valida e persiste o campo em `sales.external_reference`; vendas de upsell herdam o valor da venda original.
- Dashboard Seller exibe o campo no detalhe da venda para seller e administração, quando preenchido.

## Banco de dados

Nenhum ajuste de banco será aplicado nesta etapa. Antes de testar uma compra em homologação, será necessário aplicar manualmente o DDL aditivo da feature em `lowify.sales`; `data_layer` não receberá comandos agora.

## Sequência de homologação

1. Na VPS `root@217.216.87.77`, pré-checar somente os três participantes com `git status --porcelain=v1`, `git branch --show-current` e `git remote get-url origin`. Se qualquer um tiver alteração local ou origem inesperada, interromper toda a operação.
2. Executar `git fetch origin --prune` nos três participantes e confirmar que `origin/feat/external-reference-seller-refund` existe antes de trocar qualquer branch.
3. Atualizar e reconstruir Commerce V2, se a branch ou commit mudarem:

   ```bash
   cd /root/opt/lowify/services/service-commerce-v2
   git switch feat/external-reference-seller-refund
   git pull --ff-only origin feat/external-reference-seller-refund
   docker compose up --build -d
   ```

4. Atualizar e reconstruir Checkout, se a branch ou commit mudarem:

   ```bash
   cd /root/opt/lowify/front/front-checkout
   git switch feat/external-reference-seller-refund
   git pull --ff-only origin feat/external-reference-seller-refund
   docker compose up --build -d
   ```

5. Atualizar e reconstruir Dashboard Seller, se a branch ou commit mudarem:

   ```bash
   cd /root/opt/lowify/front/dashboard-seller
   git switch feat/external-reference-seller-refund
   git pull --ff-only origin feat/external-reference-seller-refund
   docker compose up --build -d
   ```

## Validação posterior

Esta solicitação não inclui testes. Antes de testar a feature, aplicar o banco, criar uma compra de teste com `external_reference`, concluir um upsell e conferir o detalhe seller/administrativo. O webhook de Integrações fica fora desta homologação porque o serviço não está presente na VPS mapeada.

## Rollback

Caso a preparação precise ser revertida, retornar apenas os três participantes à branch e commit anteriores registrados na pré-checagem e reconstruir somente o container cuja revisão for alterada. Não tocar em banco, Redis, filas ou targets mantidos como estão.
