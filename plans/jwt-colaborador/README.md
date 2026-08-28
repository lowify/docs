# JWT para colaborador

## Objetivo

Migrar o login de colaborador para o fluxo centralizado de autenticação, emitindo JWT próprio para essa identidade. O token deve carregar o vendedor ao qual o colaborador está vinculado e as permissões concedidas, para que cada feature decida o acesso antes de executar qualquer ação.

O resultado esperado é que o colaborador passe a ter JWT próprio nas chamadas já integradas ao Gateway, sem remover a sessão nem a whitelist local que ainda protegem páginas e ações executadas diretamente no `dashboard-seller`.

## Estado

Planejamento iniciado em 2026-08-26. Nenhuma mudança de código, migration, rota ou contrato foi implementada por este plano.

## Documentos

1. [Estado atual e lacunas](01_ESTADO_ATUAL.md)
2. [Contrato e modelo de autorização](02_CONTRATO_E_AUTORIZACAO.md)
3. [Plano de implementação e rollout](03_IMPLEMENTACAO_E_ROLLOUT.md)
4. [Casos de aceite e matriz de acesso](04_ACEITE_E_MATRIZ.md)
5. [Tasks executáveis](05_TASKS.md)

## Decisões propostas

| Tema | Proposta |
| --- | --- |
| Identidade do JWT | `sub` é sempre a identidade autenticada: `id_user` para usuário normal e `id` do colaborador para colaborador. |
| Tipo de login | O payload de login passa a exigir `type`, aceitando inicialmente `user` e `collaborator`. |
| Escopo do colaborador | O claim `seller_id` contém `tbl_colaboradores.id_owner`; o consumidor nunca deve aceitar esse valor da query/body para um colaborador. |
| Permissões | O claim `permissions` contém apenas chaves permitidas com valor `true`; a API faz deny-by-default quando a feature não estiver presente. |
| Permissão da conta | `permissao` continua sendo a permissão do owner para compatibilidade, mas não concede poderes ao colaborador. Consumers devem verificar `actor_type` antes de interpretar privilégios administrativos. |
| Renovação | Refresh token pertence ao ator autenticado e, ao renovar, busca novamente o colaborador/owner/permissões no Account. |

## Fluxo alvo

```text
dashboard-seller (login com type=collaborator)
  → edge-gateway
  → edge-public-api
  → services-auth
  → services-account resolve credencial do colaborador
  → services-auth emite JWT de colaborador
  → edge-public-api valida JWT, resolve actor/seller/permissão da feature
  → serviço responsável recebe somente o seller_id efetivo e a ação autorizada
```

## Limites desta primeira entrega

- O CRUD e a tela de colaboradores permanecem no `dashboard-seller`. O Account receberá somente os métodos de leitura/autenticação indispensáveis para login e refresh.
- O conjunto de permission keys atual é preservado; não serão criadas novas permissões nesta fase.
- A autorização fica propositalmente duplicada: o Dashboard mantém a regra para rotas locais e o `edge-public-api` aplica a mesma permission key somente às rotas já chamadas pelo Dashboard via Gateway.
- Rotas locais e endpoints que não passam hoje por Gateway/Public API não fazem parte desta migração.
- Cada colaborador possui exatamente um owner, definido por `tbl_colaboradores.id_owner`. Não há suporte a um colaborador operar para mais de um seller, transferir-se de seller por conta própria ou atuar em nome de outro colaborador.
- Colaborador continua sendo uma entidade própria em `tbl_colaboradores`; ele não será criado nem migrado para `tbl_usuarios`.
