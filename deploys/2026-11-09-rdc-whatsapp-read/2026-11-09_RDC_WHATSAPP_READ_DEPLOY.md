# Deploy — RDC por mensagem WhatsApp lida

## Objetivo

No Commerce V2, marcar `rdc = 1` quando a Meta confirmar que uma mensagem de
recuperação de venda foi lida. Isso é sinal de leitura, não de clique, cópia do
Pix ou pagamento.

A atualização é atômica e só ocorre enquanto a venda estiver `pending`; uma
leitura tardia não altera venda paga, cancelada ou expirada.

## Componente publicado

| Repositório | Diretório de produção | Branch | Commit mínimo |
| --- | --- | --- | --- |
| `service-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/rdc-whatsapp-read` | `d7cad57` |

`services-notifications` e `edge-webhook` não recebem código. Eles já devem
estar operacionais no fluxo existente `Meta -> Edge -> Notification -> Commerce`.

Não há DDL, migration, env, template Meta, fila ou mudança financeira.

## Pré-checagem

Não usar `reset`, `clean`, `stash` ou checkout forçado. Não limpar filas,
Redis, vendas, dispatches ou eventos. Se já houver outcomes `read` pendentes,
registrar a decisão operacional antes do deploy: eles podem ser consumidos pela
regra nova.

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
git merge-base --is-ancestor d7cad57 HEAD
git rev-parse --short HEAD
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

Prosseguir somente se o commit mínimo estiver presente, o serviço estiver `Up`
e não houver erro de inicialização, Redis ou fila.

## Validação pós-deploy

Usar venda Pix e destinatário piloto autorizados; não registrar telefone,
código Pix, payload Meta ou segredos.

1. Deixar o fluxo normal enviar uma recuperação WhatsApp para uma venda
   `pending`. Não clonar `whatsapp_meta`, injetar fila nem editar `rdc` por SQL.
2. Abrir a mensagem no dispositivo autorizado e aguardar o webhook oficial
   `read` da Meta.
3. Conferir que a venda continua `pending`, passa a `rdc = 1` e há um único
   evento `read` no dispatch:

   ```sql
   SELECT sale_id, status, rdc FROM sales WHERE sale_id = :sale_id;
   SELECT event_type, provider_reference_type, provider_reference_id, occurred_at
   FROM sale_recovery_dispatch_events
   WHERE sale_recovery_dispatch_id = :dispatch_id
   ORDER BY id;
   ```

4. Repetir o callback somente pelo mecanismo aprovado de homologação e
   confirmar que não há novo evento. Para uma venda já paga, confirmar que uma
   leitura tardia não modifica `rdc`.

## Rollback

Publicar a revisão de rollback previamente aprovada do Commerce V2 com a mesma
pré-checagem e `git pull --ff-only`, depois reconstruir/recriar apenas esse
serviço. Não reverter dados, Notification, Edge, Meta, Redis ou filas.

## Referências

- [Feature — comunicações de venda](../../features/sale-notifications/README.md)
- [Fase 5 — Commerce: tentativas, RDC e dispatch](../../plans/sale-notifications/05_COMMERCE_DISPATCH_TASKS.md)
- [Fase 6 — Notification: envio, callbacks e alertas](../../plans/sale-notifications/06_NOTIFICATION_CALLBACKS_TASKS.md)
