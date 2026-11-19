# Homologação — serviço MCP somente leitura

## Objetivo

Preparar a homologação do novo `services-ai-mcp` em Docker, acessível pelo
hostname `mcp.statuslive.site`. Nesta etapa são publicados somente o novo
serviço e seus endpoints de health e descoberta OAuth; Auth, Gateway,
Commerce V2 e Dashboard permanecem sem deploy para essa feature.

## Componente participante

| Repositório | Diretório na VPS | Branch | Commit | Ação |
| --- | --- | --- | --- | --- |
| `services-ai-mcp` | `/root/opt/lowify/services/services-ai-mcp` | `feat/mcp-readonly-service` | `ac0c41a` | clone, configurar `.env` e build |

Todos os demais targets operáveis da homologação devem ser mantidos como estão,
por solicitação explícita. Não executar Git, Docker, migrations ou alterações
em `services-auth`, `edge-gateway`, `services-commerce-v2`, `dashboard-seller`,
infraestrutura, banco ou Redis nesta etapa.

## Pré-requisitos

1. Os registros Cloudflare `mcp.statuslive.site` e `mcp-auth.statuslive.site`
   devem apontar para a VPS. Somente `mcp.statuslive.site` é usado agora.
2. O TLS do origin deve estar em modo Full (strict).
3. A rede Docker externa `data_net` e o Redis compartilhado já devem existir.
4. Criar `/root/opt/lowify/services` se ele ainda não existir; não sobrescrever
   um diretório já existente chamado `services-ai-mcp`.
5. Criar segredos novos para as variáveis `AUTH_SERVICE_AUTHORIZATION`,
   `COMMERCE_SERVICE_AUTHORIZATION` e `COMMERCE_SERVICE_SIGNATURE_SECRET`.
   Eles não serão usados até os serviços correspondentes entrarem na
   homologação, mas não podem permanecer com `REPLACE_ME`.

## Banco de dados

Não há banco nem migration nesta etapa. O serviço usa somente Redis para rate
limit; não criar MariaDB ou Redis dedicados.

## Sequência de deploy

1. Na VPS, verificar que o caminho de destino não existe ou está limpo:

   ```bash
   test ! -e /root/opt/lowify/services/services-ai-mcp
   ```

2. Clonar e fixar a branch publicada:

   ```bash
   cd /root/opt/lowify/services
   git clone --branch feat/mcp-readonly-service git@github.com:lowify/services-ai-mcp.git services-ai-mcp
   cd /root/opt/lowify/services/services-ai-mcp
   git fetch origin --prune
   git switch feat/mcp-readonly-service
   git pull --ff-only origin feat/mcp-readonly-service
   git rev-parse --short HEAD
   ```

   O commit esperado é `ac0c41a` ou um descendente explicitamente aprovado.

3. Criar `.env` a partir de `.env.homolog.example`, preencher valores reais e
   restringir leitura do arquivo:

   ```bash
   cp .env.homolog.example .env
   chmod 600 .env
   ```

4. Confirmar que não restaram placeholders antes de subir:

   ```bash
   if grep -q 'REPLACE_ME' .env; then
     echo 'Configure os segredos antes do deploy.' >&2
     exit 1
   fi
   ```

5. Construir e iniciar somente o serviço novo:

   ```bash
   docker compose up -d --build services-ai-mcp
   docker compose ps
   docker compose logs --tail=100 services-ai-mcp
   ```

## Validação pós-deploy

1. Abra `https://mcp.statuslive.site/health`. Deve aparecer o status saudável
   do serviço.
2. Abra `https://mcp.statuslive.site/.well-known/oauth-protected-resource`.
   Deve aparecer um documento JSON com o recurso MCP e os escopos de leitura.
3. Não teste login, troca de token ou ferramentas ainda: essas etapas dependem
   do deploy coordenado de Auth, Gateway, Commerce V2 e Dashboard.

## Rollback

Parar somente o container novo:

```bash
cd /root/opt/lowify/services/services-ai-mcp
docker compose stop services-ai-mcp
```

Não remover a rede `data_net`, não limpar Redis compartilhado, não usar
`docker compose down -v` e não alterar outros repositórios.

## Próxima etapa coordenada

Após este smoke test, publicar as branches de `services-auth`, `edge-gateway`,
`services-commerce-v2` e `dashboard-seller`, aplicar a migration do Auth e
validar consentimento OAuth, refresh, consultas e revogação.

## Execução em homologação — 2026-11-18

- Serviço clonado e publicado em `/root/opt/lowify/services/services-ai-mcp` no
  commit `ac0c41a`, branch `feat/mcp-readonly-service`.
- Imagem construída e container `services-ai-mcp` iniciado na rede `data_net`.
- `GET https://mcp.statuslive.site/health` respondeu `200` com status saudável.
- `GET https://mcp.statuslive.site/.well-known/oauth-protected-resource`
  respondeu com o recurso canônico e escopos de leitura.
- `POST /mcp` sem credencial respondeu `401`, JSON-RPC `Unauthorized` e o
  cabeçalho `WWW-Authenticate` apontando para a metadata protegida.
- Nenhum outro repositório, container, banco, Redis ou migration foi alterado.
