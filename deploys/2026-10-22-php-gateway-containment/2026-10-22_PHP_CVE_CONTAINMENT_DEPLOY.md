# Deploy principal — contenção das CVEs críticas do PHP

## Estado do deploy

**Homologação concluída; produção pendente.** As contenções de Traefik e PHP foram aplicadas e validadas no `edge-gateway` de homologação em 22/10/2026. A regra de Cloudflare ainda não foi criada e nenhuma alteração foi aplicada em produção.

## Objetivo

Registrar as decisões de contenção enquanto imagens Hyperf com o patch do PHP não estão disponíveis e validadas. O patch definitivo exige PHP 8.2.35 ou superior para runtimes PHP 8.2.

As contenções não eliminam a vulnerabilidade; elas reduzem vetores conhecidos enquanto o runtime corrigido não pode ser implantado.

## Escopo atual

O escopo inicial contém somente o container HTTP do `edge-gateway`. Os demais containers serão adicionados em documentos próprios após inventário, confirmação de exposição e decisão de mitigação.

| Container/serviço | Exposição confirmada | PHP verificado | Decisão atual | Documento específico |
| --- | --- | --- | --- | --- |
| `edge-gateway-edge-gateway-1` / `edge-gateway` | `gateway.lowify.com.br` via Traefik TLS | 8.2.26 | Contenção validada em homologação; aplicar em produção e criar WAF Cloudflare; aguardar imagem Hyperf com PHP 8.2.35+ validado | [Decisão do edge-gateway](2026-10-22_PHP_GATEWAY_CONTAINMENT_PENDING.md) |

## Decisão de runtime

As seguintes imagens foram verificadas e **não devem ser usadas como correção**:

| Imagem | PHP interno | Motivo |
| --- | --- | --- |
| `hyperf/hyperf:8.2-alpine-v3.19-swoole` | 8.2.26 | Abaixo de PHP 8.2.35 |
| `hyperf/hyperf:8.2-alpine-v3.22-swoole-v6.2.2` | 8.2.33 | Abaixo de PHP 8.2.35 |

Antes de qualquer atualização definitiva, validar a imagem candidata com:

```bash
docker run --rm --entrypoint php IMAGE -v
```

Prosseguir somente se retornar PHP 8.2.35 ou superior.

## Ordem de execução

1. Criar a regra WAF Cloudflare pendente para bloquear `multipart/form-data` em `gateway.lowify.com.br` e restringir o acesso direto à origem, se aplicável.
2. Publicar em produção as mesmas alterações validadas em homologação, após aprovação operacional.
3. Validar health, login, checkout JSON e a recusa `413` para body acima de 2 MiB.
4. Monitorar novas imagens Hyperf e validar o PHP interno antes de alterar o runtime.
5. Quando houver imagem corrigida, reconstruir e recriar `edge-gateway` e `edge-gateway-worker`.
6. Inventariar o próximo container exposto e criar seu documento de decisão antes de qualquer alteração.

## Critério de conclusão

O item `edge-gateway` só pode ser marcado como corrigido após a confirmação de PHP 8.2.35 ou superior dentro do container em execução. Até então, seu estado é **contido temporariamente**, não corrigido.

## Referências

- [Aviso de segurança do PHP](https://www.php.net/archive/2026.php#2026-10-20-1)
- [Runbook específico do edge-gateway](2026-10-22_PHP_GATEWAY_CONTAINMENT_PENDING.md)
