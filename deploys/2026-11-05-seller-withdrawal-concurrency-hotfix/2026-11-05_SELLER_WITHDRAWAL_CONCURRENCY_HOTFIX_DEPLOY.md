# Deploy — hotfix de concorrência de saque do seller

## Objetivo

Publicar uma proteção contra solicitações simultâneas de saque do mesmo seller no Dashboard Seller. A criação do saque passa a serializar, por seller, a conferência de saldo e o registro do saque pendente. Assim, depois que o primeiro pedido é registrado, um pedido concorrente passa a enxergar o valor já comprometido e é recusado se exceder o saldo disponível.

O worker de pagamentos também passa a exigir saldo suficiente para o valor líquido do saque mais a taxa antes de enviar um Pix. Essa é uma barreira adicional para pedidos inconsistentes já existentes.

Fora do escopo: remover ou corrigir `api/request-withdrawal.php`, que não usa este fluxo; aplicar a mesma trava ao saque administrativo; invalidar challenges financeiros aprovados concorrentes; e corrigir dados financeiros históricos. Não testar tentativas paralelas de saque em produção.

## Componentes e referências

| Repositório | Diretório de produção | Branch de deploy | Commit | Papel na entrega |
| --- | --- | --- | --- | --- |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `main` | `1a032ff75aab1a113f373dd719668ca7fa848a6f` | Trava transacional por seller ao criar saque e validação defensiva no worker de pagamentos. |

Não há alteração em `services-wallet`, `services-account`, edge, banco, Redis, filas ou infraestrutura nesta entrega.

## Alterações incluídas

- `withdrawalRequest()` inicia uma transação e bloqueia a linha do seller em `tbl_usuarios` com `SELECT ... FOR UPDATE`.
- O bloqueio permanece ativo desde a leitura do saldo até o `INSERT` do saque com status `pendente`; falhas fazem rollback antes de devolver o erro.
- Como o cálculo de saldo bloqueia saques pendentes, uma segunda solicitação do mesmo seller só prossegue depois do commit da primeira e não pode reutilizar o saldo já reservado.
- Em `scripts/process/withdrawal_payments_worker.php`, o worker interrompe o processamento quando o saldo recomposto não cobre `valor_solicitado + taxa_saque`.
- O contrato de interface, o formato das solicitações e as filas existentes não foram modificados. O worker continua selecionando registros pendentes elegíveis e enviando o Pix pelo gateway já configurado.

## Pré-requisitos

1. Confirmar que `origin/main` do repositório `dashboard-seller` contém o commit `1a032ff75aab1a113f373dd719668ca7fa848a6f` antes de iniciar.
2. Antes de trocar a revisão, executar `git status --porcelain=v1` no diretório de produção. Se houver qualquer saída, interromper a operação e preservar as alterações encontradas; não usar stash, reset, limpeza ou checkout forçado.
3. Confirmar que o banco de dados principal está acessível ao Dashboard Seller. A nova trava depende de transações e de bloqueio de linha no banco.
4. Confirmar que o agendador que executa `scripts/process/withdrawal_payments_worker.php` continua ativo. Não é necessário reiniciar ou limpar filas, Redis, registros de saque ou dados de sellers.
5. Separar uma conta de teste autorizada para a validação em homologação. Não enviar pedidos paralelos nem Pix de teste em produção.

## Banco de dados

Não há migration, DDL ou DML manual.

O código usa a transação existente do PDO e um bloqueio temporário na linha correspondente ao seller em `tbl_usuarios`. O lock é liberado pelo commit após inserir o saque pendente ou pelo rollback em caso de falha. Não criar índices, atualizar saldo, apagar saques pendentes ou modificar `tbl_saques` manualmente como parte deste deploy.

## Sequência de deploy

### 1. Atualizar o Dashboard Seller

```bash
cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git fetch origin --prune
git switch main
git pull --ff-only origin main
git rev-parse HEAD
```

O último comando deve retornar `1a032ff75aab1a113f373dd719668ca7fa848a6f` ou um commit posterior explicitamente aprovado que o contenha.

Não há rebuild de container confirmado para este repositório. O próximo atendimento PHP e a próxima execução agendada do worker já usarão os arquivos atualizados. Se a operação local possuir cache de opcode gerenciado por processo, aplicar somente o procedimento operacional já aprovado para recarregá-lo; não reiniciar serviços ou containers sem essa necessidade confirmada.

### 2. Conferir o estado operacional

```bash
cd /opt/lowify/front/dashboard-seller
php -l includes/operations/withdrawal.php
php -l scripts/process/withdrawal_payments_worker.php
```

Os dois comandos devem informar que não há erros de sintaxe. Como conferência técnica opcional, aguardar a próxima execução normal do worker e verificar que não há erro de PHP referente a `withdrawal_payments_worker.php`. Não acionar manualmente Pix, não reprocessar saques e não limpar locks ou registros para essa conferência.

## Testes de compatibilidade em homologação

Executar somente em homologação, com uma conta de teste cujo saldo e conta Pix estejam controlados. Não usar produção nem uma conta de seller real.

1. Com saldo de teste de R$ 50, validar a senha financeira em dois fluxos e obter duas autorizações aprovadas de saque.
2. Enviar em paralelo duas solicitações de R$ 40, cada uma com sua própria autorização, para o fluxo atual de criação de saque.
3. Confirmar que apenas uma solicitação é registrada como pendente e que a outra recebe a mensagem de saldo insuficiente.
4. Confirmar na tela de saldo que o valor disponível considera o saque pendente e não fica negativo.
5. Deixar o worker processar somente se o ambiente de homologação estiver configurado sem saída financeira real; caso contrário, interromper antes do envio ao gateway.
6. Registrar os IDs gerados e cancelar/limpar os dados de teste apenas pelo procedimento aprovado do ambiente. Não apagar registros diretamente no banco e não limpar filas ou Redis.

## Validação pós-deploy

1. Faça login no Dashboard Seller com uma conta autorizada e abra a área de saldo.
2. Abra a solicitação de saque, informe uma conta Pix já cadastrada e um valor que esteja dentro do saldo exibido. A tela deve continuar pedindo a senha financeira e aceitar a solicitação normal após a confirmação.
3. Confirme que a área de saldo exibe a solicitação como pendente e reduz o valor disponível de acordo com as regras atuais.
4. Não tente repetir pedidos em paralelo em produção. A prova de concorrência pertence exclusivamente ao teste de homologação acima.
5. Se a solicitação normal falhar, interrompa novos testes e preserve o horário, o ID do seller e a mensagem apresentada para investigação. Não realizar ajuste manual de saldo, nem aprovar, pagar ou excluir saques para contornar a falha.

Como conferência técnica complementar, o operador pode verificar os logs da aplicação e do worker pelo ID do seller. Essa conferência não exige alterar filas, Redis ou o banco.

## Rollback

1. Antes da atualização, registrar o commit que estava ativo no Dashboard Seller. A referência imediatamente anterior deste hotfix é `63f954ba825082ab59c7d7f2ca8e9a287a85c9db`.
2. Se houver regressão confirmada, no diretório `/opt/lowify/front/dashboard-seller`, repetir a pré-checagem de estado limpo e retornar temporariamente ao commit anterior com os comandos abaixo. Esta referência é somente o rollback deste hotfix; não a usar para descartar alterações futuras já publicadas em `main`.

```bash
cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git fetch origin --prune
git switch --detach 63f954ba825082ab59c7d7f2ca8e9a287a85c9db
git rev-parse HEAD
```

O último comando deve retornar `63f954ba825082ab59c7d7f2ca8e9a287a85c9db`. A recuperação definitiva deve ser feita em seguida por um commit de reversão aprovado e publicado em `main`; não usar reset nem checkout forçado.
3. Não apagar saques pendentes, execution locks, mensagens, chaves Redis ou registros financeiros. O rollback restaura somente o comportamento de código e não desfaz solicitações ou Pix já processados.
4. Após o rollback, suspender novos testes de saque até que a causa seja analisada. Qualquer diferença financeira exige conciliação própria aprovada.

## Riscos e pendências

- O hotfix protege os chamadores de `withdrawalRequest()`, incluindo `actions/withdrawal/create.php`. Ele não remove nem protege `api/request-withdrawal.php`, endpoint legado que hoje está fora deste fluxo e deve ser removido ou corrigido em uma entrega específica.
- `withdrawalProfitRequest()` segue fora da trava; avaliar separadamente o fluxo administrativo e sua relação com o saldo do seller.
- A conta explicitamente isenta de validação de saldo pela regra atual não passa pela recusa por insuficiência, mesmo com a serialização. Essa exceção deve ser revisada pelo responsável financeiro.
- A publicação não corrige desafios de senha financeira aprovados simultâneos. A limitação de uma autorização ativa por usuário permanece uma melhoria necessária em `services-account`.
- Não há correção automática de possíveis saldos negativos ou saques históricos. A auditoria e a conciliação devem ser conduzidas em procedimento separado.
