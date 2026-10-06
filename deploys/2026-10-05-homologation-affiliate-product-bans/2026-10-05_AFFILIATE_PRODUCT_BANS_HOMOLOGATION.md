# Deploy — Bloqueio de afiliado por produto em homologação

## Objetivo

Publicar o bloqueio de afiliação por produto. O produtor poderá bloquear um afiliado com motivo interno, impedindo novas solicitações para o mesmo produto. A abertura do convite por um afiliado bloqueado retorna como não encontrada; a reversão não reativa a afiliação automaticamente.

O escopo não inclui bloqueio global por seller nem altera vendas, comissões ou saldos já existentes.

## Componentes e referências

| Repositório | Branch | Commit |
| --- | --- | --- |
| `services-commerce-v2` | `fix/affiliate-qa-hotfixes` | `ca313cd` |
| `edge-public-api` | `fix/affiliate-qa-hotfixes` | `e985776` |
| `edge-gateway` | `fix/affiliate-qa-hotfixes` | `a9eea25` |
| `dashboard-seller` | `fix/affiliate-qa-hotfixes` | `3ddd7315` |

Todos os demais targets operáveis do mapa oficial foram declarados pelo solicitante para permanecer como estão e não receberão comandos.

## Banco de dados

O Commerce V2 possui a migration `20261005180000_create_affiliate_bans_tables.php`, que cria as tabelas `affiliate_bans` e `affiliate_ban_events`.

Ela não deve ser executada nesta operação. A execução de `migrate` será manual e é pré-requisito para usar as novas rotas de bloqueio e reversão.

## Sequência de deploy

Modo de rebuild: incremental.

1. Atualizar `services-commerce-v2` em `/root/opt/lowify/services/service-commerce-v2` para `fix/affiliate-qa-hotfixes` e, se branch ou commit mudar, executar `docker compose up --build -d`.
2. Atualizar `edge-public-api` em `/root/opt/lowify/edge/edge-public-api` para `fix/affiliate-qa-hotfixes` e, se branch ou commit mudar, executar `docker compose up --build -d`.
3. Atualizar `edge-gateway` em `/root/opt/lowify/edge/edge-gateway` para `fix/affiliate-qa-hotfixes` e, se branch ou commit mudar, executar `docker compose up --build -d`.
4. Atualizar `dashboard-seller` em `/root/opt/lowify/front/dashboard-seller` para `fix/affiliate-qa-hotfixes` e, se branch ou commit mudar, executar `docker compose up --build -d`.

Cada repositório deve passar por `git fetch origin --prune`, `git switch fix/affiliate-qa-hotfixes` e `git pull --ff-only origin fix/affiliate-qa-hotfixes` depois da pré-checagem limpa de todos os quatro participantes.

## Validação pós-deploy

Após a migration manual:

1. Abra os detalhes de uma afiliação aprovada e bloqueie o afiliado, informando um motivo interno. A tela deve exibir o estado de bloqueio e o motivo apenas para o produtor.
2. Abra o convite com a conta do afiliado bloqueado. A tela deve informar que o link não foi encontrado.
3. Tente solicitar o convite bloqueado. Nenhuma nova afiliação deve ser criada.
4. Reverta o bloqueio pelo detalhe do afiliado. A tela deve confirmar a reversão e manter a afiliação desativada.
5. Solicite novamente a afiliação após a reversão. A solicitação deve seguir o tipo de aprovação configurado pelo produto.

## Rollback

Retornar os quatro componentes para os commits anteriores nas branches de origem e reconstruir somente os componentes cuja referência mudar. Não apagar `affiliate_bans` nem `affiliate_ban_events`; a migration é aditiva e os registros preservam a auditoria.
