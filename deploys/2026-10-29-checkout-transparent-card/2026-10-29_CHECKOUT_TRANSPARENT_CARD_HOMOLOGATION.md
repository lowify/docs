# Homologação — Checkout Transparente: cartão

## Objetivo

Publicar em homologação o Checkout Transparente com cartão e confirmar que os componentes da feature constroem e iniciam sem erro. A VPS de homologação deve usar a branch `feat/checkout-transparent-card` somente nos participantes abaixo; todos os outros targets operáveis devem ficar em `main`.

Não aplicar migrations, não habilitar `card_credit` para sellers e não realizar cobrança real nesta operação. A validação cobre Git, build, inicialização e saúde dos containers. A homologação funcional com contas de teste e credenciais válidas será uma etapa posterior.

## VPS e modo de rebuild

- VPS: `root@217.216.87.77`
- Modo de rebuild: incremental. Reconstruir somente edges e serviços cuja branch ou commit mudar. Todo target `front/*` recebe apenas `git pull`; não executar Docker Compose nem rebuild nos fronts.
- Targets mantidos como estão: `checkout-transparent-infra` e `data_layer`, pois são infraestrutura, banco e Redis.
- Targets ausentes da VPS e repositórios sem mapeamento oficial não fazem parte desta operação.

## Matriz de targets

| Chave no mapa | Caminho na VPS | Branch desejada | Papel |
| --- | --- | --- | --- |
| `checkout-transparent-api` | `/root/opt/lowify-ct/services-checkout-transparent-api` | `feat/checkout-transparent-card` | API de charge, tentativa, idempotência, migrações e confirmação. |
| `checkout-transparent-worker` | `/root/opt/lowify-ct/services-checkout-transparent-worker` | `feat/checkout-transparent-card` | Consumidor e clientes de gateway. |
| `ct-webhook` | `/root/opt/lowify-ct-webhook/edge-checkout-transparent-webhook` | `feat/checkout-transparent-card` | Webhook de provedores CT. |
| `services-commerce-v2` | `/root/opt/lowify/services/service-commerce-v2` | `feat/checkout-transparent-card` | Venda pendente e confirmação CT. |
| `edge-webhook` | `/root/opt/lowify/edge/edge-webhook` | `feat/checkout-transparent-card` | Confirmação CT para Commerce. |
| `edge-public-api` | `/root/opt/lowify/edge/edge-public-api` | `feat/checkout-transparent-card` | Contrato público CT. |
| `edge-gateway` | `/root/opt/lowify/edge/edge-gateway` | `feat/checkout-transparent-card` | Roteamento CT. |
| `front-checkout` | `/root/opt/lowify/front/front-checkout` | `feat/checkout-transparent-card` | Tokenização e checkout. |
| `dashboard-seller` | `/root/opt/lowify/front/dashboard-seller` | `feat/checkout-transparent-card` | Configuração e relatório de integração. |
| `front-chat` | `/root/opt/lowify/front/front-chat` | `main` | Não participante. |
| `front-idv` | `/root/opt/lowify/front/front-idv` | `main` | Não participante. |
| `front-member-area` | `/root/opt/lowify/front/front-member-area` | `main` | Não participante. |
| `services-account` | `/root/opt/lowify/services/services-account` | `main` | Não participante. |
| `services-auth` | `/root/opt/lowify/services/services-auth` | `main` | Não participante. |
| `services-banking` | `/root/opt/lowify/services/services-banking` | `main` | Não participante. |
| `services-banking-v2` | `/root/opt/lowify/services/services-banking-v2` | `main` | Não participante; preserva cartão/recorrência convencional. |
| `services-commerce` | `/root/opt/lowify/services/services-commerce` | `main` | Não participante. |
| `services-notification` | `/root/opt/lowify/services/services-notifications` | `main` | Não participante. |
| `services-platform` | `/root/opt/lowify/services/services-platform` | `main` | Não participante. |
| `services-wallet` | `/root/opt/lowify/services/services-wallet` | `main` | Não participante. |
| `checkout-transparent-billing` | `/root/opt/lowify-ct/services-checkout-transparent-billing` | `main` | Não participante. |

Não executar comandos nos targets `checkout-transparent-infra` e `data_layer`. Não criar nem atualizar os itens de `absent_from_vps` ou `unmapped_vps_repositories` do mapa de homologação.

## Pré-checagem obrigatória

Antes de qualquer `fetch`, `switch`, `pull` ou Docker, verificar todos os targets da tabela:

```bash
git status --porcelain=v1
git branch --show-current
git remote get-url origin
```

Se qualquer target tiver alteração rastreada ou não rastreada, origem ausente/incorreta ou não for repositório Git, parar toda a operação. Não usar stash, reset, limpeza, commit ou troca de branch para contornar o estado encontrado.

Depois de todos limpos, executar `git fetch origin --prune` em todos e confirmar a existência de `origin/feat/checkout-transparent-card` nos nove participantes e de `origin/main` nos demais.

## Sequência de integração

1. Atualizar os participantes na ordem: `checkout-transparent-worker`, `checkout-transparent-api`, `services-commerce-v2`, `ct-webhook`, `edge-webhook`, `edge-public-api`, `edge-gateway`, `front-checkout`, `dashboard-seller`.
2. Atualizar cada participante com `git switch feat/checkout-transparent-card` e `git pull --ff-only origin feat/checkout-transparent-card`.
3. Atualizar cada target não participante da tabela com `git switch main` e `git pull --ff-only origin main`.
4. Registrar branch e commit antes/depois de cada target. Se a branch ou o commit mudar, executar `docker compose up --build -d` somente nos edges e serviços. Para `dashboard-seller`, `front-chat`, `front-checkout`, `front-idv` e `front-member-area`, a atualização termina no `git pull --ff-only`; não executar Compose.
5. Após cada rebuild, conferir `docker compose ps`. Se a atualização ou o container falhar, parar a sequência; não fazer rollback automático e não atualizar targets restantes.

## Validação de build e saúde

1. Para cada target que mudou, o `docker compose up --build -d` deve concluir sem falha e `docker compose ps` deve indicar os serviços esperados em execução/saudáveis.
2. Para CT API, CT Worker e CT Webhook, conferir os logs recentes sem imprimir segredos: `docker compose logs --tail=100`.
3. No CT API, confirmar que o processo `stale_card_attempt_expiration` iniciou sem erro. Não rodar migration, backfill nem o comando de expiração nesta homologação.
4. Não executar checkout financeiro, tokenização, consumo/manualização de fila, limpeza de Redis ou chamada de webhook real enquanto não houver credenciais de homologação e roteiro funcional aprovado.

## Rollback

Se um build ou inicialização falhar, parar no primeiro alvo com problema e registrar branch, commit e saída. Para uma reversão autorizada posterior, retornar primeiro as interfaces e edges, depois CT API/worker e Commerce V2, preservando filas, banco, Redis e todas as alterações de infraestrutura.

## Referências

- `deploys/2026-10-29-checkout-transparent-card/2026-10-29_CHECKOUT_TRANSPARENT_CARD_DEPLOY.md`
- `.agents/integration/homologation-map.yaml`
