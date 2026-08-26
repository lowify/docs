# Contrato e modelo de autorização

## Login

`POST /auth/login` passa a aceitar o campo obrigatório `type`.

```json
{
  "login": "colaborador@exemplo.com",
  "password": "senha",
  "type": "collaborator"
}
```

Valores iniciais permitidos:

- `user`: login em `tbl_usuarios` (fluxo atual);
- `collaborator`: login em `tbl_colaboradores`.

Para preservar clientes existentes durante a migração, o `edge-public-api` deve normalizar a ausência de `type` para `user` antes de encaminhar o payload ao `services-auth`. Assim, o contrato externo continua compatível para clientes existentes e o Auth recebe sempre um tipo explícito. A obrigatoriedade definitiva no contrato público fica para a etapa de corte, depois de todos os clientes conhecidos terem sido atualizados.

O Account é a fonte de verdade da validação. Deve expor/estender `POST /auth/login` para delegar pelo `type` a um caso de uso específico de colaborador. Esse caso de uso lê `tbl_colaboradores`, valida a senha, o status e o owner, e retorna a identidade completa que o Auth precisa para assinar o token; não deve devolver hash, senha ou token de sessão local. Não fará CRUD de colaboradores.

## Claims

### Usuário normal

```json
{
  "sub": "1417",
  "actor_type": "user",
  "seller_id": 1417,
  "permissao": 3
}
```

### Colaborador

```json
{
  "sub": "93",
  "actor_type": "collaborator",
  "collaborator_id": 93,
  "seller_id": 1417,
  "permissao": 3,
  "permissions": ["sales", "sale_detail"]
}
```

Os claims padrão (`iss`, `iat`, `nbf`, `exp`, `jti`) permanecem obrigatórios. `permissao` no token do colaborador descreve a conta dona apenas para compatibilidade de leitura; ele não transforma o colaborador em admin nem libera endpoints administrativos.

O payload de resposta pode incluir uma representação não sensível do ator, por exemplo `user.actor_type`, `user.seller_id`, `user.collaborator_id` e `user.permissions`, para o Dashboard compor a interface sem inferir a identidade do owner.

## Resolução de acesso na API

Criar em `edge-public-api` um resolvedor único, preferencialmente sobre `JwtPayloadService`, com estas responsabilidades:

1. identificar `actor_type`;
2. resolver o `seller_id` efetivo;
3. para colaborador, ignorar `seller_id`, `user_id`, `id_user` ou equivalentes enviados pelo cliente;
4. exigir a permission key da feature/ação;
5. produzir resposta padronizada de acesso negado;
6. expor contexto mínimo e já autorizado ao controller/serviço interno.

Contrato de falha proposto:

| Situação | HTTP | Código/mensagem |
| --- | --- | --- |
| JWT inválido, expirado ou ator removido | 401 | `unauthenticated` |
| Token de colaborador sem claim estrutural válido | 401 | `invalid_actor_context` |
| Colaborador sem permissão para a feature | 403 | `feature_permission_denied` |
| Tentativa de atuar em seller diferente | 403 | `seller_scope_denied` |

Uma busca no código atual não encontrou uso de `feature_permission_denied`; ele é reservado por este plano para o novo guard. O status HTTP permanece `403`, que já é usado pelo Dashboard para acesso negado.

### Resposta de acesso negado

O guard identifica se a chamada representa uma navegação de página ou uma chamada dinâmica do Dashboard. Essa informação deve ser encaminhada pelo Dashboard em um header interno explícito (por exemplo, `X-Dashboard-Request-Type: navigation|api`), pois o caminho no `edge-public-api` não preserva necessariamente a rota original do Dashboard.

Para navegação (`navigation`), retornar `403` com um destino seguro que já esteja liberado ao colaborador. O destino é resolvido por uma tabela fixa e deny-by-default, usando a primeira permission key presente na ordem atual do Dashboard (`dashboard`, `products`, `sales`, `membros`, `order_bumps`, `upsells`, `integracoes`, `balance`, `disputes`). Exemplo:

```json
{
  "success": false,
  "data": null,
  "error_code": "feature_permission_denied",
  "redirect_to": "/sales"
}
```

O Dashboard recebe `redirect_to` e redireciona o navegador. A API não deve usar redirecionamento HTTP 3xx, porque ela é chamada pelo Dashboard como cliente HTTP.

Para chamadas dinâmicas sob `/api/` (`api`), retornar `403` sem mensagem de UI e sem destino:

```json
{
  "success": false,
  "data": null,
  "error_code": "feature_permission_denied"
}
```

O consumidor da chamada dinâmica não redireciona automaticamente; pode encerrar silenciosamente ou tratar o código no contexto da própria tela. Em ambos os formatos, não revelar seller, recurso, permission key ou configuração interna.

## Regra de escopo

Para um colaborador, todo endpoint que opera dados de vendedor deve usar exclusivamente o `seller_id` do JWT. Esse valor é o `id_owner` resolvido no momento da autenticação/refresh. Nunca deve ser aceito da URL, query, body ou sessão PHP.

Administradores preservam a regra atual de seleção explícita de vendedor quando a feature a permitir. Usuário normal não administrador usa seu próprio `sub` como seller. A implementação deve tornar essa diferença explícita para que `permissao: 3` do owner não seja interpretada como autorização do colaborador.

## Refresh e revogação

O registro de refresh token deve distinguir ator/subject para evitar que o refresh de um colaborador seja tratado como `id_user`. Proposta: acrescentar `actor_type` e `actor_id` a `refresh_tokens` (ou usar uma tabela/colunas equivalentes) e manter `seller_id` como contexto resolvido, não como autoridade persistida.

No refresh, o Auth chama o Account para revalidar: colaborador existe, está ativo, owner está ativo e as permissões atuais. Em seguida revoga o refresh token anterior e emite novo access/refresh token com claims atualizados. Falha nessa validação deve invalidar a sessão.

Para revogação imediata de mudanças sensíveis (desativar, remover ou reduzir permissões), definir uma destas estratégias antes da implementação:

- access token curto e revogação efetiva no próximo refresh; ou
- `token_version`/lista de revogação consultada pela API em cada request.

A decisão depende do tempo máximo aceitável de permanência de uma permissão removida; ela ainda está em aberto.
