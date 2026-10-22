# Correção crítica de PHP — Front IDV

## Estado

**Correção pendente.** O inventário de produção foi concluído em 22/10/2026. Nenhuma imagem, configuração ou container foi alterado por este registro.

## Contexto

O Front IDV é publicado por Nginx no host `files.${DOMAIN_MAIN}`. O Nginx público (`front-idv`) encaminha requisições PHP-FPM ao container `front-idv-app`.

Na VPS `147.93.180.183`, os containers `front-idv`, `front-idv-app` e `front-idv-cache` estavam `Up` há três dias. O app executava PHP 8.4.24, abaixo de PHP 8.4.27, mínimo corrigido para CVE-2026-109618 e CVE-2026-109619.

O Dockerfile usa atualmente `php:8.4-fpm-alpine` como base. Por ser uma tag móvel, ela não registra qual patch de PHP foi usado na imagem em execução.

## Tomada de ação

### Atual

1. Alterar a imagem base de `php:8.4-fpm-alpine` para `php:8.4.27-fpm-alpine`.
2. Construir com `--pull`, validar `php -v` na imagem e recriar `front-idv-app` e `front-idv` juntos. O Nginx precisa ser recriado porque recebe as conexões públicas e depende do app PHP-FPM.
3. Preservar os volumes `front_idv_storage` e `front_idv_cache`; eles não fazem parte da correção.

### Futura ou pendente

- Criar o commit de Dockerfile na `main`.
- Executar build e validação de interface em homologação antes de produção.
- Confirmar em produção os limites PHP e `session.upload_progress.enabled`, pois a VPS não possui `rg` e a coleta inicial dessa configuração não foi concluída. A versão corrigida é a medida obrigatória; a configuração não será alterada sem validação de upload.

## Commit de fix

**Pendente.** O commit deverá modificar apenas a imagem base do `front-idv` para PHP 8.4.27 e será registrado aqui antes do deploy.

## Ações externas

Nenhuma ação externa bloqueia a correção. Não aplicar bloqueio genérico de `multipart/form-data`: o Front IDV armazena documentos de verificação e pode depender de uploads legítimos.

Como complemento operacional, manter monitoração para processos PHP inesperados, downloads anômalos e falhas/reinícios do PHP-FPM.

## Testes em homologação

Ainda não executados para este componente.

Depois do build corrigido, confirmar:

```bash
docker exec front-idv-app php -v
docker compose ps
```

Critério técnico: PHP 8.4.27 ou superior, `front-idv-app` e `front-idv` em estado `Up`.

Na interface, abrir a página pública de IDV com uma conta de teste e, se houver roteiro seguro, enviar um documento de teste não sensível. O resultado esperado é upload e fluxo de verificação normais, sem erro 5xx. Não usar documento real nem dado pessoal de produção.

## Deploy e rollback

O diretório de produção do Front IDV ainda precisa ser confirmado no servidor antes de gerar comandos operacionais. Não inferir o caminho a partir de outro host.

Não há migration, DDL, DML, mudança de Redis ou alteração de contrato de API.

Para rollback após a futura publicação, retornar ao commit/imagem imediatamente anterior e recriar juntos `front-idv-app` e `front-idv`. Não apagar o volume de documentos de verificação nem o volume Redis.
