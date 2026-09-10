# Deploy — edição administrativa de produto no Commerce V2

## Objetivo

Corrigir a edição de produtos de outros sellers por administradores no Dashboard Seller. Antes desta entrega, o Dashboard substituía o dono do produto pelo ID do administrador antes de chamar o Commerce V2; por isso, a busca por `id_produto + id_usuario` retornava `product_not_found`.

A correção preserva o seller dono do produto no payload e mantém o ator autenticado separado no fluxo de auditoria já existente.

## Componentes alterados

| Componente | Branch de deploy | Entrega |
| --- | --- | --- |
| `edge-public-api` | `hotfix/admin-product-edit-commerce-v2` | Restringe a seleção de seller-alvo para edição administrativa às permissões 1 e 2. |
| `dashboard-seller` | `hotfix/admin-product-edit-commerce-v2` | Preserva o seller dono do produto ao normalizar e encaminhar a edição ao Commerce V2. |

O `services-commerce-v2` não possui alteração nesta entrega. Ele já busca e atualiza o produto por `id_produto + user_id`, preservando a propriedade do produto.

Não há migration, alteração de schema, variável de ambiente ou mudança de configuração.

## Comportamento incluído

```text
Admin (permissão 1 ou 2)
  -> Dashboard preserva user_id do seller dono
  -> Gateway / Public API valida o JWT
  -> Commerce V2 atualiza o produto do seller alvo
  -> change-log registra o admin autenticado como ator
```

- Admins com permissões 1 e 2 podem editar produtos de sellers distintos.
- Sellers comuns e colaboradores continuam restritos ao seller resolvido pelo JWT e pelo contexto de colaborador; qualquer `user_id` enviado pelo navegador é ignorado.
- A permissão 4 não pode editar produto de outro seller, em conformidade com a permissão de tela `admin_product_edit` do Dashboard.
- O Commerce V2 não altera `id_usuario` durante a edição.
- Após uma edição bem-sucedida, o Dashboard envia o diff para o endpoint de change-log. A Public API resolve o ator pelo JWT e o Commerce V2 grava o ator em `product_changes_log`.

## Sequência de deploy

Atualizar primeiro a Public API e depois o Dashboard. Antes de cada etapa, confirmar que o clone correspondente não possui alterações locais.

### Public API

```bash
cd /opt/lowify/edge/edge-public-api
git fetch origin --prune
git switch hotfix/admin-product-edit-commerce-v2
git pull --ff-only origin hotfix/admin-product-edit-commerce-v2
docker compose up -d --build edge-public-api
docker compose ps
```

Confirmar que o serviço iniciou sem erro:

```bash
docker compose logs --tail=200 edge-public-api
```

### Dashboard Seller

```bash
cd /opt/lowify/front/dashboard-seller
git fetch origin --prune
git switch hotfix/admin-product-edit-commerce-v2
git pull --ff-only origin hotfix/admin-product-edit-commerce-v2
```

O Dashboard não requer rebuild de container. Caso o ambiente use cache de opcode, aplicar o procedimento operacional aprovado para recarregá-lo.

## Validação pós-deploy

1. Acessar o Dashboard com uma conta administrativa de permissão 1 ou 2.
2. Abrir um produto que pertença a outro seller e alterar um campo não estrutural, como o título.
3. Confirmar que a atualização é concluída e que `tbl_produtos.id_usuario` permanece associado ao seller original.
4. Reabrir o produto e confirmar que o novo valor foi persistido.
5. Consultar a timeline de alterações do produto e confirmar que o ator é o administrador que executou a edição.
6. Com uma conta seller, tentar informar o `user_id` de outro seller em uma requisição de atualização. Confirmar que a alteração não ocorre.
7. Com uma conta de permissão 4, tentar editar produto de outro seller. Resultado esperado: `product_not_found` ou negação de acesso, sem alteração do produto.

## Rollback

1. Retornar `dashboard-seller` e `edge-public-api` às revisões anteriores aprovadas e aplicar o rebuild da Public API.
2. Recarregar o cache de opcode do Dashboard, se aplicável.
3. Não há rollback de banco: a entrega não possui migration nem altera a propriedade dos produtos.
4. Preservar os registros de `product_changes_log`, pois eles são evidência de auditoria das edições realizadas.
