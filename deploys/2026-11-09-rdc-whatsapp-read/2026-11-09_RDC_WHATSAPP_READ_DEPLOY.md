# Deploy — RDC por mensagem WhatsApp lida

## Objetivo

Marcar `rdc = 1` quando a Meta confirmar leitura de recuperação WhatsApp. O
webhook marca somente vendas `pending`; o comando cobre leituras históricas,
inclusive as recebidas depois do pagamento.

## Componente publicado

| Repositório | Diretório de produção | Branch | Revisão |
| --- | --- | --- | --- |
| `service-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/rdc-whatsapp-read` | A definir — comando ainda sem commit/push |

Não há DDL, env, migration ou alteração em Notification e Edge.

## Pré-checagem

Não usar `reset`, `clean`, `stash` ou checkout forçado.

```bash
cd /opt/lowify/services/service-commerce-v2
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/rdc-whatsapp-read
docker compose config --quiet
```

## Deploy

```bash
cd /opt/lowify/services/service-commerce-v2
git switch feat/rdc-whatsapp-read
git pull --ff-only origin feat/rdc-whatsapp-read
# substituir pelo SHA aprovado que incluir o comando
git merge-base --is-ancestor <sha-aprovado> HEAD
git rev-parse --short HEAD
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

Prosseguir se o serviço estiver `Up` e sem erro de inicialização.

## Reconciliação histórica

Data obrigatória em `America/Sao_Paulo`. O comando executa a marcação.

```bash
cd /opt/lowify/services/service-commerce-v2
docker compose exec -T service-commerce-v2 \
  php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads \
  --date=YYYY-MM-DD
```

Ele marca somente vendas com `rdc = 0` que tenham evento WhatsApp `read` de
recuperação a partir da data.

## Validação pós-deploy

Confirmar uma leitura normal em venda `pending` e uma venda paga com `read`
posterior processada pelo comando.

## Rollback

Publicar a revisão de rollback previamente aprovada do Commerce V2 com a mesma
pré-checagem e `git pull --ff-only`, depois reconstruir/recriar apenas esse
serviço. Não reverter dados, Notification, Edge, Meta, Redis ou filas.

## Referências

- [Feature — comunicações de venda](../../features/sale-notifications/README.md)
- [Fase 5 — Commerce: tentativas, RDC e dispatch](../../plans/sale-notifications/05_COMMERCE_DISPATCH_TASKS.md)
- [Fase 6 — Notification: envio, callbacks e alertas](../../plans/sale-notifications/06_NOTIFICATION_CALLBACKS_TASKS.md)
