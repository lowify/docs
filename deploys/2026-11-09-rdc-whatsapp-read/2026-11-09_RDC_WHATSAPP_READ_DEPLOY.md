# Deploy — RDC por leitura de recuperação WhatsApp

## Objetivo

Publicar no Commerce V2 a marcação de `rdc = 1` a partir de uma leitura de
mensagem de recuperação por WhatsApp.

O fluxo oficial continua imediato: o callback da Meta chega pelo Notifications,
o Commerce valida o dispatch de recuperação e marca a venda somente se ela
ainda estiver `pending`. A entrega adiciona uma fila exclusiva para a
reconciliação de vendas já pagas: o operador enfileira as vendas confirmadas de
um dia, e o consumidor confere novamente se existe uma leitura WhatsApp válida
antes de marcar o RDC.

Não há alteração em Edge, Notifications, banco, migration, variável obrigatória
ou contrato HTTP.

## Estado desejado

| Repositório | Diretório em produção | Branch | Ação |
| --- | --- | --- | --- |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/rdc-whatsapp-read` | `pull + build` |

O deploy é incremental e restrito ao Commerce V2. Não sincronizar nem
reconstruir outros repositórios como efeito colateral.

## Alterações incluídas

- O callback oficial de `read` no WhatsApp preserva a regra de marcar apenas
  vendas `pending`, evitando que uma confirmação tardia altere uma venda paga
  diretamente.
- O comando `sales-recovery:mark-rdc-from-whatsapp-reads` seleciona vendas
  `paid` por `confirmed_at`, usando datas em `America/Sao_Paulo`, e as coloca
  na fila `sales:recovery:whatsapp-rdc:verify`.
- O consumidor da fila processa uma venda por vez, com intervalo padrão de 200
  ms, deduplicação por `sale_id` e até três tentativas em caso de falha.
- Antes de alterar uma venda, o consumidor exige `rdc = 0` e um evento
  persistido de recuperação WhatsApp com `event_type = read` e referência
  `whatsapp_meta`. Reentregas da fila são idempotentes.
- O comando aceita `--date=YYYY-MM-DD` para uma data. O suporte a intervalo é
  administrativo, mas não será usado nesta operação: executar cada dia
  separadamente para controlar o volume.

## Pré-requisitos

1. Publicar previamente a branch `feat/rdc-whatsapp-read` no remoto com o
   commit `9bfcea4` (`feat(sales): queue WhatsApp recovery RDC checks`). Este
   documento não autoriza nem executa o push.
2. Confirmar que o arquivo `.env` do Commerce V2 não sobrescreve as
   configurações padrão da fila com valores inválidos. Não é necessário criar
   variável nova: o processo fica ativo por padrão e usa o Redis já configurado
   para o serviço.
3. Reservar uma janela para a reconciliação. O consumidor processa cerca de
   cinco vendas por segundo no padrão; não iniciar o próximo dia enquanto a
   fila do dia atual ainda estiver sendo processada.

## Banco de dados

Não há migration, DDL, DML manual nem alteração de schema.

Os dados alterados pelo consumidor são somente `sales.rdc`, e somente após a
confirmação do evento WhatsApp persistido. Não apagar eventos de recuperação,
listas Redis ou chaves de deduplicação durante o deploy ou a reconciliação.

## Sequência de deploy

### 1. Publicar Commerce V2

```bash
cd /opt/lowify/services/service-commerce-v2
test -z "$(git status --porcelain=v1)" || { echo 'Há alterações locais; interrompendo.' >&2; exit 1; }
git fetch origin --prune
git switch feat/rdc-whatsapp-read
git pull --ff-only origin feat/rdc-whatsapp-read
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

O commit exibido deve ser `9bfcea4`. Não continuar se o serviço não estiver
`Up`, se o processo `commerce_whatsapp_recovery_rdc_queue` apresentar erro de
inicialização ou se o commit for diferente.

## Reconciliação de 4 a 9 de novembro

Executar um dia por vez. Primeiro usar `--dry-run`, confirmar a quantidade
retornada e só então repetir a mesma data sem essa opção. Não iniciar a data
seguinte antes de a fila da data atual estar sendo processada.

### 1. Dia 4 de novembro de 2026

```bash
cd /opt/lowify/services/service-commerce-v2
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-04 --dry-run
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-04
```

### 2. Dia 5 de novembro de 2026

```bash
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-05 --dry-run
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-05
```

### 3. Dia 6 de novembro de 2026

```bash
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-06 --dry-run
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-06
```

### 4. Dia 7 de novembro de 2026

```bash
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-07 --dry-run
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-07
```

### 5. Dia 8 de novembro de 2026

```bash
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-08 --dry-run
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-08
```

### 6. Dia 9 de novembro de 2026

```bash
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-09 --dry-run
docker compose exec -T service-commerce-v2 php bin/hyperf.php sales-recovery:mark-rdc-from-whatsapp-reads --date=2026-11-09
```

O comando informa `sales_found`, `enqueued`, `already_pending` e `failed`.
Interromper a operação se `failed` for maior que zero. Uma segunda execução da
mesma data é segura: vendas já marcadas permanecem fora da atualização por
terem `rdc = 1`.

## Validação pós-deploy

1. Use uma venda de teste ainda pendente que receba uma mensagem de recuperação
   via WhatsApp. Ao abrir a mensagem, confirme no fluxo administrativo da venda
   que ela passa a aparecer como recuperada.
2. Escolha uma venda paga do período que tenha leitura WhatsApp de recuperação
   registrada. Após processar o dia correspondente, confirme que ela aparece
   como recuperada, sem alteração de valor, pagamento ou entrega.
3. Escolha uma venda paga sem leitura WhatsApp de recuperação. Confirme que ela
   não aparece como recuperada após o processamento.

Como conferência técnica opcional, os logs do Commerce devem mostrar
`[WhatsappRecoveryRdcProcess] Sale checked.` para as vendas processadas. Não
limpar a fila nem Redis para repetir a validação.

## Rollback

1. Retornar o Commerce V2 ao commit anterior `a73958b` na mesma branch e
   reconstruir somente esse serviço com `docker compose up -d --build`.
2. Não reverter `sales.rdc` já marcado: as marcações refletem eventos WhatsApp
   persistidos e são compatíveis com a revisão anterior.
3. Não apagar mensagens da fila ou chaves de deduplicação no Redis. Elas não
   causam efeito na revisão anterior e podem ser retomadas ao republicar a
   versão com o consumidor.
4. O callback oficial de leitura para vendas `pending` permanece disponível na
   revisão anterior.

## Referências

- [Feature — comunicações de venda](../../features/sale-notifications/README.md)
- [Fase 5 — Commerce: tentativas, RDC e dispatch](../../plans/sale-notifications/05_COMMERCE_DISPATCH_TASKS.md)
- [Fase 6 — Notification: envio, callbacks e alertas](../../plans/sale-notifications/06_NOTIFICATION_CALLBACKS_TASKS.md)
