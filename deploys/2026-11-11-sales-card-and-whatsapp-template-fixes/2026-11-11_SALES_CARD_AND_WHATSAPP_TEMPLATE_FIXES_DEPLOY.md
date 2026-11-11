# Deploy — filtro Cartão e salvamento de template WhatsApp

## Objetivo

Publicar duas correções independentes:

- **Vendas:** o filtro **Cartão** passa `card`, valor usado pelas vendas; a
  compatibilidade com a URL antiga `gateway=cartao` permanece.
- **WhatsApp Meta:** o Notifications associa o código do cenário da rota ao
  parâmetro do controller e volta a salvar os vínculos de template.

Não há DDL, migration, env, alteração de dados ou ação manual em filas.

## Componentes publicados

| Repositório | Diretório de produção | Branch | Commit mínimo |
| --- | --- | --- | --- |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `fix/quick-fixes-2026-11-09` | `867b7d7b` |
| `services-notifications` | `/opt/lowify/services/services-notifications` | `fix/quick-fixes-2026-11-09` | `0dabab3` |

O Dashboard usa bind mount em `/var/www/html`; não requer build nem restart.
O Notifications precisa ser reconstruído e recriado.

O Dashboard possui mudança posterior nesta mesma branch, documentada
separadamente para RisePay. Não usar este roteiro para autorizar essa mudança:
publique a ponta da branch somente se o pacote completo estiver aprovado.

## Pré-checagem

Não usar `reset`, `clean`, `stash` ou checkout forçado. Se houver alteração
local, remoto inesperado ou branch ausente, interromper e preservar o estado.

```bash
cd /opt/lowify/front/dashboard-seller
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/fix/quick-fixes-2026-11-09
docker compose config | grep -F '/var/www/html'

cd /opt/lowify/services/services-notifications
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/fix/quick-fixes-2026-11-09
docker compose config --quiet
```

## Deploy

### 1. Notifications

```bash
cd /opt/lowify/services/services-notifications
git switch fix/quick-fixes-2026-11-09
git pull --ff-only origin fix/quick-fixes-2026-11-09
git merge-base --is-ancestor 0dabab3 HEAD
git rev-parse --short HEAD
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 services-notifications
```

Prosseguir somente se `0dabab3` estiver presente, o serviço estiver `Up` e os
logs não tiverem erro de inicialização, rota ou conexão.

### 2. Dashboard Seller

```bash
cd /opt/lowify/front/dashboard-seller
git switch fix/quick-fixes-2026-11-09
git pull --ff-only origin fix/quick-fixes-2026-11-09
git merge-base --is-ancestor 867b7d7b HEAD
git rev-parse --short HEAD
docker compose ps
```

Prosseguir somente se `867b7d7b` estiver presente e os containers que já
estavam ativos continuarem `Up`. Não reiniciar containers nem processar filas.

## Validação pós-deploy

1. No Dashboard, abrir **Vendas**, selecionar um período que contenha uma
   venda de cartão conhecida, escolher **Cartão** e filtrar. A venda deve
   aparecer. Repetir pela URL antiga com `gateway=cartao`, se houver link
   salvo, e confirmar o mesmo resultado.
2. Como administrador, abrir **Configurações do sistema > WhatsApp Meta**,
   alterar um template principal ou reserva de recuperação, clicar em
   **Salvar** e recarregar a página. A seleção deve permanecer; não deve
   aparecer a mensagem `1` nem erro de resposta inválida.

## Rollback

Publicar revisões de rollback previamente aprovadas dos dois repositórios,
reconstruindo e recriando somente `services-notifications`. Não reverter dados,
templates, Redis ou filas: esta entrega não os altera.

## Referências

- [Deploy de templates WhatsApp](../2026-11-03-sale-recovery-whatsapp-templates/2026-11-03_SALE_RECOVERY_WHATSAPP_TEMPLATES_DEPLOY.md)
- [Deploy de remoção da RisePay](../2026-11-11-remove-risepay-checkout-transparent/2026-11-11_REMOVE_RISEPAY_CHECKOUT_TRANSPARENT_DEPLOY.md)
