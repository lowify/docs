# Contenção temporária — vulnerabilidades críticas do PHP no Edge Gateway

## Estado

**Pendente de aplicação.** Nenhuma regra Cloudflare, configuração Traefik ou container foi alterado por este documento.

## Contexto confirmado

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

## Decisão de contenção

No momento, não existe uma imagem oficial Hyperf validada para este gateway que execute PHP 8.2.35 ou superior. A atualização direta da tag atualmente utilizada não corrige o runtime: as imagens testadas continuam em versões vulneráveis.

Enquanto o patch não estiver disponível na imagem Hyperf adotada, o objetivo é impedir que vetores conhecidos alcancem o PHP e limitar o tamanho de requisições que chegam ao gateway. Isso **reduz materialmente o risco**, mas não permite afirmar que a vulnerabilidade se tornou impossível de reproduzir. A atualização para PHP 8.2.35 ou superior permanece obrigatória assim que houver uma imagem validada.

## Escopo analisado

No fluxo `edge-gateway` → `edge-public-api`, não foram identificadas rotas PHP que processem upload de arquivo, `multipart/form-data`, `UploadedFile` ou `getUploadedFiles()`.

As rotas de banner recebem somente `checkout_banner_url` como string e exigem JWT; a aplicação encaminha a URL ao serviço de Commerce. Rotas de documentos nesse fluxo realizam consulta, análise e atualização de status/KYC, sem upload de documento.

Essa conclusão é baseada no código atual e não substitui a validação de consumidores externos não documentados.

## Medidas pendentes

### 1. Cloudflare WAF — bloquear multipart no gateway

Pré-condição: `gateway.lowify.com.br` deve estar com proxy Cloudflare ativo. A origem deve aceitar HTTP/HTTPS somente das faixas oficiais da Cloudflare; caso contrário, o WAF pode ser contornado por acesso direto ao IP de origem.

Criar uma regra em **Security rules → Custom rules**:

| Campo | Valor |
| --- | --- |
| Nome | `Block multipart on gateway` |
| Ação | `Block` |
| Expressão | `http.host eq "gateway.lowify.com.br" and any(http.request.headers["content-type"][*] matches "(?i).*multipart/form-data.*")` |

Validar que `GET /health`, login e checkout JSON continuam funcionando. Uma requisição multipart ao gateway deve ser recusada no edge e não alcançar o Traefik/PHP.

Referência para criar a regra no Cloudflare: [Custom rules — Cloudflare WAF](https://developers.cloudflare.com/waf/custom-rules/create-dashboard/).

### 2. Traefik — limitar tamanho do request body

Em `edge-gateway/docker-compose.yml`, no serviço `edge-gateway`, adicionar às labels:

```yaml
- traefik.http.middlewares.edge-gateway-request-limit.buffering.maxRequestBodyBytes=8388608
- traefik.http.routers.edge-gateway.middlewares=edge-gateway-request-limit
```

O teto inicial de 8 MiB preserva o limite PHP atual de `post_max_size` e reduz o risco de corpos ilimitados. Requests acima do limite devem receber `413 Request Entity Too Large` antes de atingir o PHP.

Aplicar em homologação antes de produção. A alteração requer recriar somente o container HTTP `edge-gateway`; não requer rebuild da imagem:

```bash
docker compose config --quiet
docker compose up -d --no-deps --force-recreate edge-gateway
```

### 3. PHP — desabilitar upload progress

Adicionar à configuração PHP carregada pela imagem:

```ini
session.upload_progress.enabled=0
```

Essa medida reduz uma rota conhecida associada ao estado residual entre requisições. Ela exige rebuild e recriação de `edge-gateway` e `edge-gateway-worker`, mas não substitui a atualização do PHP.

## Validação em homologação

Antes de produção, validar:

1. `GET /health` retorna sucesso.
2. Login continua respondendo normalmente.
3. Fluxo público de checkout JSON continua funcionando.
4. O maior payload JSON legítimo conhecido continua aceito.
5. Body acima de 8 MiB recebe `413`.
6. Requisição com `Content-Type: multipart/form-data` é bloqueada pelo Cloudflare, quando a regra estiver aplicada.

## Critério para remover a contenção temporária

Somente após uma imagem Hyperf ser validada com `php -v` retornando PHP 8.2.35 ou superior. A versão deve ser verificada dentro da imagem antes do deploy e novamente no container em execução.

## Referências

- [PHP — aviso de segurança](https://www.php.net/archive/2026.php#2026-10-20-1)
- [CVE-2026-109618 — advisory PHP](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
- [CVE-2026-109619 — advisory PHP](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)
- [Traefik Buffering middleware](https://doc.traefik.io/traefik/v2.11/middlewares/http/buffering/)
- [Cloudflare WAF custom rules](https://developers.cloudflare.com/waf/custom-rules/create-dashboard/)
