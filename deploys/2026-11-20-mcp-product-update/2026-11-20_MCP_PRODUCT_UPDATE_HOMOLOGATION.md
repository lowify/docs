# Homologação — edição básica de produtos via MCP

## Objetivo

Publicar a edição confirmada de produtos pelo MCP. O seller poderá alterar
somente título, preço, imagem principal e entregáveis de um produto próprio,
sempre passando por prévia, confirmação explícita e idempotência.

## Componentes e referências

| Repositório | Diretório na VPS | Branch | Commit |
| --- | --- | --- | --- |
| `services-ai-mcp` | `/root/opt/lowify/services/services-ai-mcp` | `feat/mcp-readonly-service` | `82ff896` |
| `services-commerce-v2` | `/root/opt/lowify/services/service-commerce-v2` | `feat/mcp-readonly-service` | `28a6c55` |
| `dashboard-seller` | `/root/opt/lowify/front/dashboard-seller` | `feat/mcp-readonly-service` | `02d07877` |

Modo de rebuild: incremental. Todos os demais targets operáveis, incluindo
Auth, Account e Gateway, devem ser mantidos exatamente como estão por
instrução explícita; não executar Git, Docker ou migrations neles.

## Alterações incluídas

- MCP: ferramentas `preview_update_product` e `update_product`, protegidas por
  `mcp.products.write` e confirmação com validade de cinco minutos.
- Commerce V2: endpoints internos assinados para prévia e atualização, com
  verificação de propriedade pelo seller e substituição transacional dos PDFs
  quando a entrega for alterada.
- Dashboard: consentimento OAuth redesenhado com componentes base e descrição
  clara da permissão de criar e editar produtos.

## Pré-requisitos

1. Os serviços MCP e Commerce V2 já possuem as autorizações internas e a
   assinatura HMAC usadas pela criação de produtos MCP.
2. O usuário de banco do Commerce V2 pode criar uma tabela aditiva.
3. Não registrar nem exibir valores de `.env`, tokens ou segredos.

## Banco de dados

Aplicar somente a migration aditiva
`20261120120000_create_mcp_product_update_idempotency_table.php` no banco do
Commerce V2. Ela cria `mcp_product_update_idempotency` com chave única por
seller e chave de idempotência. Não apagar a tabela anterior de criação de
produtos e não limpar dados de produto ou Redis.

Como o container atual não disponibiliza o executor de migrations, aplicar o
DDL equivalente por procedimento manual controlado e confirmar a existência
da tabela e da chave única antes do rebuild.

## Sequência de deploy

1. Fazer a pré-checagem, sem alterar estado, nos três diretórios da tabela:

   ```bash
   git status --porcelain=v1
   git branch --show-current
   git remote get-url origin
   ```

   Se houver mudanças locais em qualquer participante, parar o deploy.

2. Em cada participante, buscar referências e confirmar a branch remota:

   ```bash
   git fetch origin --prune
   git show-ref --verify --quiet refs/remotes/origin/feat/mcp-readonly-service
   ```

3. Atualizar sequencialmente MCP, Commerce V2 e Dashboard:

   ```bash
   git switch feat/mcp-readonly-service
   git pull --ff-only origin feat/mcp-readonly-service
   ```

4. Aplicar a migration aditiva do Commerce V2 pelo procedimento manual
   controlado e validar a tabela e sua chave única.

5. Somente para participantes cujo commit mudou, executar, um por vez:

   ```bash
   docker compose up -d --build
   docker compose ps
   ```

## Validação pós-deploy

1. Abra o Dashboard de homologação, conecte o cliente de IA e confira a tela
   de autorização: ela deve usar o logo da Lowify e informar a permissão de
   criar e editar produtos.
2. Em uma conversa conectada a um seller de teste, peça para alterar somente o
   título de um produto de teste. A IA deve primeiro mostrar a prévia e pedir
   confirmação.
3. Confirme a alteração. O título deve aparecer atualizado no Dashboard e o
   produto deve continuar pertencendo ao mesmo seller.
4. Repita com uma entrega de e-book e confira que os entregáveis mostrados no
   Dashboard foram substituídos. Não use produto de cliente real.

Como conferência técnica complementar, o health público do MCP deve responder
normalmente e os logs não devem apresentar erros de assinatura ou migração.

## Rollback

Reverter somente os três repositórios para os commits anteriores da mesma
branch e reconstruir apenas os containers que forem alterados. A tabela de
idempotência é aditiva e deve permanecer; não apagar produtos, PDFs, tokens ou
chaves Redis como parte do rollback.

## Execução em homologação — 2026-11-20

- Os três participantes estavam limpos e foram atualizados por fast-forward
  para os commits documentados. Os demais targets foram mantidos como estavam.
- Um backup temporário de configuração criado em operação anterior no diretório
  do MCP foi removido antes da pré-checagem; ele não era configuração ativa nem
  fazia parte do repositório.
- O DDL aditivo da tabela `mcp_product_update_idempotency` foi aplicado no
  banco do Commerce V2. A tabela foi confirmada como InnoDB e a chave única
  `mcp_product_update_idempotency_seller_key_unique` foi validada.
- MCP e Commerce V2 foram reconstruídos incrementalmente e iniciaram com os
  workers HTTP e de fila normais. O Dashboard recebeu somente o pull da branch,
  conforme orientação anterior para esse frontend.
- `https://mcp.statuslive.site/health` respondeu `200`; `tools/list` expôs
  `preview_update_product` e `update_product`; a rota interna do Commerce
  respondeu `401` sem assinatura, comportamento esperado para a verificação
  sem credenciais.

## Correção de autorização — 2026-11-20

- O Dashboard foi atualizado incrementalmente para o commit `4168de3b` da
  mesma branch. Quando o cliente OAuth omitir o parâmetro `scope`, o
  consentimento agora inclui também `mcp.products.write`.
- O container do Dashboard não foi reconstruído, conforme a orientação vigente
  para esse frontend; a atualização ocorreu somente por pull do código.
- Conexões OAuth já autorizadas não são alteradas retroativamente: é necessário
  desconectar e conectar novamente o cliente de IA para emitir um token com a
  nova permissão.

## Correção de metadata OAuth — 2026-11-20

- O MCP foi atualizado incrementalmente para o commit `5025837` e reconstruído.
  O documento público de recurso protegido agora anuncia
  `mcp.products.write`, além dos scopes de leitura.
- A metadata pública e o health do MCP foram consultados após o restart e
  responderam corretamente. Clientes que fazem descoberta OAuth passam a poder
  solicitar a permissão de edição ao reconectar.

## Correção de validação de preço — 2026-11-20

- O Commerce V2 foi atualizado para `8b939f3` e o MCP para `622a621`, ambos na
  mesma branch e reconstruídos incrementalmente.
- A prévia de edição passa a bloquear preço abaixo do mínimo aplicável antes da
  confirmação. O MCP também devolve erros de validação do Commerce como erro de
  ferramenta, em vez de reportá-los como indisponibilidade temporária.
- Não houve alteração de produto durante esta correção. O health público do MCP
  respondeu `200` e o container do Commerce V2 iniciou normalmente.

## Upload de imagem pelo MCP — 2026-11-20

- O MCP foi atualizado para `2dc265c` e reconstruído. Foi configurado somente
  na VPS para reutilizar as credenciais S3/R2 já aprovadas no `services-account`;
  nenhum valor de storage foi exibido ou versionado.
- A ferramenta `upload_product_image` é anunciada apenas para clientes que
  declaram suporte à extensão experimental `io.modelcontextprotocol/files`.
  Ela aceita JPEG, PNG e WebP de até 10 MB, valida bytes e dimensões, limita a
  imagem a 20 milhões de pixels, redimensiona o maior lado para 1600 px e salva
  o resultado em WebP no prefixo isolado `mcp/products`.
- Clientes sem suporte continuam usando `thumbnail_url` como fallback. O upload
  exige `mcp.products.write` e OAuth; a verificação sem token respondeu `401`.
- Nenhum arquivo real, produto ou dado de seller foi criado durante a validação.

## Correção de rota de upload — 2026-11-20

- O MCP foi atualizado para `65cd907` e reconstruído. O caminho devolvido ao
  cliente passou a ser relativo ao endpoint MCP, como requer a extensão de
  arquivos. O servidor também aceita a forma absoluta anterior para tolerar
  clientes que resolvam o caminho de modo diferente.
- As duas rotas públicas de upload foram verificadas sem credencial e ambas
  responderam `401`, confirmando que chegam ao serviço e permanecem protegidas
  por OAuth.

## Correção de autorização no Dashboard — 2026-11-20

- O Dashboard de homologação havia sido movido para `main` no commit
  `13aa85e1`, que não contém a página de consentimento OAuth MCP. Isso fazia o
  redirecionamento do Auth para `oauth_mcp_authorize.php` responder `404`.
- Com autorização explícita, somente o `dashboard-seller` foi restaurado para
  `feat/mcp-readonly-service`, commit `4168de3b`; os demais repositórios e
  containers foram mantidos como estavam.
- Uma solicitação OAuth de validação para a URL pública passou a responder
  `302` para `/login.php`, comportamento esperado para seller sem sessão.
