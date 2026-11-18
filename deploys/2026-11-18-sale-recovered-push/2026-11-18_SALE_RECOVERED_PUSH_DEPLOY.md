# Deploy — push de venda recuperada

## Objetivo

Enviar ao vendedor o push **“Venda recuperada”** quando uma venda paga tiver
`rdc = 1`. Vendas pagas sem RDC continuam enviando **“Venda Aprovada!”**;
vendas do Checkout Transparente sem RDC continuam com o template próprio.

O caminho publicado é:

```text
Commerce V2 (venda paga com rdc = 1)
  -> evento sale_recovered em stream:notifications:push_notification
  -> services-notification (template sale_recovered)
  -> Firebase Cloud Messaging
```

## Componentes e referências

| Componente | Diretório de produção | Branch | Commit esperado | Ação |
| --- | --- | --- | --- | --- |
| `services-notification` | `/opt/lowify/services/services-notifications` | `feat/sale-recovered-push` | `b773c9f` | migration do template e rebuild |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/sale-recovered-push` | `b3b0a7e` | seleção do evento e rebuild |

Não há alteração em front, edge, banco do Commerce V2, Firebase ou contratos
de fila existentes. Não publicar outros componentes por causa desta entrega.

## Alterações incluídas

- O Commerce V2 usa `sale_recovered` para o push de uma venda `paid` com
  `rdc = 1`; essa seleção tem prioridade inclusive quando houver contexto de
  Checkout Transparente.
- O serviço de notificações recebe a migration aditiva que cria o template
  ativo `sale_recovered`, com título `Venda recuperada` e corpo
  `Valor: [amount_brl]`.
- A chave de idempotência continua derivada de venda e evento. Como o novo
  evento tem nome próprio, uma venda RDC não conflita com `sale_approved`.

## Pré-requisitos

1. Publicar as duas branches no remoto antes da janela. Este roteiro não faz
   `git push`.
2. Confirmar que os clones de produção estão limpos antes de trocar de branch.
3. Confirmar que o Firebase e os processos `push_notification_stream` e
   `push_notification_sender` já estão saudáveis no Notifications.
4. Usar uma venda de teste cujo seller tenha push de venda paga habilitado e
   um dispositivo com token FCM ativo. Não usar dados reais de cliente.

## Banco de dados

Aplicar somente a migration do Notifications:

`migrations/2026_11_18_000063_seed_sale_recovered_push_template.php`

Ela insere ou atualiza o template pelo nome `sale_recovered`; não há DDL, não
há migration no Commerce V2 e não há backfill. Antes da execução, conferir o
status das migrations. Após a execução, confirmar que ela aparece como
aplicada. Não executar rollback durante a janela.

## Sequência de deploy

### 1. Pré-checagem

Em cada diretório, a saída de `git status --porcelain=v1` deve estar vazia. Se
não estiver, parar e preservar as alterações para análise.

```bash
cd /opt/lowify/services/services-notifications
git status --porcelain=v1
git fetch origin --prune
git show --quiet --oneline b773c9f

cd /opt/lowify/services/service-commerce-v2
git status --porcelain=v1
git fetch origin --prune
git show --quiet --oneline b3b0a7e
```

### 2. Publicar Notifications e o template

Publicar o consumidor antes do produtor para que o template já exista quando
o Commerce começar a emitir `sale_recovered`.

```bash
cd /opt/lowify/services/services-notifications
git switch feat/sale-recovered-push
git pull --ff-only origin feat/sale-recovered-push
git merge-base --is-ancestor b773c9f HEAD
docker compose up -d --build services-notifications
docker compose exec -T services-notifications php bin/hyperf.php migrate --force --path=migrations/2026_11_18_000063_seed_sale_recovered_push_template.php
docker compose exec -T services-notifications php bin/hyperf.php migrate:status
docker compose ps
docker compose logs --tail=100 services-notifications
```

### 3. Publicar Commerce V2

```bash
cd /opt/lowify/services/service-commerce-v2
git switch feat/sale-recovered-push
git pull --ff-only origin feat/sale-recovered-push
git merge-base --is-ancestor b3b0a7e HEAD
docker compose up -d --build service-commerce-v2
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

## Validação pós-deploy

1. Abra a área de vendas com uma conta de teste que receba notificações push.
2. Faça uma recuperação de carrinho para essa conta e conclua o pagamento pela
   URL de recuperação, para que a venda fique marcada como RDC.
3. Confirme no dispositivo de teste que chega uma notificação com o título
   **“Venda recuperada”** e o valor correto.
4. Faça uma venda paga normal para a mesma conta. Confirme que ela continua
   exibindo **“Venda Aprovada!”**.
5. Se a notificação não chegar, verificar como conferência técnica os logs dos
   dois serviços e o estado do processo de push; não consumir, reenfileirar ou
   limpar `stream:notifications:push_notification` durante a verificação.

## Rollback

1. Retornar primeiro o Commerce V2 à revisão saudável anterior, reconstruir e
   recriar somente `service-commerce-v2`. Isso interrompe a emissão do evento
   novo.
2. Retornar o Notifications à revisão saudável anterior e reconstruir somente
   `services-notifications` se necessário.
3. Manter a migration e o registro `sale_recovered`: eles são aditivos e a
   versão anterior do Commerce não os utiliza.
4. Não apagar notificações já registradas, tokens FCM ou mensagens existentes
   na stream. Registrar e investigar qualquer falha de entrega separadamente.
