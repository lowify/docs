# Deploy — auditoria e reenvio de cobranças PIX Automático

## Objetivo

Disponibilizar no `main` do `services-banking` os ajustes de cobrança PIX Automático e a auditoria persistente do encaminhamento para o Commerce.

O objetivo é observar o fluxo em operação por um período prolongado e identificar, com evidência persistida, se o gargalo anterior entre Banking e Commerce foi resolvido. Este plano não inclui testes de compatibilidade, alterações no Commerce nem ações de limpeza de filas.

## Componentes alterados

| Componente | Branch | Commits incluídos |
|---|---|---|
| `services-banking` | `main` | `aa3f148`, `eb0d63f`, `a329536` |

## Alterações incluídas

- `aa3f148`: resolve dinamicamente o provider de assinaturas no fluxo de reembolso.
- `eb0d63f`: republica a ação ao Commerce quando uma cobrança já paga recebe ou corrige o E2E, evitando que a primeira mensagem incompleta deixe a venda sem processamento posterior.
- `a329536`: grava a auditoria persistente da publicação em `commerce:subscriptions:actions` na tabela `services-banking.ordinary_logs`.

Para cada encaminhamento ao Commerce, o Banking passa a registrar:

| Tipo | Significado |
|---|---|
| `commerce_enqueue` | mensagem preparada antes do envio ao Redis |
| `commerce_enqueued` | publicação concluída no Redis |
| `commerce_enqueue_error` | falha de publicação, com o erro e a mensagem correspondente |

Os registros armazenam a mensagem completa, incluindo correlação, parcela, E2E e horário de atualização.

## Pré-requisitos

1. A `main` do `services-banking` deve conter os commits `aa3f148`, `eb0d63f` e `a329536`.
2. A tabela `services-banking.ordinary_logs` deve estar disponível no ambiente.
3. O app e o worker `subscriptions-queue-worker` devem estar configurados para iniciar após a atualização.

## Banco de dados

Não há migration, DDL ou DML neste deploy. A alteração passa a utilizar a tabela existente `services-banking.ordinary_logs` para registrar os envios à fila do Commerce.

## Sequência de disponibilização

1. No diretório do `services-banking`, confirmar que não há alterações locais:

   ```bash
   cd /opt/lowify/services/services-banking
   git status --porcelain=v1
   ```

2. Atualizar a branch `main` até o `HEAD` publicado:

   ```bash
   git switch main
   git pull --ff-only origin main
   ```

3. Reconstruir e subir o serviço e seus workers:

   ```bash
   docker compose up -d --build
   ```

4. Confirmar que o app e o worker de assinaturas estão ativos:

   ```bash
   docker compose ps
   docker compose logs --tail=100 services-banking-subscriptions-queue-worker
   ```

## Validação pós-deploy

Não há validação funcional manual prevista para esta atualização. O acompanhamento ocorre durante a operação normal das cobranças PIX Automático.

Os envios para o Commerce agora são persistidos no banco. Em caso de erro, consulte `services-banking.ordinary_logs` para identificar a mensagem enviada ao Commerce e o erro registrado.

## Rollback

Reverter a revisão do `services-banking` para o commit anterior a `aa3f148` somente se a atualização causar instabilidade operacional confirmada. Os registros já gravados em `ordinary_logs` devem ser preservados: eles são evidência de auditoria e não afetam o processamento das cobranças.
