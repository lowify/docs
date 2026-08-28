# Casos de aceite e matriz de acesso

## Matriz inicial

| Feature/ação | Permission key | Colaborador autorizado | Sem a key | Administrador/owner |
| --- | --- | --- | --- | --- |
| Resumo do painel | `dashboard` | Usa `seller_id` do token | 403 | Regra atual |
| Listar produtos | `products` | Usa `seller_id` do token | 403 | Regra atual |
| Criar/editar produtos | `products_edit` | Usa `seller_id` do token | 403 | Regra atual |
| Listar vendas | `sales` | Usa `seller_id` do token | 403 | Regra atual |
| Detalhar venda | `sale_detail` | Só dados do `seller_id` do token | 403 | Regra atual + ownership |
| Saldo/extrato | `balance` | Usa `seller_id` do token | 403 | Regra atual |
| Área de membros | `membros` | Usa `seller_id` do token | 403 | Regra atual |
| Order bumps | `order_bumps` | Usa `seller_id` do token | 403 | Regra atual |
| Upsells | `upsells` | Usa `seller_id` do token | 403 | Regra atual |
| Integrações | `integracoes` | Usa `seller_id` do token | 403 | Regra atual |
| Disputas | `disputes` | Usa `seller_id` do token | 403 | Regra atual |
| Gestão de colaboradores, credenciais, 2FA, perfil sensível, saques e rotas admin | nenhuma nesta fase | Negado | 403 | Regra atual |

Esta tabela é o baseline para endpoints que já passam por Gateway/Public API. Cada um desses endpoints deve receber uma linha equivalente antes de ser liberado ao colaborador. Páginas e ações locais permanecem sob a whitelist atual do Dashboard e não exigem migração para a API nesta fase.

## Cenários de aceite

1. Login `type=user` com credenciais válidas continua emitindo os mesmos tokens e claims compatíveis atuais.
2. Login `type=collaborator` válido emite access token e refresh token com `actor_type=collaborator`, `sub/collaborator_id` do colaborador, `seller_id` do owner e somente as permissões concedidas.
3. Credencial inexistente, senha inválida, colaborador inativo ou owner inativo retorna 401 sem revelar qual condição falhou.
4. Um colaborador com `sales` consegue listar apenas as vendas do seu `seller_id`, mesmo que envie outro `seller_id`/`user_id` na requisição.
5. O mesmo colaborador não consegue detalhes de venda sem `sale_detail`, nem uma venda pertencente a outro seller, mesmo que conheça seu identificador.
6. Um colaborador cujo owner tenha `permissao` administrativa não obtém acesso administrativo só por herdar esse claim.
7. Rota não mapeada para collaborator retorna 403; ela nunca segue o comportamento de owner como fallback.
8. Ao alterar permissões, desativar ou excluir o colaborador, o comportamento respeita o SLA de revogação escolhido; refresh posterior sempre falha ou emite claims atualizados conforme o caso.
9. A rotação de refresh token de colaborador não cria token associado a `id_user` nem muda o `seller_id` sem nova autenticação válida.
10. Logs de acesso e auditoria diferenciam colaborador e owner, mantendo correlação com o `seller_id` efetivo.
11. A UI exibe uma mensagem de falta de permissão para 403 e não entra em loop de renovação ou redirecionamento para login.
12. JWT inválido/expirado continua retornando 401 e acionando o fluxo de refresh/login existente, sem ser confundido com falta de permissão.
13. Em uma navegação negada, o Public API responde 403 com `error_code=feature_permission_denied` e `redirect_to` para a primeira página permitida; o Dashboard redireciona sem usar HTTP 3xx.
14. Em chamada dinâmica sob `/api/`, o Public API responde 403 com `success=false`, `data=null` e `error_code=feature_permission_denied`, sem `redirect_to` nem mensagem de UI.

## Testes mínimos por serviço

| Serviço | Cobertura mínima |
| --- | --- |
| `services-account` | Use cases de login user/collaborator, status, senha, owner e atualização de último login. |
| `services-auth` | Contrato do proxy, claims, emissão, rotação e falha de refresh por colaborador revogado. |
| `edge-public-api` | Assinatura JWT, resolver de contexto, guard por feature, imutabilidade de seller scope e 401/403. |
| `dashboard-seller` | Formulário com `type=collaborator`, persistência de tokens, tratamento de 401/403 e visibilidade dos links. |
| Integração | Login → chamada autorizada → tentativa cross-seller → alteração/revogação → refresh. |

## Pontos que exigem confirmação antes de codificar

1. Qual é o tempo máximo aceitável para uma permissão removida ainda valer em um access token já emitido?
2. O colaborador poderá operar saldo/integrações nesta fase exatamente como a whitelist atual permite, ou essas ações exigem uma revisão de risco?
3. O `seller_id` no token é suficiente como snapshot até o refresh, ou a API precisa revalidar vínculo/status em toda request?
4. Há clientes além do `dashboard-seller` que usam o login de colaborador ou dependem de `tbl_colaboradores.token_login`?
5. Confirmar o DDL de `tbl_colaboradores` e os índices existentes com uma credencial de leitura que tenha acesso ao host informado.
