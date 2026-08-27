# Deploy parcial — JWT para colaborador

## Objetivo

Publicar, em ambiente de teste, a primeira parte da feature de autenticação JWT para colaboradores:

- `services-account` resolve o colaborador e expõe o contexto de autenticação;
- `services-auth` emite e renova tokens preservando o ator, o `seller_id` e o tipo de ator;
- a migration registra o contexto do ator nos refresh tokens.

Este deploy não altera o CRUD de colaboradores nem a validação de permissões no `public-api`.

## Componentes publicados

| Componente | Branch | Commit |
|---|---|---|
| `services-account` | `feat/jwt-colaborador` | `7f7efae` |
| `services-auth` | `feat/jwt-colaborador` | `ae62aa4` |

Os repositórios de produção tinham estados locais que não devem ser sobrescritos. Por isso, a publicação foi feita em worktrees isolados na VPS:

- `/root/opt/lowify/services/.deploy/services-account-jwt`
- `/root/opt/lowify/services/.deploy/services-auth-jwt`

## Banco de dados

Migration aplicada no banco do `services-auth`:

```text
2026_08_26_000006_add_actor_context_to_refresh_tokens_table
```

Ela adiciona `actor_type` e `actor_id` a `refresh_tokens`, permitindo que refresh tokens preservem o ator que os originou.

## Ajustes específicos do ambiente de teste

O checkout isolado do Auth continha a migration histórica
`2026_03_27_000004_finalize_auth_access_tracking_schema.php`, que falha nessa VPS devido à ausência da coluna `dim_locations.address_ip`. A migration foi removida **somente do worktree isolado**, sem alteração de branch, commit ou checkout original.

Também foi mantida no worktree isolado a configuração de Supervisor já usada pelo checkout original da VPS: o programa `worker` foi omitido porque chama `queue:consume`, comando que não existe neste serviço. Sem isso, o container permanecia em ciclo de reinício do worker, embora a API estivesse disponível.

## Validações realizadas

- Containers ativos:
  - `services-account-services-account-1`
  - `services-auth-jwt-services-auth-1`
- Migration JWT confirmada como aplicada (`batch 10`).
- `GET /` no Auth retornou `200`.
- Requisição do container Account para `http://services_auth:9501/` retornou `200`.
- Após o ajuste do Supervisor, o container Auth ficou com `RestartCount: 0`.
- Capacidade da VPS antes do deploy: aproximadamente 133 GB livres em disco, 6% de inodes usados e cerca de 5,9 GB de memória disponível.

## Teste manual de colaborador

Foi criado o colaborador de teste `id 44`, vinculado ao owner `id_user 3632`, com todas as chaves de permissão já existentes. O e-mail e a senha temporária foram definidos exclusivamente para o ambiente de teste e não são registrados neste documento.

Foram validados diretamente no Auth:

1. `POST /auth/login` com `type: collaborator` retornou sucesso.
2. O contexto retornado contém `actor_type: collaborator`, `seller_id: 3632`, `collaborator_id: 44` e a lista normalizada das permissões.
3. Os claims do access token preservam o mesmo ator, owner e permissões.
4. `POST /auth/refresh` retornou sucesso e manteve os mesmos claims de colaborador.
5. `tbl_colaboradores.ultimo_login` foi atualizado pelo Account durante o login.

Tokens e refresh tokens não foram persistidos na documentação.

## Regressão — login do owner

O login normal do owner de teste também foi validado no Auth, seguido de refresh. Ambos retornaram sucesso e preservaram o contrato anterior:

- `actor_type: user`;
- `seller_id: 3632`;
- `sub: 3632`;
- `permissao: 3`.

Isso confirma o fallback do fluxo já existente para usuários durante a primeira etapa da migration.

## Pendências para a próxima etapa

1. Executar login real de colaborador com credenciais de teste e conferir os claims do JWT.
2. Implementar no `public-api` a leitura do novo contexto, com fallback para tokens de usuário existentes.
3. Aplicar as regras de permissão e `seller_id` nas rotas já integradas entre Dashboard, Gateway e Public API.
4. Definir o procedimento permanente de deploy após a migração ser validada, evitando depender dos worktrees isolados.

## Rollback

1. Parar o container `services-auth-jwt-services-auth-1`.
2. Subir novamente o container original `services-auth-services-auth-1` a partir do checkout anterior.
3. Para o Account, recriar o serviço usando o checkout anterior, se necessário.

A migration adiciona colunas e é compatível com o fluxo anterior; por isso, o rollback da aplicação não exige rollback imediato de banco.
