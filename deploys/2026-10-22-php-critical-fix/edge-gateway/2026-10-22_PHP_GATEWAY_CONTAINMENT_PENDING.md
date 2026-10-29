# Contenção temporária — vulnerabilidades críticas do PHP no Edge Gateway

## Estado

**Aplicado e validado em homologação; pendente de produção.** As medidas 2 e 3 foram implementadas e validadas no workspace local e em homologação em 22/10/2026. Nenhuma regra do Cloudflare foi criada e nenhuma alteração foi aplicada em produção.

## Contexto

O `edge-gateway` de produção atende `gateway.lowify.com.br` por Traefik, na entrada TLS `websecure`.

Em 22/10/2026, a verificação direta do container HTTP identificou:

```text
Container: edge-gateway-edge-gateway-1
PHP: 8.2.26
Runtime: Hyperf/Swoole
memory_limit: 1G
post_max_size: 8M
upload_max_filesize: 2M
session.upload_progress.enabled: On
```

Essa versão é anterior ao mínimo corrigido para as vulnerabilidades PHP CVE-2026-109618 e CVE-2026-109619: **PHP 8.2.35**.

Foram testadas imagens oficiais Hyperf em homologação e produção:

| Imagem | PHP verificado | Resultado |
| --- | --- | --- |
| `hyperf/hyperf:8.2-alpine-v3.19-swoole` | 8.2.26 | Vulnerável |
| `hyperf/hyperf:8.2-alpine-v3.22-swoole-v6.2.2` | 8.2.33 | Vulnerável |

Até a publicação de uma imagem Hyperf que execute PHP 8.2.35 ou superior, as medidas abaixo reduzem exposição, mas não corrigem integralmente a vulnerabilidade.

## Tomada de ação

No momento, não existe uma imagem oficial Hyperf validada para este gateway que execute PHP 8.2.35 ou superior. A atualização direta da tag atualmente utilizada não corrige o runtime: as imagens testadas continuam em versões vulneráveis.

Enquanto o patch não estiver disponível na imagem Hyperf adotada, o objetivo é impedir que vetores conhecidos alcancem o PHP e limitar o tamanho de requisições que chegam ao gateway. Isso **reduz materialmente o risco**, mas não permite afirmar que a vulnerabilidade se tornou impossível de reproduzir. A atualização para PHP 8.2.35 ou superior permanece obrigatória assim que houver uma imagem validada.

| Horizonte | Ação |
| --- | --- |
| Atual | Desabilitar `session.upload_progress`, limitar requests no Traefik a 2 MiB e aplicar a mesma configuração em produção após aprovação. |
| Atual, fora do commit | Criar a regra WAF do Cloudflare para bloquear `multipart/form-data` no hostname público. |
| Futuro | Substituir a imagem por uma versão Hyperf validada com PHP 8.2.35 ou superior e remover as contenções apenas após nova validação. |

## Escopo analisado

No fluxo `edge-gateway` → `edge-public-api`, não foram identificadas rotas PHP que processem upload de arquivo, `multipart/form-data`, `UploadedFile` ou `getUploadedFiles()`.

As rotas de banner recebem somente `checkout_banner_url` como string e exigem JWT; a aplicação encaminha a URL ao serviço de Commerce. Rotas de documentos nesse fluxo realizam consulta, análise e atualização de status/KYC, sem upload de documento.

Essa conclusão é baseada no código atual e não substitui a validação de consumidores externos não documentados.

## Ações externas (fora do commit)

### Cloudflare WAF — bloquear multipart no gateway

Pré-condição: `gateway.lowify.com.br` deve estar com proxy Cloudflare ativo. A origem deve aceitar HTTP/HTTPS somente das faixas oficiais da Cloudflare; caso contrário, o WAF pode ser contornado por acesso direto ao IP de origem.

Criar uma regra em **Security rules → Custom rules**:

| Campo | Valor |
| --- | --- |
| Nome | `Block multipart on gateway` |
| Ação | `Block` |
| Expressão | `http.host eq "gateway.lowify.com.br" and any(http.request.headers["content-type"][*] matches "(?i).*multipart/form-data.*")` |

Validar que `GET /health`, login e checkout JSON continuam funcionando. Uma requisição multipart ao gateway deve ser recusada no edge e não alcançar o Traefik/PHP.

Referência para criar a regra no Cloudflare: [Custom rules — Cloudflare WAF](https://developers.cloudflare.com/waf/custom-rules/create-dashboard/).

Status: **pendente**. Esta ação exige acesso ao painel/conta Cloudflare e não é coberta pelo commit de código.

## Commit de fix

Status: criado diretamente na branch `main`: `4b8d586` (`fix: contain PHP upload attack paths`). O deploy em produção permanece pendente.

O commit deve incluir exclusivamente:

| Arquivo | Alteração |
| --- | --- |
| `Dockerfile` | Carrega o hardening PHP antes de iniciar o runtime. |
| `docker/php/99-security-hardening.ini` | Define `session.upload_progress.enabled=0`. |
| `docker-compose.yml` | Cria e associa o middleware Traefik de limite de body. |

Antes do deploy em produção, confirmar que a referência `4b8d586` está disponível no remoto da `main` usado pelo servidor.

### Traefik — limitar tamanho do request body

Em `edge-gateway/docker-compose.yml`, no serviço `edge-gateway`, adicionar às labels:

```yaml
- traefik.http.middlewares.edge-gateway-request-limit.buffering.maxRequestBodyBytes=2097152
- traefik.http.routers.edge-gateway.middlewares=edge-gateway-request-limit
```

O limite é 2 MiB, igual ao `package_max_length` efetivo do Swoole neste gateway. Assim, a borda devolve `413` antes do backend para requests que este já recusaria.

Status: aplicado e validado em homologação. A recriação do serviço `edge-gateway` fez o Traefik carregar as labels.

Aplicar em homologação antes de produção. A alteração requer recriar somente o container HTTP `edge-gateway`; não requer rebuild da imagem:

```bash
docker compose config --quiet
docker compose up -d --no-deps --force-recreate edge-gateway
```

### PHP — desabilitar upload progress

Adicionar à configuração PHP carregada pela imagem:

```ini
session.upload_progress.enabled=0
```

Status: aplicado e validado em homologação a partir de `docker/php/99-security-hardening.ini`. Requer rebuild e recriação de `edge-gateway` e `edge-gateway-worker` no deploy.

Essa medida reduz uma rota conhecida associada ao estado residual entre requisições. Ela exige rebuild e recriação de `edge-gateway` e `edge-gateway-worker`, mas não substitui a atualização do PHP.

## Sequência de deploy em produção

Publicar a `main`, reconstruir as imagens e recriar os dois serviços:

```bash
cd /opt/lowify/edge/edge-gateway

git pull --ff-only origin main
docker compose build edge-gateway edge-gateway-worker
docker compose up -d --no-deps --force-recreate edge-gateway edge-gateway-worker
```

## Validação pós-deploy em produção

Executar após os containers estarem `Up`:

```bash
cd /opt/lowify/edge/edge-gateway

GATEWAY_CONTAINER=$(docker compose ps -q edge-gateway)

docker exec "$GATEWAY_CONTAINER" php -r 'echo "PHP=", PHP_VERSION, PHP_EOL; echo "session.upload_progress.enabled=", ini_get("session.upload_progress.enabled"), PHP_EOL;'
docker inspect -f '{{ index .Config.Labels "traefik.http.middlewares.edge-gateway-request-limit.buffering.maxRequestBodyBytes" }}' "$GATEWAY_CONTAINER"
curl --fail --silent --show-error --max-time 10 https://gateway.lowify.com.br/health
```

Critérios de aprovação: `session.upload_progress.enabled=0`, label com `2097152`, health check HTTP 200, e ausência de erros novos nos logs. Em uma janela autorizada, repetir o teste de body acima de 2 MiB usado em homologação e confirmar `413`; não executar tentativa de RCE em produção.

## Validação em homologação

Executada em 22/10/2026, diretamente contra `gateway.statuslive.site` pelo Traefik local:

| Verificação | Antes da correção | Depois da correção final |
| --- | --- | --- |
| `session.upload_progress.enabled` | `On` | `Off` |
| Limite de body no Traefik | Não configurado | 2 MiB (`2097152`) |
| Carga multipart sintética de 7.740.122 bytes | `413` pelo Swoole (`package_max_length=2 MiB`); a requisição alcançou o backend | `413` pelo Traefik em 25 ms; não houve log de processamento no Swoole/PHP |
| OOM e reinícios | Nenhum observado no baseline | Nenhum após o teste |
| `GET /health` | `200` | `200` |

A memória observada no baseline foi 30,42 MiB e, após o teste final, 21,11 MiB. Esses valores não devem ser comparados como ganho de memória, pois o container foi recriado entre as medições; o dado relevante é que a memória permaneceu em 21,11 MiB antes e depois da carga pós-correção.

Houve uma tentativa intermediária de configurar 8 MiB no Traefik. Nesse estado, a requisição de 7,74 MiB passou pela borda, alcançou o Swoole e retornou `500`, porque o backend já recusava esse tamanho. O limite Traefik foi reduzido para os mesmos 2 MiB, eliminando essa resposta `500` e movendo a recusa para a borda.

O teste confirma a contenção configurada; não prova ausência de todos os vetores das CVEs nem substitui atualizar o PHP.

Antes de produção, validar:

1. `GET /health` retorna sucesso.
2. Login continua respondendo normalmente.
3. Fluxo público de checkout JSON continua funcionando.
4. O maior payload JSON legítimo conhecido continua aceito.
5. Body acima de 2 MiB recebe `413`.
6. Requisição com `Content-Type: multipart/form-data` é bloqueada pelo Cloudflare, quando a regra estiver aplicada.

## Critério para remover a contenção temporária

Somente após uma imagem Hyperf ser validada com `php -v` retornando PHP 8.2.35 ou superior. A versão deve ser verificada dentro da imagem antes do deploy e novamente no container em execução.

## Referências

- [PHP — aviso de segurança](https://www.php.net/archive/2026.php#2026-10-20-1)
- [CVE-2026-109618 — advisory PHP](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
- [CVE-2026-109619 — advisory PHP](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)
- [Traefik Buffering middleware](https://doc.traefik.io/traefik/v2.11/middlewares/http/buffering/)
- [Cloudflare WAF custom rules](https://developers.cloudflare.com/waf/custom-rules/create-dashboard/)
