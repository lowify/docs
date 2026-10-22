# Correção crítica de PHP — Edge Checkout Transparent Webhook

## Estado

**Correção pendente.** O inventário de produção foi concluído em 22/10/2026. Nenhuma imagem, configuração ou container foi alterado por este registro.

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
2. Identificar uma imagem Hyperf/Swoole com PHP 8.3.36 ou superior, compatível com as extensões e o Swoole usados pelo projeto.
3. Fixar a tag exata no `Dockerfile`, hoje `hyperf/hyperf:8.3-alpine-v3.19-swoole`, para que rebuilds futuros sejam reproduzíveis.
4. Construir a imagem, validar `php -v` e recriar o único serviço `edge-checkout-transparent-webhook`.

### Futura ou pendente

- Confirmar a tag Hyperf corrigida antes de alterar o `Dockerfile`; ela ainda não foi selecionada.
- Executar a validação de runtime em homologação e de webhook assinado antes de produção.
- Avaliar, com o responsável pelo provedor de pagamentos, se a origem pode ser restringida no Traefik/WAF sem bloquear callbacks legítimos. Essa medida reduz exposição, mas não substitui a atualização.

## Commit de fix

**Pendente.** Nenhum commit foi criado para este componente. O commit deverá conter somente o pin da imagem Hyperf corrigida e será registrado aqui antes do deploy.

## Ações externas

Não criar bloqueio genérico de `multipart/form-data`, pois isso pode interromper callbacks legítimos. Se houver lista oficial e estável de IPs do provedor, a restrição de origem deve ser homologada separadamente.

Manter monitoramento de processos inesperados, downloads e reinícios do container até a atualização ser concluída.

## Testes em homologação

Ainda não executados para este componente.

Após selecionar a imagem, executar em homologação:

```bash
docker exec lowify-edge-checkout-transparent-webhook php -v
docker compose ps
```

Critério técnico: PHP 8.3.36 ou superior e container `Up`.

Em seguida, enviar um webhook de teste assinado pelo mecanismo oficial do provedor e confirmar que ele é aceito, processado uma única vez e não gera erro no log. Não usar webhook produtivo, credencial real ou payload sem assinatura para essa validação.

## Deploy e rollback

O caminho produtivo confirmado é:

```text
/opt/lowify-ct-webhook/edge-checkout-transparent-webhook/edge/edge-checkout-transparent-webhook
```

O deploy só será documentado com comandos após existir o commit de fix e a imagem compatível ser validada. Não há migration, alteração de banco, volume, cache ou fila neste ajuste de runtime.

Para rollback, retornar ao commit/imagem imediatamente anterior e recriar somente `edge-checkout-transparent-webhook`. Não limpar filas, banco, volumes ou logs de webhook.
