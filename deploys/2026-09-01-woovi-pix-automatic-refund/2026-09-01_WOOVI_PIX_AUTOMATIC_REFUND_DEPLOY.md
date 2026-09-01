# Deploy — reembolso de PIX Automático Woovi

## Estrutura

```text
docs/
└── deploys/
    └── 2026-09-01-woovi-pix-automatic-refund/
        └── 2026-09-01_WOOVI_PIX_AUTOMATIC_REFUND_DEPLOY.md
```

## Objetivo

Disponibilizar o ajuste do `services-banking` para que reembolsos de cobranças pagas por PIX Automático, dos providers `woovi` e `woovi_2`, sejam solicitados na API correta da Woovi.

O fluxo identifica a cobrança como assinatura a partir da relação entre a correlação, o provider e a assinatura. Para PIX Automático, envia o E2E da cobrança ao endpoint `POST /api/v1/refund`. Cobranças PIX avulsas continuam usando o endpoint de reembolso de charge já existente.

## Componentes e referências

| Componente | Branch | Commits incluídos | Ação neste deploy |
|---|---|---|---|
| `services-banking` | `fix/banking-commerce-queue-audit` | `aa3f148`, `eb0d63f`, `a329536`, `221e6ce` | Atualizar e recriar app e Nginx |
| `dashboard-seller` | — | — | Sem alteração |
| `edge-gateway`, `edge-public-api`, `services-commerce-v2` | — | — | Sem alteração |

## Alterações incluídas

- `aa3f148`: localiza a assinatura pelo provider efetivamente usado, incluindo `woovi_2`, em vez de assumir provider ID fixo.
- `eb0d63f` e `a329536`: mantêm o reenvio e a auditoria das atualizações de cobrança de assinatura já pagas.
- `221e6ce`: identifica reembolso de PIX Automático, valida uma cobrança de assinatura paga e usa `POST /api/v1/refund` com:
  - `transactionEndToEndId`: E2E persistido para a cobrança;
  - `correlationID`: identificador UUID novo do reembolso;
  - `value`: valor em centavos;
  - `comment`: quando informado.

`refund_mode` é uma marca interna do Banking; não precisa ser enviada pelo dashboard, Gateway ou Commerce.

## Pré-requisitos

1. A branch de deploy deve conter os quatro commits listados acima, com `221e6ce` no `HEAD`.
2. As configurações de credenciais e App ID de `woovi` e `woovi_2` devem existir no ambiente. Não alterar ou expor valores de variáveis no procedimento.
3. A venda de teste deve corresponder a uma cobrança PIX Automático paga, com E2E persistido em `subscriptions_charge`.
4. O container Nginx do compose deve ser recriado junto com o app. Ele pode manter o IP antigo do PHP-FPM se somente o app for recriado, causando `502 Bad Gateway`.

## Banco de dados e filas

Não há migration, DDL, DML nem nova fila neste deploy.

Os registros existentes de `refunds_charge` e as mensagens já pendentes devem ser preservados. A criação do reembolso permanece assíncrona quanto à confirmação final: este ajuste corrige a solicitação inicial à Woovi; não adiciona um novo consumidor de webhook de confirmação de estorno.

## Sequência de disponibilização

1. Obter o diretório de trabalho do compose a partir do container atual e confirmar que não há alterações locais:

   ```bash
   cd "$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' services-banking-services-banking-1)"
   git status --porcelain=v1
   ```

2. Atualizar a branch de deploy:

   ```bash
   git fetch origin --prune
   git switch fix/banking-commerce-queue-audit
   git pull --ff-only origin fix/banking-commerce-queue-audit
   git rev-parse --short HEAD
   ```

   O último comando deve retornar `221e6ce` ou um commit posterior que o contenha.

3. Reconstruir o app e recriar também o Nginx para atualizar a resolução do upstream FastCGI:

   ```bash
   docker compose up -d --build --force-recreate services-banking-app services-banking
   ```

4. Confirmar os containers e a rota de saúde:

   ```bash
   docker compose ps
   docker compose exec services-banking wget -qO- http://127.0.0.1/health
   ```

   A rota deve retornar `{"status":"ok"}`. Se retornar `502`, recrie novamente `services-banking-app` e `services-banking` juntos; não reinicie apenas um deles.

## Validação pós-deploy

1. No dashboard, em uma venda de teste PIX Automático já paga, solicitar o reembolso.
2. Confirmar que não há erro `refund_request_failed` e que a operação cria/atualiza o registro de reembolso esperado.
3. Conferir nos detalhes da venda que o reembolso ficou em processamento/pendente até a confirmação do provider.
4. Confirmar que o reembolso de uma cobrança PIX avulsa continua funcionando, pois ele não deve seguir o modo PIX Automático.
5. Se houver falha, consultar os logs do app e do worker de reembolsos:

   ```bash
   docker compose logs --tail=200 services-banking-app
   docker compose logs --tail=200 services-banking-refunds-queue-worker
   ```

## Rollback

Não há rollback de banco ou filas.

Se houver instabilidade confirmada e for necessário voltar somente este ajuste, reverta o commit `221e6ce` na branch de deploy e recrie app e Nginx juntos:

```bash
git switch fix/banking-commerce-queue-audit
git revert --no-edit 221e6ce
docker compose up -d --build --force-recreate services-banking-app services-banking
```

Esse rollback restaura o uso anterior do endpoint de charge para PIX Automático, que não é o endpoint indicado pela Woovi. Portanto, deve ser uma medida temporária e deliberada, com os reembolsos PIX Automático suspensos até a correção.
