# Deploy — configuração de limites de saque por vendedor

## Objetivo

Permitir que administradores configurem, na visão administrativa de cada vendedor, um limite diário de saque específico ou a opção **Sem limite**. A configuração é aplicada tanto no aviso mostrado ao vendedor quanto na validação do pedido de saque.

O `dashboard-seller` é o único componente desta entrega. Ele lê e grava diretamente no banco `lowify`, na tabela `user_system_vars`, usando a chave `withdrawal_daily_limit`.

Quando não houver configuração individual, o comportamento anterior permanece: são usados os limites e as exceções definidos em `includes/operations/withdrawal_limits.php`.

## Componente alterado

| Componente | Branch de deploy | Entrega |
| --- | --- | --- |
| `dashboard-seller` | `feat/seller-withdrawal-limits-config` | Tela administrativa, persistência direta em `user_system_vars` e validação de saque. |

Não há migration, alteração de schema, nova variável de ambiente, serviço adicional ou rebuild de container nesta entrega.

## Comportamento incluído

- Na página administrativa do vendedor, usuários com a permissão `admin_sellers_edit` têm a ação **Limites de saque**.
- O modal permite selecionar **Limite customizado** e informar um valor diário positivo em reais, ou selecionar **Sem limite**.
- O Dashboard grava `withdrawal_daily_limit` diretamente em `user_system_vars`. Valores numéricos representam o teto diário; `unlimited` remove o teto diário.
- Em cada solicitação de saque, essa configuração é consultada antes dos limites legados. O limite diário é reservado no Redis; pedidos que ultrapassem o total do dia são recusados.
- A ausência de registro individual preserva as regras, exceções e valores padrão existentes.

## Pré-requisitos

1. Confirmar que o clone de produção do `dashboard-seller` não possui alterações locais.
2. Confirmar acesso de um usuário administrador com a permissão `admin_sellers_edit`.
3. Confirmar que o Redis usado pelo Dashboard está saudável, pois ele mantém a reserva acumulada do limite diário.
4. Registrar o commit anterior conhecido e aprovado antes da atualização, para eventual rollback.
5. Antes de executar o SQL abaixo, conferir os valores contra `includes/operations/withdrawal_limits.php` do `dashboard-seller`. Se os arrays de limites ou isenções forem alterados, atualizar o SQL antes de executá-lo.

## SQL de configuração inicial

Executar no banco `lowify` pelo procedimento aprovado. Este comando não substitui configurações individuais já existentes; ele só cria os registros ausentes.

```sql
INSERT INTO user_system_vars (user_id, var_key, var_value)
SELECT source.user_id, 'withdrawal_daily_limit', source.var_value
FROM (
    SELECT 39 AS user_id, 'unlimited' AS var_value
    UNION ALL SELECT 79, 'unlimited'
    UNION ALL SELECT 814, 'unlimited'
    UNION ALL SELECT 1336, 'unlimited'
    UNION ALL SELECT 1100, 'unlimited'
    UNION ALL SELECT 542, 'unlimited'
    UNION ALL SELECT 14, '8000.00'
    UNION ALL SELECT 2200, '6000.00'
    UNION ALL SELECT 11509, '5000.00'
    UNION ALL SELECT 99, '5000.00'
    UNION ALL SELECT 1131, '8000.00'
    UNION ALL SELECT 55, '30000.00'
    UNION ALL SELECT 1818, '3000.00'
    UNION ALL SELECT 164, '3000.00'
    UNION ALL SELECT 299, '10000.00'
    UNION ALL SELECT 10, '3000.00'
    UNION ALL SELECT 284, '8000.00'
    UNION ALL SELECT 8140, '15000.00'
    UNION ALL SELECT 294, '10000.00'
    UNION ALL SELECT 11694, '8000.00'
    UNION ALL SELECT 1925, '12000.00'
    UNION ALL SELECT 412, '8000.00'
    UNION ALL SELECT 1779, '4000.00'
) AS source
WHERE NOT EXISTS (
    SELECT 1
    FROM user_system_vars existing_config
    WHERE existing_config.user_id = source.user_id
      AND existing_config.var_key = 'withdrawal_daily_limit'
);
```

## Sequência de deploy

1. Executar o SQL de configuração inicial acima, após conferir os valores com `includes/operations/withdrawal_limits.php`.
2. Atualizar o `dashboard-seller` para a branch da entrega:

   ```bash
   cd /opt/lowify/front/dashboard-seller
   git status --porcelain=v1
   git fetch origin --prune
   git switch feat/seller-withdrawal-limits-config
   git pull --ff-only origin feat/seller-withdrawal-limits-config
   git rev-parse --short HEAD
   ```

3. O Dashboard não requer rebuild de container. Se o ambiente usar cache de opcode, aplicar o procedimento operacional aprovado para recarregá-lo após a atualização.

## Validação pós-deploy

1. Consultar `user_system_vars` para a chave `withdrawal_daily_limit` e confirmar que os registros criados pelo SQL correspondem aos limites ativos em `includes/operations/withdrawal_limits.php`.
2. Acessar a visão administrativa de um vendedor com um administrador que tenha `admin_sellers_edit`.
3. Em **Gerenciar conta**, abrir **Limites de saque** e salvar um limite customizado de teste, por exemplo `R$ 100,00`.
4. Reabrir o modal e confirmar que o valor salvo está visível.
5. Confirmar que o vendedor vê o aviso com o novo teto diário nas páginas de saldo, contas e saques.
6. Com uma conta de teste que tenha saldo e conta de saque válidos, solicitar valores que totalizem até o limite configurado. Confirmar que os pedidos são aceitos.
7. Tentar um novo saque que faça o total diário exceder o limite. Resultado esperado: o pedido é recusado e não é criado um saque pendente.
8. Alterar a configuração para **Sem limite**, repetir a tentativa acima e confirmar que a validação diária não bloqueia o pedido por valor acumulado.
9. Para um vendedor sem registro em `user_system_vars.withdrawal_daily_limit`, confirmar que os limites e exceções legados continuam aplicados.
10. Verificar os logs do PHP e do Redis se algum pedido for recusado inesperadamente; não limpar chaves de limite diário durante a validação.

## Rollback

1. Retornar somente o `dashboard-seller` ao commit anterior conhecido e aprovado. Recarregar o opcode cache, se aplicável.
2. Não apagar os registros de `user_system_vars` sem um plano de dados aprovado: eles representam a configuração individual vigente de cada vendedor.
3. Não limpar manualmente as chaves Redis de reserva diária, exceto em incidente com procedimento operacional aprovado. Elas expiram naturalmente e a remoção pode permitir saques acima do teto já consumido no dia.
4. Após o rollback, validar um saque de teste e confirmar que a regra anterior está sendo aplicada.
