# Deploy — configuração de limites de saque por vendedor

## Objetivo

Permitir que administradores configurem, na visão administrativa de cada vendedor, um limite diário de saque específico, o **Limite padrão** global ou a opção **Sem limite**. A configuração é aplicada tanto no aviso mostrado ao vendedor quanto na validação do pedido de saque.

O `dashboard-seller` é o único componente desta entrega. Ele lê e grava diretamente no banco `lowify`, nas tabelas `user_system_vars` (chave `withdrawal_daily_limit` por vendedor) e `system_vars` (chave global `withdrawal_daily_limit_default`).

Quando não houver configuração individual, exceção ou limite customizado legado, é aplicado o limite global definido em `system_vars`.

## Componente alterado

| Componente | Branch de deploy | Entrega |
| --- | --- | --- |
| `dashboard-seller` | `feat/seller-withdrawal-limits-config` | Tela administrativa, persistência direta em `user_system_vars` e `system_vars`, e validação de saque. |

Não há migration, alteração de schema, nova variável de ambiente, serviço adicional ou rebuild de container nesta entrega. Há uma nova **variável de configuração no banco**: `system_vars.withdrawal_daily_limit_default`.

## Comportamento incluído

- Na página administrativa do vendedor, usuários com a permissão `admin_sellers_edit` têm a ação **Limites de saque**.
- O modal permite selecionar **Limite padrão**, **Limite customizado** e informar um valor diário positivo em reais, ou selecionar **Sem limite**.
- O Dashboard grava `withdrawal_daily_limit` diretamente em `user_system_vars`. O valor `default` aplica o limite global; valores numéricos representam o teto individual; `unlimited` remove o teto diário.
- O limite global é lido de `system_vars.withdrawal_daily_limit_default`. Se a chave estiver ausente, inválida ou não positiva, o código usa o fallback de `R$ 3.000,00`.
- Em cada solicitação de saque, essa configuração é consultada antes dos limites legados. O limite diário é reservado no Redis; pedidos que ultrapassem o total do dia são recusados.
- A ausência de registro individual preserva as exceções e os valores customizados legados; os demais vendedores passam a usar o limite global.

## SQL de configuração inicial

Executar no banco `lowify` pelo procedimento aprovado. O primeiro comando cria a configuração global apenas se ela não existir; o segundo não substitui configurações individuais já existentes, apenas cria os registros ausentes.

```sql
INSERT INTO system_vars (var_key, var_value)
VALUES ('withdrawal_daily_limit_default', '3000.00')
ON DUPLICATE KEY UPDATE var_value = var_value;

INSERT INTO user_system_vars (user_id, var_key, var_value)
SELECT source.user_id, 'withdrawal_daily_limit', source.var_value
FROM (
    SELECT 39 AS user_id, 'unlimited' AS var_value
    UNION ALL SELECT 79, 'unlimited'
    UNION ALL SELECT 814, 'unlimited'
    UNION ALL SELECT 1336, 'unlimited'
    UNION ALL SELECT 1100, 'unlimited'
    UNION ALL SELECT 542, 'unlimited'
    UNION ALL SELECT 14, '3000.00'
    UNION ALL SELECT 2200, '6000.00'
    UNION ALL SELECT 11509, '5000.00'
    UNION ALL SELECT 99, '5000.00'
    UNION ALL SELECT 1131, '5000.00'
    UNION ALL SELECT 55, '30000.00'
    UNION ALL SELECT 1818, '3000.00'
    UNION ALL SELECT 164, '3000.00'
    UNION ALL SELECT 299, '6000.00'
    UNION ALL SELECT 10, '3000.00'
    UNION ALL SELECT 284, '8000.00'
    UNION ALL SELECT 8140, '15000.00'
    UNION ALL SELECT 294, '10000.00'
    UNION ALL SELECT 11694, '4000.00'
    UNION ALL SELECT 9270, '3000.00'
    UNION ALL SELECT 1925, '20000.00'
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

1. Executar o SQL de configuração inicial acima.
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

1. Consultar `system_vars` para a chave `withdrawal_daily_limit_default` e confirmar o valor global aprovado. Consultar `user_system_vars` para `withdrawal_daily_limit` e confirmar que os registros criados pelo SQL correspondem aos limites individuais ativos em `includes/operations/withdrawal_limits.php`.
2. Acessar a visão administrativa de um vendedor com um administrador que tenha `admin_sellers_edit`.
3. Em **Configurações administrativas** > **Pagamentos** > **Saques**, confirmar que o campo **Limite padrão diário** exibe o valor global e salvá-lo sem alteração. O valor deve permanecer visível ao recarregar a página.
4. Em **Gerenciar conta**, abrir **Limites de saque**, selecionar **Limite customizado** e salvar um limite de teste, por exemplo `R$ 100,00`.
5. Reabrir o modal e confirmar que o valor salvo está visível. Em seguida, selecionar **Limite padrão**, salvar e confirmar que o valor exibido corresponde ao limite global.
6. Confirmar que o vendedor vê o aviso com o teto diário efetivo nas páginas de saldo, contas e saques.
7. Com uma conta de teste que tenha saldo e conta de saque válidos, solicitar valores que totalizem até o limite configurado. Confirmar que os pedidos são aceitos.
8. Tentar um novo saque que faça o total diário exceder o limite. Resultado esperado: o pedido é recusado e não é criado um saque pendente.
9. Alterar a configuração para **Sem limite**, repetir a tentativa acima e confirmar que a validação diária não bloqueia o pedido por valor acumulado.
10. Para um vendedor sem registro em `user_system_vars.withdrawal_daily_limit`, confirmar que ele usa o limite global, exceto quando possuir uma exceção ou valor customizado legado.
11. Verificar os logs do PHP e do Redis se algum pedido for recusado inesperadamente; não limpar chaves de limite diário durante a validação.

## Rollback

1. Retornar somente o `dashboard-seller` ao commit anterior conhecido e aprovado. Recarregar o opcode cache, se aplicável.
2. Não apagar os registros de `user_system_vars` nem a chave `system_vars.withdrawal_daily_limit_default` sem um plano de dados aprovado: eles representam as configurações individual e global vigentes.
3. Não limpar manualmente as chaves Redis de reserva diária, exceto em incidente com procedimento operacional aprovado. Elas expiram naturalmente e a remoção pode permitir saques acima do teto já consumido no dia.
4. Após o rollback, validar um saque de teste e confirmar que a regra anterior está sendo aplicada.
