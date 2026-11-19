# Cloudflare — MCP em homologação

## Objetivo

Permitir que clientes MCP remotos, como Claude e ChatGPT, usem o endpoint de
homologação sem desafios HTML, cache ou bloqueios de borda incompatíveis com
OAuth 2.1 e Streamable HTTP.

Este documento é restrito à homologação. Não replicar regras em produção sem
revisão própria.

## Escopo exato da exceção

| Host | Caminhos | Métodos necessários | Finalidade |
| --- | --- | --- | --- |
| `mcp.statuslive.site` | `/mcp` | `GET`, `POST`, `DELETE`, `OPTIONS` | Transporte Streamable HTTP do MCP. |
| `mcp.statuslive.site` | `/.well-known/oauth-protected-resource` e `/.well-known/oauth-protected-resource/mcp` | `GET` | Descoberta do resource server OAuth. |
| `mcp-auth.statuslive.site` | `/.well-known/oauth-authorization-server` | `GET` | Descoberta do authorization server OAuth. |
| `mcp-auth.statuslive.site` | `/oauth/mcp/authorize` | `GET` | Início do consentimento OAuth; redireciona ao Dashboard. |
| `mcp-auth.statuslive.site` | `/oauth/mcp/token` e `/oauth/mcp/register` | `POST` | Troca de token e registro de cliente OAuth. |

Não criar uma exceção para `*.statuslive.site`, para todo o Dashboard ou para
outros caminhos. A exceção deve ser limitada aos hosts e caminhos desta tabela.

## Antes de alterar regras

1. No dashboard Cloudflare da zona `statuslive.site`, abrir **Security →
   Events**.
2. Filtrar por hostname `mcp.statuslive.site` ou `mcp-auth.statuslive.site`.
3. Filtrar pelo caminho que falhou, especialmente `/mcp`.
4. Registrar qual serviço tomou a ação: Custom Rule, Managed Rules, Rate
   Limiting, Bot Fight Mode ou Super Bot Fight Mode.

O evento determina qual exceção é necessária. Não desativar produtos de
segurança globalmente sem evidência de que são a causa.

## Regra WAF de exceção limitada

Criar em **Security → WAF → Custom rules → Create rule**.

Nome sugerido: `MCP homologation transport exception`.

Expressão:

```txt
(
  (http.host eq "mcp.statuslive.site" and starts_with(http.request.uri.path, "/mcp"))
  or
  (http.host eq "mcp.statuslive.site" and starts_with(http.request.uri.path, "/.well-known/oauth-protected-resource"))
  or
  (http.host eq "mcp-auth.statuslive.site" and (
    starts_with(http.request.uri.path, "/.well-known/oauth-authorization-server")
    or starts_with(http.request.uri.path, "/oauth/mcp/")
  ))
)
```

Escolher a ação **Skip** e selecionar apenas os mecanismos confirmados em
Security Events. Para o cenário atual, os candidatos são:

- **All Super Bot Fight Mode rules**;
- **All Managed Rules**;
- **All rate limiting rules**, somente se o evento apontar rate limit;
- **All remaining custom rules**, somente se houver uma regra customizada que
  bloqueie o mesmo tráfego e a ordem das regras não puder ser ajustada.

Manter **Log matching requests** habilitado. Posicionar a regra antes de regras
genéricas de bloqueio ou challenge.

### Bot Fight Mode simples

O Bot Fight Mode simples não aceita exceção por uma regra `Skip`. Se ele for o
serviço indicado em Security Events, não desativá-lo automaticamente: decidir
entre desligá-lo para a zona de homologação ou migrar para Super Bot Fight Mode,
que permite exceções delimitadas.

## Cache

Criar em **Rules → Cache Rules → Create rule** uma regra chamada `Bypass MCP
homologation cache` com a mesma expressão da regra WAF acima e a ação:

```text
Cache eligibility: Bypass cache
```

OAuth e Streamable HTTP não podem receber páginas ou respostas JSON em cache.

## Redirects, Workers e Transform Rules

Em **Rules**, revisar Redirect Rules, Origin Rules, Transform Rules e Workers.
Para os hosts/caminhos da tabela inicial, não pode haver regra que:

- redirecione o endpoint MCP ou OAuth;
- reescreva método, corpo, `Authorization`, `Content-Type`, `Accept`,
  `WWW-Authenticate` ou `Location`;
- gere challenge/cookie HTML;
- intercepte `GET /mcp`, `POST /mcp` ou `DELETE /mcp`.

Se houver Worker, criar uma condição de bypass para esses hosts e caminhos ou
garantir que ele encaminhe os métodos, headers e corpo sem alteração.

## DNS e TLS

- Os registros `mcp.statuslive.site` e `mcp-auth.statuslive.site` devem apontar
  para a VPS de homologação e permanecer proxied somente se as regras acima
  estiverem compatíveis.
- TLS deve usar **Full (strict)**.
- Não usar Access, Basic Auth ou challenge de navegador nesses endpoints, pois
  clientes MCP não resolvem páginas HTML ou JavaScript.

## Validação após a alteração

Executar de uma máquina externa, sem token:

```bash
curl -i https://mcp-auth.statuslive.site/.well-known/oauth-authorization-server
curl -i https://mcp.statuslive.site/.well-known/oauth-protected-resource/mcp
curl -i -X GET -H 'Accept: text/event-stream' https://mcp.statuslive.site/mcp
curl -i -X POST https://mcp.statuslive.site/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Critérios de aceite:

| Verificação | Resultado esperado |
| --- | --- |
| Authorization Server Metadata | `200`, `Content-Type: application/json`; issuer `https://mcp-auth.statuslive.site`. |
| Protected Resource Metadata | `200`, `Content-Type: application/json`; resource `https://mcp.statuslive.site/mcp`. |
| `GET /mcp` | não pode ser `404`, challenge HTML ou página Cloudflare; deve chegar ao origin como Streamable HTTP. |
| `POST /mcp` com `tools/list` | `200` com as ferramentas e seus `securitySchemes` OAuth. |
| `POST /mcp` para `tools/call` sem Bearer | `401` com `WWW-Authenticate` apontando para a metadata protegida. |
| Claude e ChatGPT | conseguem iniciar OAuth, completar o consentimento e chamar uma tool de leitura. |

## Segurança residual

A exceção de borda não torna o MCP público em dados: as tools continuam
protegidas por OAuth, PKCE, token de curta duração, escopos por seller e rate
limit no serviço. A regra Cloudflare existe somente para não exigir JavaScript,
cookie de challenge ou cache em um protocolo de máquina para máquina.

## Referências

- Cloudflare, [Skip options](https://developers.cloudflare.com/waf/custom-rules/skip/options/).
- Cloudflare, [tratar falsos positivos de Bot Fight Mode](https://developers.cloudflare.com/bots/troubleshooting/false-positives/).
- OpenAI, [custom MCP server no ChatGPT](https://developers.openai.com/api/docs/guides/custom-mcp-server).
