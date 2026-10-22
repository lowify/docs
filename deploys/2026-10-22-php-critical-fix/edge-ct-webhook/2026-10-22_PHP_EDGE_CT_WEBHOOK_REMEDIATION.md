# Correção crítica de PHP — Edge Checkout Transparent Webhook

## Estado

**Correção publicada na `main`; deploy em produção pendente.** Nenhum container de produção foi alterado por este registro.

## Contexto

O `edge-checkout-transparent-webhook` recebe requisições públicas em `checkout-transparent-webhook.lowify.com.br`, encaminhadas pelo Traefik para a porta 9501 do Hyperf/Swoole.

Na VPS `80.190.72.228`, o container `lowify-edge-checkout-transparent-webhook` estava `Up` há três dias e executava PHP 8.3.14. Essa versão está abaixo de PHP 8.3.36, mínimo corrigido para CVE-2026-109618 e CVE-2026-109619.

Configuração observada:

| Item | Valor |
| --- | --- |
| SAPI consultado | CLI; o processo web é Hyperf/Swoole |
| `memory_limit` | 1G |
| `post_max_size` | 8M |
| `upload_max_filesize` | 2M |
| `session.upload_progress.enabled` | On |
| Imagem construída atualmente | `edge-checkout-transparent-webhook-edge-checkout-transparent-webhook` |

Assinatura ou validação de webhook pela aplicação não protege o parsing de requisição que ocorre antes do código da aplicação. O serviço é público e deve ser tratado como prioridade alta.

## Tomada de ação

### Atual

1. Não publicar alteração parcial de `php.ini` como se ela fosse a correção completa.
2. Fixar `hyperf/hyperf:8.3-alpine-v3.23-swoole-v6.2.2`, validada localmente com PHP 8.3.36 e Swoole 6.2.2.
3. Construir a imagem, validar `php -v` e recriar o único serviço `edge-checkout-transparent-webhook`.

### Futura ou pendente

- Executar a validação de runtime em homologação e de webhook assinado antes de produção.
- Avaliar, com o responsável pelo provedor de pagamentos, se a origem pode ser restringida no Traefik/WAF sem bloquear callbacks legítimos. Essa medida reduz exposição, mas não substitui a atualização.

## Commit de fix

`c1faaaf` — `fix: upgrade CT webhook PHP runtime`.

O commit altera apenas a imagem base do `Dockerfile`.

## Ações externas

Não criar bloqueio genérico de `multipart/form-data`, pois isso pode interromper callbacks legítimos. Se houver lista oficial e estável de IPs do provedor, a restrição de origem deve ser homologada separadamente.

Manter monitoramento de processos inesperados, downloads e reinícios do container até a atualização ser concluída.

## Testes em homologação

O Dockerfile foi construído localmente sem erro e `php -v` na imagem resultante retornou PHP 8.3.36.

Em homologação, após o deploy, executar:

```bash
docker exec lowify-edge-checkout-transparent-webhook php -v
docker compose ps
```

Critério técnico: PHP 8.3.36 ou superior e container `Up`.

Em seguida, enviar um webhook de teste assinado pelo mecanismo oficial do provedor e confirmar que ele é aceito, processado uma única vez e não gera erro no log. Não usar webhook produtivo, credencial real ou payload sem assinatura para essa validação.

## Sequência de deploy em produção

O caminho produtivo confirmado é:

```text
/opt/lowify-ct-webhook/edge-checkout-transparent-webhook/edge/edge-checkout-transparent-webhook
```

```bash
cd /opt/lowify-ct-webhook/edge-checkout-transparent-webhook/edge/edge-checkout-transparent-webhook

test -z "$(git status --porcelain)" || {
  echo 'Há alterações locais; interrompendo.' >&2
  exit 1
}

git fetch origin --prune
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD

docker compose build --pull edge-checkout-transparent-webhook
docker compose up -d --no-deps --force-recreate edge-checkout-transparent-webhook

docker exec lowify-edge-checkout-transparent-webhook php -v
docker compose ps
```

Prosseguir somente se o commit for `c1faaaf`, `php -v` informar PHP 8.3.36 e o container estiver `Up`. Não há migration, alteração de banco, volume, cache ou fila neste ajuste de runtime.

## Rollback

Para rollback, retornar ao commit `5ad99b3` e recriar somente `edge-checkout-transparent-webhook`. Não limpar filas, banco, volumes ou logs de webhook.
