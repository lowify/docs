# Plano de implementação e rollout

## Fase 0 — decisões e inventário

1. Confirmar o enum final de `type` e os nomes definitivos dos claims.
2. Definir o SLA de revogação e escolher access token curto ou revogação imediata.
3. Montar uma tabela endpoint → permission key somente para as chamadas atuais do Dashboard que passam por `GatewayJwtClient → edge-gateway → edge-public-api`, incluindo operações de escrita.
4. Classificar as rotas remotas administrativas, financeiras, de credenciais, perfil, 2FA e gestão de colaboradores como negadas por padrão quando chamadas por colaborador.
5. Manter todos os endpoints e ações locais fora desta migração, preservando a whitelist já existente no Dashboard.

## Fase 1 — Account: autenticação do colaborador

1. Criar modelo/repositório de leitura de `tbl_colaboradores` no `services-account`, sem endpoints ou casos de uso de CRUD.
2. Criar `LoginCollaboratorUseCase`, validando e-mail, senha, status do colaborador e status do owner.
3. Retornar `collaborator_id`, `seller_id`, dados mínimos do owner e permissions normalizadas; nunca expor `senha`.
4. Atualizar `ultimo_login` somente após credencial válida; `token_login` não participa do novo fluxo.
5. Alterar o controller `/auth/login` para validar/delegar por `type`.
6. Criar endpoint interno de resolução de ator para refresh, se o contrato atual de `/auth/user` não puder representar colaborador.
7. Cobrir com testes de use case e controller.

## Fase 2 — Auth: emissão e refresh

1. Propagar `type` de `services-auth` para o Account com validação de allowlist.
2. Fazer `AccountService` interpretar a resposta tipada sem perder os erros de autenticação.
3. Evoluir `JwtService` e o armazenamento de refresh para emitir/rotacionar token por ator.
4. Criar os claims de colaborador descritos no contrato e manter claims atuais do usuário normal.
5. Atualizar o callback de refresh para resolver novamente o ator correto, inclusive suas permissões e `seller_id`.
6. Definir se o tracking de login em `LoginAccessService` deve registrar colaborador, owner ou ambos; a recomendação é registrar o ator e o seller em campos distintos para auditoria.
7. Criar testes de emissão, refresh, revogação e compatibilidade do login `user`.

## Fase 3 — Edge/Public API: autorização centralizada

1. Normalizar no controller de login a ausência de `type` para `user`, antes de encaminhar a requisição ao Auth; não concentrar esse fallback no Gateway.
2. Estender `JwtPayloadService` ou criar `ActorContextResolver` para entregar `{actor_type, actor_id, seller_id, permissions}`.
3. Criar middleware/guard reutilizável que receba a permission key requerida pela rota/ação.
4. Definir o header `X-Dashboard-Request-Type` entre Dashboard e Gateway/Public API para distinguir `navigation` de `api`, sem confiar em valor enviado pelo navegador externo.
5. Para `navigation`, resolver e retornar `redirect_to` para uma rota já permitida; para `api`, retornar somente `success=false`, `data=null` e `error_code`.
6. Atualizar controllers para usar o `seller_id` efetivo do contexto, nunca o `sub` diretamente quando houver colaborador.
7. Aplicar deny-by-default às rotas remotas incluídas: ausência de mapeamento para colaborador é 403.
8. Revisar endpoints que hoje usam somente `permissao`, pois o token de colaborador contém a permissão do owner por compatibilidade.
9. Propagar apenas contexto já resolvido aos serviços internos e impedir sobrescrita por parâmetros recebidos do Dashboard.
10. Registrar logs/auditoria com `actor_type`, `actor_id`, `seller_id`, feature e decisão de acesso; não registrar token nem senha.

## Fase 4 — Dashboard: adoção do JWT

1. Alterar `GatewayJwtClient::login()` para receber/enviar `type`.
2. Fazer `login_colaborador_process.php` chamar o Gateway para autenticar e obter JWT, preservando a criação da sessão/token local necessária às páginas que ainda não passam pelo Gateway.
3. Persistir os tokens administrados por `GatewayJwtClient` e manter os dados de sessão atuais para a autorização local; o JWT será a autoridade adicional das chamadas remotas incluídas.
4. Usar `permissions` da resposta/JWT para esconder links, mas manter a API como autoridade final.
5. Manter a whitelist local como regra definitiva para páginas e ações locais. Para cada rota remota incluída, aplicar a mesma permission key no `edge-public-api` como segunda barreira.
6. Manter a geração/validação de `tbl_colaboradores.token_login` e os dados de sessão do fluxo local nesta fase; sua remoção fica fora do escopo.

## Fase 5 — rollout seguro

1. Publicar Account e Auth de forma retrocompatível: login `user` sem mudança de comportamento.
2. Publicar a validação de novos claims no Edge sem ativar o login de colaborador para todos.
3. Habilitar uma feature flag de emissão JWT de colaborador para usuários internos/piloto.
4. Monitorar 401/403, falhas de refresh e divergências entre whitelist local e guard da API.
5. Migrar progressivamente colaboradores existentes; sessões locais continuam válidas e protegidas pela whitelist atual.
6. Após estabilização, tornar `type` obrigatório para os clientes que usam o Gateway. O login local e seu caminho legado permanecem até que um projeto futuro os substitua explicitamente.

## Rollback

O rollback deve desativar somente a emissão JWT de colaborador para chamadas remotas, sem alterar a emissão de JWT de usuários normais nem o fluxo local existente. Migrations de refresh devem ser aditivas e permanecer compatíveis enquanto houver tokens anteriores válidos.
