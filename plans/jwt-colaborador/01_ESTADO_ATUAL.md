# Estado atual e lacunas

## Login atual

O login normal já percorre `dashboard-seller → edge-gateway → edge-public-api → services-auth`. Em `services-auth`, `POST /auth/login` repassa a credencial ao Account, recebe `id_user` e `permissao`, e cria os access/refresh tokens.

O login de colaborador é uma exceção local em `dashboard-seller/login_colaborador_process.php`:

1. consulta diretamente `tbl_colaboradores` por e-mail;
2. valida `status` e `senha` no próprio Dashboard;
3. busca o owner em `tbl_usuarios`;
4. grava `ultimo_login` e um novo `token_login` do colaborador;
5. cria a sessão PHP como se fosse o owner (`user_id`, `permissao` e `login_token` do owner) e adiciona dados auxiliares de colaborador à sessão.

Em cada request, `dashboard-seller/includes/init.php` volta a validar `token_login` em `tbl_colaboradores`, carrega o owner como `currentUser` e aplica uma whitelist de arquivos PHP com base em `$_SESSION['colaborador_permissoes']`.

## Consequências

| Problema | Impacto |
| --- | --- |
| Identidade mascarada | Serviços remotos recebem, quando recebem autenticação, o contexto do owner e não sabem que a ação veio de um colaborador. |
| Autorização apenas local | A whitelist do Dashboard não protege endpoints já expostos por `edge-public-api`; uma chamada que use JWT do owner pode contornar o limite funcional. |
| Credencial fora do Account/Auth | Regras de senha, status, auditoria, bloqueio e refresh não são centralizadas. |
| Revogação incompleta | Mudança de permissões/status só alcança a sessão local; um eventual token emitido para o owner não representa o colaborador. |
| Escopo manipulável | Muitos endpoints resolvem o vendedor pelo `sub` do JWT ou aceitam parâmetros de vendedor; não existe regra única para fixar `seller_id` no owner do colaborador. |

## Componentes já reutilizáveis

- `services-auth/app/Controller/AuthController.php` recebe o login e emite tokens via `JwtService`.
- `services-auth/app/Service/AccountService.php` já encapsula `POST /auth/login` e `GET /auth/user`.
- `services-account/app/Application/UseCase/Auth/LoginUseCase.php` já concentra a validação de senha do usuário normal.
- `edge-public-api/app/Http/Middleware/JwtAuthMiddleware.php` valida assinatura, validade e disponibiliza `jwt_payload`.
- `edge-public-api/app/Services/JwtPayloadService.php` já é o ponto comum para resolver `sub` e `permissao`.
- `dashboard-seller/app/services/GatewayJwtClient.php` já armazena access token e refresh token e os envia a cada chamada ao Gateway.

## Inventário inicial de permissões existentes

O CRUD local armazena as seguintes chaves em `tbl_colaboradores.permissoes`: `dashboard`, `products`, `products_edit`, `sales`, `sale_detail`, `balance`, `membros`, `order_bumps`, `upsells`, `integracoes` e `disputes`.

Elas hoje são mapeadas para páginas, e não para uma política de API. Nesta entrega, o mapeamento será feito somente para cada endpoint/ação que já é chamado pelo `dashboard-seller` por `GatewayJwtClient → edge-gateway → edge-public-api`. A whitelist local não será removida: ela continuará protegendo páginas e ações locais. Nas rotas remotas incluídas, a API nega o acesso quando não houver mapeamento.

## Estrutura atual observada

Pelos fluxos do `dashboard-seller`, `tbl_colaboradores` utiliza pelo menos os campos abaixo:

| Campo | Uso atual |
| --- | --- |
| `id` | Identidade do colaborador. |
| `id_owner` | `id_user` do vendedor/owner. |
| `nome`, `email` | Identificação e login por e-mail. |
| `senha` | Hash validado no login legado. |
| `permissoes` | JSON com as permission keys existentes. |
| `status` | Habilita/desabilita o acesso. |
| `ultimo_login` | Atualizado após login válido. |
| `token_login` | Token de sessão exclusivo do fluxo local legado. |
| `created_at` | Ordenação/exibição no CRUD. |

O DDL remoto ainda precisa ser confirmado antes de qualquer migration. A consulta de leitura ao host informado foi recusada para `root`, inclusive com a credencial local disponível; nenhum dado de tabela foi lido ou alterado. Esta entrega não pressupõe alteração estrutural na tabela: o Account apenas precisará de acesso de leitura e da atualização controlada de `ultimo_login`.
