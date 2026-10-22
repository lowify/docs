# Correção crítica de PHP — Front IDV

## Estado

**Correção publicada na `main`; deploy em produção pendente.** Nenhum container de produção foi alterado por este registro.

## Contexto

O Front IDV é publicado por Nginx no host `files.${DOMAIN_MAIN}`. O Nginx público (`front-idv`) encaminha requisições PHP-FPM ao container `front-idv-app`.

Na VPS `147.93.180.183`, os containers `front-idv`, `front-idv-app` e `front-idv-cache` estavam `Up` há três dias. O app executava PHP 8.4.24, abaixo de PHP 8.4.27, mínimo corrigido para CVE-2026-109618 e CVE-2026-109619. A coleta confirmou PHP-FPM/FastCGI com `memory_limit=256M`, `post_max_size=40M`, `upload_max_filesize=15M` e `session.upload_progress.enabled=On`.

O Dockerfile usa atualmente `php:8.4-fpm-alpine` como base. Por ser uma tag móvel, ela não registra qual patch de PHP foi usado na imagem em execução.

## Tomada de ação

### Atual

1. Alterar a imagem base de `php:8.4-fpm-alpine` para `php:8.4.27-fpm-alpine`.
2. Construir com `--pull`, validar `php -v` na imagem e recriar `front-idv-app` e `front-idv` juntos. O Nginx precisa ser recriado porque recebe as conexões públicas e depende do app PHP-FPM.
3. Preservar os volumes `front_idv_storage` e `front_idv_cache`; eles não fazem parte da correção.

### Futura ou pendente

- Executar build e validação de interface em homologação antes de produção.
- A versão corrigida é a medida obrigatória; `session.upload_progress.enabled` não será alterada sem validação de upload.

## Commit de fix

`6c1ab0c` — `fix: upgrade IDV PHP runtime to 8.4.27`.

O commit modifica somente a imagem base do Dockerfile.

## Ações externas

Nenhuma ação externa bloqueia a correção. Não aplicar bloqueio genérico de `multipart/form-data`: o Front IDV armazena documentos de verificação e pode depender de uploads legítimos.

Como complemento operacional, manter monitoração para processos PHP inesperados, downloads anômalos e falhas/reinícios do PHP-FPM.

## Testes em homologação

O Dockerfile foi construído localmente sem erro e `php -v` na imagem resultante retornou PHP 8.4.27. A validação remota em homologação continua pendente.

Depois do build corrigido, confirmar:

```bash
docker exec front-idv-app php -v
docker compose ps
```

Critério técnico: PHP 8.4.27 ou superior, `front-idv-app` e `front-idv` em estado `Up`.

Na interface, abrir a página pública de IDV com uma conta de teste e, se houver roteiro seguro, enviar um documento de teste não sensível. O resultado esperado é upload e fluxo de verificação normais, sem erro 5xx. Não usar documento real nem dado pessoal de produção.

## Sequência de deploy em produção

O comando inicial descobre o diretório Compose real pelo label do container público, sem assumir caminho de outro host:

```bash
PROJECT_DIR="$(docker inspect front-idv --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}')"
test -n "$PROJECT_DIR" && test -d "$PROJECT_DIR" || {
  echo 'Diretório Compose do Front IDV não encontrado; interrompendo.' >&2
  exit 1
}
cd "$PROJECT_DIR"

test -z "$(git status --porcelain)" || {
  echo 'Há alterações locais; interrompendo.' >&2
  exit 1
}

git fetch origin --prune
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD

docker compose build --pull front-idv-app
docker compose up -d --no-deps --force-recreate front-idv-app front-idv

docker exec front-idv-app php -v
docker compose ps
```

Prosseguir somente se o commit for `6c1ab0c`, `php -v` informar PHP 8.4.27 e `front-idv-app` e `front-idv` estiverem `Up`.

## Rollback

Não há migration, DDL, DML, mudança de Redis ou alteração de contrato de API.

Para rollback, retornar ao commit `9dbd945` e recriar juntos `front-idv-app` e `front-idv`. Não apagar o volume de documentos de verificação nem o volume Redis.
