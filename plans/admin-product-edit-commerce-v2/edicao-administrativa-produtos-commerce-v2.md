# Plano — edição administrativa de produto no Commerce V2

> Status: proposta para implementação
> Criado em: 2026-09-10
> Escopo: `dashboard-seller`, `edge-public-api` e `services-commerce-v2`

## Problema

Ao editar, pelo Dashboard Seller, um produto pertencente a outro seller, um administrador recebe “Produto não encontrado ou sem permissão.”

O problema não é a autorização inicial da tela. O produto é carregado pelo dashboard para administradores, mas o `PATCH` do Commerce V2 passa a usar o ID do administrador como se fosse o dono do produto.

Fluxo atual:

```text
Admin -> dashboard-seller -> PATCH /products/{produto}
      -> edge-public-api -> services-commerce-v2
```

1. O dashboard define `user_id` como o ID do usuário logado, inclusive quando ele é admin.
2. O Public API reconhece o JWT administrativo, mas preserva o `user_id` recebido como o usuário da requisição.
3. O Commerce V2 consulta o produto por `id_produto + id_usuario`.
4. Como `id_usuario` é o ID do admin, não o ID do seller dono, a consulta não encontra o produto e retorna `product_not_found` (HTTP 404).

## Objetivo

Permitir que administradores autorizados editem produtos de sellers sem permitir que o dashboard se autoatribua privilégio administrativo e sem perder a rastreabilidade de quem realizou a alteração.

## Solução recomendada

Manter a rota atual `PATCH /products/{product_id}` e separar, no contrato interno, o dono do produto do ator que executa a ação.

| Campo | Origem confiável | Finalidade |
| --- | --- | --- |
| `user_id` | Dashboard, validado pelo Public API | ID do seller dono do produto-alvo |
| `actor_user_id` | JWT, resolvido pelo Public API | ID de quem solicitou a atualização |
| `actor_is_admin` | JWT, resolvido exclusivamente pelo Public API | Autoriza a edição de produto de outro seller |
| `actor_permission` | JWT, resolvido pelo Public API | Auditoria e política detalhada, se necessária |

`actor_is_admin` não pode ser aceito do navegador. O Public API deve gerá-lo após validar o JWT. A autorização do Commerce V2 deve confiar somente nesse contexto encaminhado internamente pelo Public API, protegido pelo contrato de serviço interno já existente.

## Fluxo proposto

```text
Admin (JWT permissao 1, 2 ou 4)
  -> dashboard envia product_id e user_id do seller
  -> public-api valida JWT e injeta actor_user_id / actor_is_admin
  -> commerce-v2 verifica ownership ou contexto administrativo
  -> atualiza produto do seller e registra o ator
```

### Dashboard Seller

- Ao editar um produto existente, enviar `user_id` igual a `id_usuario` do produto carregado.
- Não substituir esse valor pelo ID do usuário logado.
- Para um seller comum, o valor ainda será o próprio ID; o Public API continuará sendo a fonte de autorização.
- Alinhar a permissão de tela `admin_product_edit`: hoje ela contempla apenas permissões 1 e 2. A inclusão da permissão 4 é uma decisão de produto e deve ser explícita, não um efeito colateral da regra de backend.

### Edge Public API

- Resolver o ator pelo JWT (`sub`) e determinar administração pelas permissões 1, 2 e 4.
- Para seller não-admin ou colaborador, ignorar qualquer `user_id` fornecido e usar o seller resolvido do JWT/contexto.
- Para admin, aceitar `user_id` somente como o seller-alvo e encaminhar também:

```json
{
  "user_id": 123,
  "actor_user_id": 9,
  "actor_is_admin": true,
  "actor_permission": 1
}
```

- Não é necessário criar uma rota administrativa nova. Uma rota como `PATCH /admin/products/{product_id}` é alternativa válida apenas se houver interesse em expor uma política ou auditoria administrativa totalmente separada.

### Commerce V2

- Receber e validar o contexto de ator no request interno.
- Se `actor_is_admin` for `false`, localizar e atualizar com `id_produto + user_id`.
- Se `actor_is_admin` for `true`, localizar e atualizar por `id_produto`, sem trocar a propriedade do produto.
- Manter `user_id` como o dono do produto no resultado e em operações subsequentes, como criação/atualização de short link.
- Registrar `actor_user_id` e `actor_permission` no log de alterações. Se a tabela atual não suportar esses campos, criar migration nova; não alterar migrations já existentes.

## Critérios de aceite

1. Seller só consegue atualizar produto próprio; tentar informar outro `user_id` não amplia seu acesso.
2. Colaborador continua restrito ao seller definido no respectivo contexto.
3. Admin com permissão autorizada atualiza produto de qualquer seller existente.
4. Admin não consegue atualizar produto inexistente e recebe `product_not_found`.
5. A propriedade (`id_usuario`) do produto não é alterada pela edição administrativa.
6. O log identifica o admin responsável pela alteração e o seller dono do produto.
7. A permissão 4 só edita produtos se a regra de produto for alterada explicitamente para incluí-la, tanto na interface quanto no backend.

## Testes recomendados

- Teste unitário do resolvedor de identidade no Public API: seller, admin 1, 2, 4 e colaborador.
- Teste de integração Public API -> Commerce V2 para atualização própria e atualização administrativa de produto de seller distinto.
- Teste de negação: seller envia `user_id` de outro seller e recebe resposta de acesso negado ou produto não encontrado, conforme contrato adotado.
- Teste de auditoria: confirmar ator e dono persistidos no log.

Antes do deploy, vale executar um teste de compatibilidade em homologação para esse fluxo, usando um produto de teste e revertendo o campo alterado ao final.

## Referências no código

- `dashboard-seller/api/product/update.php`: sobrescreve `user_id` com o usuário logado no fluxo V2.
- `edge-public-api/app/Http/Controllers/ProductV2Controller.php`: resolve `user_id` para admins a partir do payload e o encaminha ao Commerce V2.
- `edge-public-api/app/Services/JwtPayloadService.php`: identifica admin pelas permissões 1, 2 e 4.
- `services-commerce-v2/app/Application/UseCase/Product/UpdateProductUseCase.php`: usa `user_id` para buscar e atualizar o produto.
- `services-commerce-v2/app/Domain/Product/Repository/ProductRepository.php`: disponibiliza buscas por produto e dono e a verificação `userOwnsOrIsAdmin()`.
- `dashboard-seller/includes/user_functions.php`: `admin_product_edit` está mapeada para permissões 1 e 2.
