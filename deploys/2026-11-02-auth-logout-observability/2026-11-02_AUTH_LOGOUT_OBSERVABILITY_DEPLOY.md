# Deploy — Observabilidade de logout e refresh JWT

## Objetivo

Publicar um histórico de diagnóstico, no Redis, para encerramentos de sessão associados ao Dashboard Seller e ao ciclo de refresh JWT no Public API. Os registros permitem correlacionar o seller, a origem, o motivo e o caminho da requisição sem armazenar access token, refresh token, cookie, senha, IP ou payload de autenticação.

Fora do escopo: alterar a política de expiração, revogar tokens existentes, encerrar sessões ativas, criar uma tela de consulta no Dashboard ou modificar o `services-auth`.

## Componentes e referências

| Repositório | Host | Diretório de produção | Branch | Commit de deploy | Papel |
| --- | --- | --- | --- | --- | --- |
| `edge-public-api` | `144.126.149.57` | `/opt/lowify/edge/edge-public-api` | `feat/auth-logout-observability` | `5910a10` | Registra e fornece, a administradores autenticados, o histórico de logout no Redis. |
| `dashboard-seller` | `144.126.149.57` | `/opt/lowify/front/dashboard-seller` | `feat/auth-logout-observability` | `6e4cf9da` | Registra invalidações e apresenta o histórico no item Adicional da visão geral do vendedor. |

## Alterações incluídas

- A lista por seller usa a chave `auth:logout-events:{seller_id}`, conserva no máximo 50 eventos e expira após 7 dias.
- Cada evento contém `at`, `source`, `reason` e `request_path`.
- O Public API registra: `jwt_expired_without_refresh_token`, `jwt_refresh_token_missing`, `jwt_refresh_rejected` e `jwt_refresh_lock_timeout`.
- O Dashboard registra: `legacy_login_token_mismatch` e `upstream_401` antes de limpar a sessão local.
- O endpoint autenticado `GET /api/admin/users/{sellerId}/auth-logout-events` devolve o histórico somente para administradores; a visão geral administrativa do vendedor o apresenta em tabela.
- A escrita no Redis é estritamente observacional: falha de conexão não bloqueia login, refresh, resposta HTTP nem logout.

## Pré-requisitos

1. Confirmar que as duas branches e os commits da tabela estão disponíveis no remoto.
2. Garantir que os dois containers conseguem alcançar o mesmo Redis de observabilidade. Configure os nomes de variáveis, sem registrar seus valores:
   - `AUTH_LOGOUT_EVENTS_REDIS_HOST`, `AUTH_LOGOUT_EVENTS_REDIS_PORT`, `AUTH_LOGOUT_EVENTS_REDIS_PASSWORD` e `AUTH_LOGOUT_EVENTS_REDIS_DB`; ou
   - os equivalentes já usados pelo refresh, `JWT_REFRESH_CACHE_REDIS_HOST`, `JWT_REFRESH_CACHE_REDIS_PORT`, `JWT_REFRESH_CACHE_REDIS_PASSWORD` e `JWT_REFRESH_CACHE_REDIS_DB`.
3. Não alterar `JWT_SECRET`, TTLs, chaves de sessão, banco de dados ou chaves de Redis existentes durante esta publicação.
4. Antes de cada atualização, parar se `git status --porcelain=v1` retornar qualquer linha; não descartar mudanças locais.

## Banco de dados

Não há migrations, DDL ou DML. Não executar migrations como parte deste deploy.

## Sequência de deploy

Modo de rebuild: incremental. Publicar primeiro o Public API; o Dashboard passa a registrar no mesmo armazenamento somente depois que o destino estiver confirmado.

### 1. Edge Public API — `144.126.149.57`

```bash
cd /opt/lowify/edge/edge-public-api
git status --porcelain=v1
git fetch origin --prune
git switch feat/auth-logout-observability
git pull --ff-only origin feat/auth-logout-observability
git merge-base --is-ancestor 5910a10 HEAD
git rev-parse --short HEAD
docker compose up -d --build edge-public-api
docker compose ps
docker compose logs --tail=100 edge-public-api
```

Interromper se o `merge-base` falhar ou se o container não ficar em execução. Não limpar a chave de histórico nem qualquer outra chave Redis.

### 2. Dashboard Seller — `144.126.149.57`

```bash
cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git fetch origin --prune
git switch feat/auth-logout-observability
git pull --ff-only origin feat/auth-logout-observability
git merge-base --is-ancestor 6e4cf9da HEAD
git rev-parse --short HEAD
```

O Dashboard usa o checkout montado no container; não executar `docker compose up -d --build front-dashboard-seller` nesta entrega. Os workers do Dashboard também não foram alterados e não devem ser reiniciados isoladamente.

## Validação pós-deploy

1. Abra o Dashboard com uma conta de teste válida e navegue por uma página que consulte dados no Public API. A página deve continuar carregando normalmente.
2. Mantenha a sessão aberta por mais de 15 minutos e volte a navegar. Se o cookie de refresh estiver válido, a pessoa deve permanecer autenticada sem precisar entrar novamente.
3. Em uma sessão controlada, remova apenas o cookie de refresh no navegador de teste, aguarde a expiração do access token e navegue. A pessoa deve ser direcionada ao login; isso cria o cenário esperado de expiração sem refresh.
4. Como administrador, abra a Visão geral do vendedor de teste, acesse o item Adicional “Histórico de logout”. O modal deve mostrar data, origem, motivo e caminho do evento, sem token, cookie, senha ou IP.
5. Se a navegação normal falhar, interrompa a publicação, preserve os logs de container e execute o rollback abaixo. Não tente corrigir apagando chaves Redis.

## Rollback

1. Reverter primeiro o Dashboard para a referência saudável anterior e recriar apenas `front-dashboard-seller`.
2. Reverter em seguida o Public API para a referência saudável anterior e recriar `edge-public-api`.
3. Não executar migration rollback e não apagar `auth:logout-events:{seller_id}`. Os registros são temporários, expiram automaticamente em 7 dias e podem ajudar a investigar a causa do rollback.
4. Validar login, uma navegação autenticada no Dashboard e uma chamada que passe pelo Public API.

## Riscos e limites

- A tela de histórico é restrita à visão administrativa do vendedor. O endpoint também exige JWT administrativo; colaboradores não podem consultar eventos.
- `legacy_login_token_mismatch` indica que a validação da sessão legada falhou. A investigação deve considerar novo login concorrente, alteração do token legado ou conta inativa antes de concluir a causa.
- Falhas de rede entre Public API e `services-auth` continuam seguindo o comportamento atual de erro; esta entrega não as converte em logout nem muda a política de retry.
