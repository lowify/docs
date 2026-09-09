# Deploy — configuração de limites de saque por vendedor

## Objetivo

Permitir que administradores configurem, na visão administrativa de cada vendedor, um limite diário de saque específico ou a opção **Sem limite**. A configuração passa a ser aplicada tanto no aviso mostrado ao vendedor quanto na validação do pedido de saque.

Quando não houver configuração individual, o comportamento anterior permanece: são usados os limites e as exceções definidos pelo sistema.

## Componentes alterados

| Componente | Branch de deploy | Entrega |
| --- | --- | --- |
| `dashboard-seller` | `feat/seller-withdrawal-limits-config` | Feature `c6c1e03`, atualizada com a `main` no commit `f9243be`. |
| `services-commerce-v2` | `feat/seller-withdrawal-limits-config` | Seed dos limites iniciais por vendedor. |

A branch foi criada a partir de `main` em 24/08/2026 e foi atualizada com a `origin/main` em 09/09/2026. Essa `main` já contém a integração Cielo.

Não há alteração de schema, nova variável de ambiente ou segredo. O seed de dados `20260824150000_seed_user_withdrawal_daily_limits.sql` deve ser executado no banco `lowify`.

## Comportamento incluído

- Na página administrativa do vendedor, usuários com a permissão `admin_sellers_edit` passam a ter a ação **Limites de saque**.
- O modal permite selecionar **Limite customizado** e informar um valor diário positivo em reais, ou selecionar **Sem limite**.
- A opção é armazenada por vendedor em `user_system_vars`, com a chave `withdrawal_daily_limit` e valor numérico ou `unlimited`.
- Em cada solicitação de saque, a configuração individual é consultada antes dos limites legados. O limite diário é reservado no Redis; pedidos que ultrapassem o total do dia são recusados.
- A opção `unlimited` remove o limite diário para aquele vendedor. A ausência de configuração individual preserva as regras, exceções e valores padrão existentes.

## Pré-requisitos

1. Confirmar que o clone de produção do `dashboard-seller` não possui alterações locais.
2. Confirmar acesso de um usuário administrador com a permissão `admin_sellers_edit`.
3. Confirmar que o Redis usado pelo dashboard está saudável, pois ele mantém a reserva acumulada do limite diário.
4. Registrar o commit anterior conhecido e aprovado antes da atualização, para eventual rollback.
5. Confirmar que `migrations/20260824150000_seed_user_withdrawal_daily_limits.sql` está presente no clone de `services-commerce-v2`.
6. Antes de executar o seed, comparar seus valores com `includes/operations/withdrawal_limits.php` do `dashboard-seller`. O SQL precisa refletir exatamente os usuários sem limite e os limites customizados não comentados nesse arquivo. Se houver divergência, corrigir o SQL antes de rodá-lo.

## Sequência de deploy

1. Atualizar o `services-commerce-v2` e executar o seed de limites:

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/seller-withdrawal-limits-config
   git pull --ff-only origin feat/seller-withdrawal-limits-config
   git rev-parse --short HEAD
   ```

   Conferir o conteúdo de `migrations/20260824150000_seed_user_withdrawal_daily_limits.sql` contra `includes/operations/withdrawal_limits.php` do `dashboard-seller` e, estando correto, executar esse arquivo no banco `lowify`, pelo procedimento de migrations aprovado para o ambiente. Ele insere os registros ausentes para a chave `withdrawal_daily_limit` e não substitui configurações já existentes.

2. Atualizar o `dashboard-seller` para a branch da entrega:

   ```bash
   cd /opt/lowify/front/dashboard-seller
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/seller-withdrawal-limits-config
   git pull --ff-only origin feat/seller-withdrawal-limits-config
   git rev-parse --short HEAD
   ```

   O commit exibido deve ser `f9243be` ou um descendente aprovado dessa revisão.

3. O dashboard não requer build de container neste procedimento. Se o ambiente usar cache de opcode, aplicar o procedimento operacional já aprovado para recarregá-lo após a atualização.

## Validação pós-deploy

1. Após executar o seed, consultar `user_system_vars` para a chave `withdrawal_daily_limit` e comparar os valores inseridos com `includes/operations/withdrawal_limits.php`. Confirmar especialmente que os usuários sem limite têm `unlimited` e que os limites customizados ativos estão corretos.
2. Acessar a visão administrativa de um vendedor com um administrador que tenha `admin_sellers_edit`.
3. Em **Gerenciar conta**, abrir **Limites de saque** e salvar um limite customizado de teste, por exemplo `R$ 100,00`.
4. Confirmar que o modal exibe o valor salvo ao ser reaberto e que o vendedor vê o aviso com o novo teto diário nas páginas de saldo, contas e saques.
5. Com uma conta de teste que tenha saldo e conta de saque válidos, solicitar valores que totalizem até o limite configurado. Confirmar que os pedidos são aceitos.
6. Tentar um novo saque que faça o total diário exceder o limite. Resultado esperado: o pedido é recusado e não é criado um saque pendente.
7. Alterar a configuração para **Sem limite**, repetir a tentativa acima e confirmar que a validação diária não bloqueia o pedido por valor acumulado.
8. Para um vendedor sem registro em `user_system_vars.withdrawal_daily_limit`, confirmar que os limites e exceções legados continuam aplicados.
9. Verificar os logs do PHP e do Redis se algum pedido for recusado inesperadamente; não limpar chaves de limite diário durante a validação.

## Rollback

1. Retornar `services-commerce-v2` e `dashboard-seller` aos commits anteriores conhecidos e aprovados. Recarregar o opcode cache do dashboard, se aplicável.
2. Não apagar os registros inseridos pelo seed sem um plano de dados aprovado: eles passam a representar a configuração individual vigente de cada vendedor.
3. Não limpar manualmente as chaves Redis de reserva diária, exceto em incidente com procedimento operacional aprovado. Elas expiram naturalmente e a remoção pode permitir saques acima do teto já consumido no dia.
4. Após o rollback, validar um saque de teste e confirmar que a regra anterior está sendo aplicada.
