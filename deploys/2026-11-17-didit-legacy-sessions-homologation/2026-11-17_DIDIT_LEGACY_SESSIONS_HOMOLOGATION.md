# Homologação — sessões Didit legadas na migração de fase 1

> Status: executado parcialmente em 2026-11-17
> VPS: `root@217.216.87.77`
> Modo de rebuild: incremental

## Objetivo

Validar, em homologação, que a migração de uma PF da fase 1 com documentos pessoais incompletos preserva seus documentos, move suas sessões de `didit` para `didit_legacy` e permite criar uma nova solicitação Didit. O teste aplicará a migração em exatamente 10 contas PF elegíveis e documentará seus resultados.

## Componentes e referências

| Repositório | Caminho na VPS | Branch | Commit |
| --- | --- | --- | --- |
| `services-account` | `/root/opt/lowify/services/services-account` | `feat/didit-legacy-sessions` | `06793641ffb747548bfcf8a18642fcba6b762b9c` |
| `dashboard-seller` | `/root/opt/lowify/front/dashboard-seller` | `feat/didit-legacy-sessions` | `853be1b7e204245892c804cf86958d585a11eab5` |

Todos os demais targets operáveis do mapa oficial de homologação devem ser sincronizados em `main`: `front-chat`, `front-checkout`, `front-idv`, `front-member-area`, `edge-gateway`, `edge-public-api`, `edge-webhook`, `services-auth`, `services-banking`, `services-banking-v2`, `services-commerce`, `services-commerce-v2`, `services-notification`, `services-platform`, `services-wallet`, `checkout-transparent-api`, `checkout-transparent-billing`, `checkout-transparent-worker` e `ct-webhook`.

## Targets mantidos como estão

| Target | Motivo |
| --- | --- |
| `services-commerce-v2` | Possui trabalho local de outro fluxo e foi explicitamente excluído desta homologação. Não receberá pré-checagem adicional, fetch, troca de branch, pull ou Docker. |
| `data_layer` | Target protegido: banco e Redis compartilhados. |
| `checkout-transparent-infra` | Target protegido: infraestrutura, banco e Redis do checkout transparente. |

Os repositórios ausentes e não mapeados não participam.

## Alterações incluídas

- A migração de PF incompleta troca sessões `didit` do titular para `didit_legacy` e preserva os documentos.
- A criação de Didit considera somente sessões com provider `didit`; a sessão legada não é reutilizada e seus documentos não bloqueiam a nova solicitação.
- Um webhook atrasado da sessão legada é ignorado pelo `services-account`, sem gerar sessão ativa nem alterar status/KYC/documentos.
- A revisão administrativa exibe documentos vinculados à sessão legada com o badge “Didit legado”.

## Pré-requisitos

1. Fazer a pré-checagem de todos os targets operáveis: árvore Git limpa, origin correto e branches remotas existentes. Se qualquer target estiver alterado, interromper toda a homologação.
2. Confirmar backup recuperável do banco `lowify` e acesso administrativo ao MariaDB da VPS.
3. Não imprimir segredos, não limpar Redis, filas, DLQs ou eventos de webhook.
4. Aplicar o ajuste de ENUM antes de publicar o `services-account`.

## Banco de dados

Precheck manual:

```sql
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'lowify'
  AND TABLE_NAME = 'user_verification_sessions'
  AND COLUMN_NAME = 'provider';
```

Prosseguir somente se o resultado for `enum('didit','local')`, anulável e default `NULL`:

```sql
ALTER TABLE lowify.user_verification_sessions
    MODIFY COLUMN provider ENUM('didit', 'didit_legacy', 'local') NULL DEFAULT NULL;
```

Validação manual após o DDL:

```sql
SELECT COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'lowify'
  AND TABLE_NAME = 'user_verification_sessions'
  AND COLUMN_NAME = 'provider';
```

O resultado esperado é `enum('didit','didit_legacy','local')`, `YES`, `NULL`. Não reaplicar o DDL se o valor já existir.

## Sequência de homologação

1. Executar a pré-checagem completa exigida pelo fluxo de homologação em todos os targets operáveis. Para participantes, validar as branches declaradas; para os demais, validar `origin/main`.
2. Aplicar e validar manualmente o DDL da seção Banco de dados.
3. Atualizar `services-account` para `feat/didit-legacy-sessions` e reconstruí-lo somente se branch ou commit mudarem.
4. Atualizar `dashboard-seller` para `feat/didit-legacy-sessions` somente via Git; não executar Docker Compose nesse repositório.
5. Atualizar os demais targets operáveis para `main`; reconstruir apenas aqueles cuja branch ou commit mudarem. Executar rebuilds sequencialmente.
6. Confirmar a saúde do container do Account e o acesso ao Dashboard atualizado antes de alterar contas de teste.

## Seleção e migração das 10 contas

Após o `services-account` estar saudável, usar exatamente estas 10 PFs elegíveis à migração: `455, 597, 1187, 1285, 1454, 1867, 2019, 3891, 4124, 4174`. Todas foram confirmadas como `account_phase = 1`, `account_review_status IS NULL`, `tipo_conta = pf` e possuem sessões Didit. O conjunto inclui seis casos completos e quatro incompletos ou rejeitados para validar os dois caminhos.

Executar primeiro a prévia:

```bash
php bin/hyperf.php account-phase:migrate-phase-one --user-ids=455,597,1187,1285,1454,1867,2019,3891,4124,4174
```

Depois de revisar a prévia, aplicar:

```bash
php bin/hyperf.php account-phase:migrate-phase-one --user-ids=455,597,1187,1285,1454,1867,2019,3891,4124,4174 --apply
```

Os comandos acima devem ser executados no container do `services-account`. Não repetir em novos IDs nesta homologação sem documentar uma nova execução.

## Validação pós-homologação

1. Para cada uma das 10 contas, confirmar que a fase passou para 2 e que os documentos anteriores permanecem registrados.
2. Nas contas incompletas que tinham sessão Didit, confirmar que a sessão antiga está em `didit_legacy`.
3. Solicitar uma nova verificação Didit em pelo menos uma conta incompleta. A interface deve abrir um novo link, diferente da sessão legada.
4. Na revisão administrativa, confirmar o badge “Didit legado” nos documentos históricos e que eles continuam visíveis para revisão/conclusão.
5. Para uma sessão legada, usar apenas um webhook/evento já disponível em homologação ou aguardar o evento natural; não publicar eventos manualmente. Confirmar que não há criação de sessão `didit` com o ID antigo nem alteração do status da conta.

## Rollback

1. Interromper novas migrações antes de reverter código.
2. Reverter `dashboard-seller` e `services-account` às revisões anteriores aprovadas. Reconstruir somente o Account; o Dashboard é atualizado apenas via Git.
3. Não remover `didit_legacy` do ENUM: sessões persistidas podem depender dele.
4. Não apagar documentos, sessões nem eventos. As 10 contas migradas devem permanecer registradas para análise; qualquer reversão de fase exige decisão individual e documentada.

## Resultado da execução

### Publicação e ambiente

- O DDL foi aplicado e validado: `provider` agora aceita `didit`, `didit_legacy` e `local`, preservando `NULL` e seu default.
- `services-account` foi publicado em `feat/didit-legacy-sessions` no commit `0679364` e está ativo no container correspondente.
- `dashboard-seller` foi publicado em `feat/didit-legacy-sessions` no commit `853be1b7` via Git. Este repositório não exige Docker Compose para publicação.
- Os demais targets operáveis foram sincronizados em `main`, mas somente o Account foi reconstruído por solicitação posterior. `services-commerce-v2` permaneceu inalterado.

### Migrações executadas

Foram migradas as 10 PFs planejadas: `455, 597, 1187, 1285, 1454, 1867, 2019, 3891, 4124, 4174`.

| Grupo | IDs | Resultado |
| --- | --- | --- |
| Documentação completa | `455, 597, 1187, 1285, 1454, 4174` | Fase alterada para 2; sessões Didit existentes permaneceram ativas. |
| Documentação incompleta/rejeitada | `1867, 2019, 3891, 4124` | Fase alterada para 2; identidade pendente quando aplicável; todas as sessões Didit anteriores foram movidas para `didit_legacy`. |

Após a aplicação, os quatro casos incompletos não possuíam sessões com provider `didit` e preservaram respectivamente `14`, `12`, `9` e `8` sessões `didit_legacy`. Os documentos continuaram presentes; o caso `3891`, que já não tinha documentos, continuou sem documentos.

### Nova solicitação Didit

Uma tentativa direta e sem credenciais no endpoint de criação retornou `401`, como esperado para uma rota autenticada. Nenhuma autenticação foi contornada e nenhuma sessão foi criada por esse teste. A validação funcional pendente é acessar o Dashboard autenticado com uma das quatro contas incompletas e solicitar a nova verificação: o resultado esperado é um novo link Didit e uma nova sessão com provider `didit`, distinta das sessões legadas.
