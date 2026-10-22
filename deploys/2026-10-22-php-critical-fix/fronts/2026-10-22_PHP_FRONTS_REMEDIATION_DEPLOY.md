# Deploy — correção crítica de PHP nos fronts Apache

## Objetivo

Atualizar o runtime PHP de três aplicações web públicas para PHP 8.3.36, versão que corrige CVE-2026-109618 e CVE-2026-109619. O escopo é exclusivamente o runtime dos containers: não há mudança de rota, contrato, banco, fila, variável de ambiente ou comportamento de negócio.

Os três serviços usam Apache com mod_php, cenário apontado pelo advisory do PHP como de maior risco. A atualização é a correção completa; mitigação isolada não substitui o patch.

## Componentes e referências

| Repositório | Diretório de produção | Container principal | Branch | Commit obrigatório |
| --- | --- | --- | --- | --- |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `front-dashboard-seller` e seis workers | `main` | `356cd9d3` |
| `front-checkout` | `/opt/lowify/front/front-checkout` | `front-checkout` | `main` | `412486b` |
| `front-member-area` | `/opt/lowify/front/front-member-area` | `front-members-area` | `main` | `1858ecf` |

## Contexto

Na coleta de produção de 22/10/2026, todos os containers estavam expostos por Traefik e executavam uma versão afetada:

| Container | PHP antes do deploy | Limites observados |
| --- | --- | --- |
| `front-dashboard-seller` | 8.3.35 | `memory_limit=128M`, `post_max_size=110M`, `upload_max_filesize=15M` |
| `front-checkout` | 8.3.33 | `memory_limit=128M`, `post_max_size=8M`, `upload_max_filesize=2M` |
| `front-members-area` | 8.3.33 | `memory_limit=128M`, `post_max_size=8M`, `upload_max_filesize=2M` |

Os três estavam com `session.upload_progress.enabled=On`. Depois da atualização para PHP 8.3.36, essa configuração não é necessária como contenção da vulnerabilidade e não será alterada neste deploy para evitar efeito em uploads legítimos.

## Tomada de ação

Cada `Dockerfile` passa a fixar a imagem base em `php:8.3.36-apache`. O pin torna a versão auditável e impede que um rebuild futuro dependa da tag móvel `php:8.3-apache`.

O deploy reconstrói e recria cada front de modo sequencial. O Dashboard inclui os workers porque todos usam a mesma imagem; atualizá-lo parcialmente deixaria processos PHP vulneráveis em execução.

Devido ao espaço reduzido no host, o procedimento conclui e limpa imagens *dangling* após cada componente. Não usar `docker system prune -a`, pois ele pode remover imagens e caches de serviços fora deste escopo.

## Ações externas

Nenhuma ação externa bloqueia esta correção. Não criar uma regra genérica de WAF que bloqueie `multipart/form-data`: Dashboard, Checkout e Área de Membros podem receber uploads legítimos.

Como medida operacional complementar, manter monitoração para processos PHP que abram shells ou baixem arquivos de forma inesperada. Isso não substitui o upgrade.

## Pré-requisitos

1. Acessar o host principal `144.126.149.57` com permissão para Docker e Git.
2. Reservar preferencialmente 10 GB livres no filesystem do Docker antes de iniciar. Conferir com `df -h /var/lib/docker` e `docker system df`.
3. Não prosseguir se qualquer árvore Git tiver alteração local: o comando de cada etapa interrompe nesse caso para preservar trabalho existente.
4. Executar os três blocos na ordem abaixo, concluindo a validação de versão antes de avançar ao próximo.

## Banco de dados

Não há migration, DDL, DML, alteração de cache ou de fila.

## Sequência de deploy

### 1. Dashboard Seller

```bash
cd /opt/lowify/front/dashboard-seller

test -z "$(git status --porcelain)" || {
  echo 'Há alterações locais; interrompendo.' >&2
  exit 1
}

git fetch origin --prune
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD

docker compose build --pull front-dashboard-seller
docker compose up -d --no-deps --force-recreate \
  front-dashboard-seller \
  front-dashboard-seller-cashing-worker \
  front-dashboard-seller-commerce-sales-actions-worker \
  front-dashboard-seller-withdrawal-payments-worker \
  front-dashboard-seller-commerce-refunds-actions-worker \
  front-dashboard-seller-dashboard-lowtrack-event-worker \
  front-dashboard-seller-evolution-cleanup-cron

docker exec front-dashboard-seller php -v
docker compose ps
docker image prune -f
docker system df
```

Prosseguir somente se o commit for `356cd9d3`, `php -v` informar `PHP 8.3.36` e todos os serviços estiverem `Up`.

### 2. Front Checkout

```bash
cd /opt/lowify/front/front-checkout

test -z "$(git status --porcelain)" || {
  echo 'Há alterações locais; interrompendo.' >&2
  exit 1
}

git fetch origin --prune
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD

docker compose build --pull front-checkout
docker compose up -d --no-deps --force-recreate front-checkout

docker exec front-checkout php -v
docker compose ps
docker image prune -f
docker system df
```

Prosseguir somente se o commit for `412486b`, `php -v` informar `PHP 8.3.36` e o container estiver `Up`.

### 3. Front Member Area

```bash
cd /opt/lowify/front/front-member-area

test -z "$(git status --porcelain)" || {
  echo 'Há alterações locais; interrompendo.' >&2
  exit 1
}

git fetch origin --prune
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD

docker compose build --pull front-members-area
docker compose up -d --no-deps --force-recreate front-members-area

docker exec front-members-area php -v
docker compose ps
docker image prune -f
docker system df
```

Prosseguir somente se o commit for `1858ecf`, `php -v` informar `PHP 8.3.36` e o container estiver `Up`.

## Testes em homologação

### Antes da atualização — Dashboard Seller

Em 22/10/2026, o `front-dashboard-seller` de homologação executava PHP 8.3.33. Foram enviados dois POSTs `multipart/form-data` de teste, sem conteúdo executável, com grande quantidade de cabeçalhos internos de partes para exercitar o parser:

| Corpo enviado | Resultado HTTP | Memória observada | Resultado |
| --- | --- | --- | --- |
| aproximadamente 7,74 MB e 430 mil cabeçalhos | 200 em aproximadamente 0,96 s | aproximadamente 31,6 MiB para 96 MiB | sem reinício ou OOM |
| aproximadamente 11,70 MB e 650 mil cabeçalhos | 200 em aproximadamente 0,95 s | aproximadamente 97 MiB para 160,6 MiB | sem reinício ou OOM |

O teste evidenciou amplificação de memória, mas não tentou executar código e não reproduziu OOM ou RCE. A ausência de reprodução não reduz a criticidade: a exploração depende de condições internas adicionais e pode ocorrer antes do código da aplicação.

### Imagens atualizadas — validação concluída localmente

Os três Dockerfiles foram construídos localmente com a base atualizada. A execução de `php -v` nas imagens de Dashboard, Checkout e Área de Membros retornou PHP 8.3.36.

### Validação pendente em homologação

Antes de produção, aplicar os mesmos três commits na VPS de homologação, recriar os respectivos containers e confirmar:

1. `php -v` retorna 8.3.36 em cada container.
2. Dashboard abre a tela de login e uma tela autenticada; os workers permanecem `Up`.
3. Checkout abre uma página pública de produto de teste sem erro visível.
4. Área de Membros permite login com conta de teste e abre um conteúdo já autorizado.
5. Se houver roteiro seguro de upload de teste em cada front, enviar um arquivo pequeno e confirmar que o upload normal continua funcionando.

## Validação pós-deploy

1. Abra o Dashboard Seller, faça login com uma conta de teste e navegue para Produtos e Vendas. As páginas devem carregar normalmente.
2. Abra uma página pública de checkout de teste. Ela deve carregar sem erro 5xx.
3. Faça login na Área de Membros com uma conta de teste que já tenha acesso a conteúdo. O conteúdo deve permanecer disponível.
4. Como conferência técnica complementar, confirme que cada `php -v` exibiu PHP 8.3.36 e que os containers continuam `Up`.
5. Se alguma tela falhar, interrompa a progressão para o próximo front, preserve os logs do container afetado e aplique o rollback abaixo.

## Rollback

Não há efeito persistente de banco, cache ou fila para reverter. A reversão é apenas da imagem/runtime.

Os commits imediatamente anteriores são `d22b1e34` (Dashboard), `fc22c16` (Checkout) e `8494045` (Área de Membros). Para uma reversão permanente, criar e publicar um `git revert` do commit da tabela de componentes e repetir o build/recreate somente do front afetado. Não apagar volumes de upload, imagens em uso ou dados de Docker como parte do rollback.
