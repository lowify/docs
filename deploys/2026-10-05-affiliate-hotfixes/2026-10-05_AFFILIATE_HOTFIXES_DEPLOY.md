# Deploy — Hotfixes do programa de afiliados

## Objetivo

Publicar os ajustes de QA do programa de afiliados e o bloqueio de afiliado por produto.

A entrega corrige a renderização de abas de entrega, recuperação e regras de notificação; fluxo de convite após login; remoção de oferta; limites de comissão; exibição de afiliações duplicadas; e inclui dados de afiliado no webhook de venda. Também permite ao produtor bloquear um afiliado em um produto com motivo interno, impedir novas solicitações e reverter o bloqueio sem reativar automaticamente a afiliação.

O escopo não inclui bloqueio global por seller, alteração de vendas/comissões/saldos históricos ou mudança de infraestrutura compartilhada.

## Componentes e referências

| Componente | Host | Repositório | Branch de deploy | Commit |
| --- | --- | --- | --- | --- |
| Dashboard Seller | `144.126.149.57` | `dashboard-seller` | `fix/affiliate-qa-hotfixes` | `41aed79b` |
| Commerce V2 | `144.126.149.57` | `services-commerce-v2` | `fix/affiliate-qa-hotfixes` | `ca313cd` |
| Public API | `144.126.149.57` | `edge-public-api` | `fix/affiliate-qa-hotfixes` | `e985776` |
| Gateway | `144.126.149.57` | `edge-gateway` | `fix/affiliate-qa-hotfixes` | `a9eea25` |
| Integrações de venda | `147.93.180.183` | `services-sale-integrations` | `fix/affiliate-webhook-payload` | `cd3d44b` |

As branches devem ser revisadas e publicadas no remoto antes da janela. Os demais componentes ficam fora do escopo.

## Alterações incluídas

### Dashboard e fluxo de afiliados

- As tabelas de entrega, recuperação e regras de notificação voltam a renderizar dentro de suas respectivas abas.
- O convite de afiliação preserva o retorno após login e exibe ícones de erro sem depender de função PHP ausente.
- O produtor pode bloquear, consultar o motivo interno e reverter o bloqueio no detalhe da afiliação.
- As tabelas de “Outros produtos afiliados” e da página `affiliates.php` exibem somente o registro mais recente de cada combinação afiliado e produto; registros históricos cancelados não se repetem.
- A comissão respeita os limites configurados do programa e a remoção de oferta retorna resultado compatível com a interface.

### APIs e Commerce

```text
Dashboard Seller
-> Gateway
-> Public API (JWT define o produtor)
-> Commerce V2
```

- `POST /affiliates/{id}/ban` exige motivo interno e bloqueia a afiliação por produto.
- `DELETE /affiliates/{id}/ban` reverte o bloqueio.
- Um afiliado bloqueado recebe convite como não encontrado; uma solicitação é recusada antes de criar nova afiliação.
- O Commerce fornece e-mail e identificadores de afiliado aos dados de integração de venda.
- O serviço de integrações acrescenta os dados opcionais de afiliado ao payload de webhook, mantendo compatibilidade com consumidores que ignoram campos desconhecidos.

Não há nova fila. O reconciliamento de bloqueio é síncrono no Commerce; o webhook continua usando o fluxo de integrações já existente.

## Pré-requisitos

1. Registrar a referência anterior aprovada de cada repositório para rollback.
2. Confirmar árvores Git limpas e `origin` correto em cada participante antes de qualquer troca de branch.
3. Confirmar acesso ao banco `lowify` para aplicar o DDL manual da seção seguinte.
4. Confirmar que o endpoint receptor de webhook de teste tolera os campos adicionais `affiliate_id`, `affiliate_code` e `affiliate_email`.
5. Não imprimir ou registrar valores de `.env`, tokens, senhas ou chaves da Cielo/Gateway.

## Banco de dados

O Commerce V2 contém a migration `20261005180000_create_affiliate_bans_tables.php`. O repositório não possui runner de migration disponível no container; portanto, a aplicação em produção deve seguir os SQLs manuais versionados nesta entrega.

1. Executar [VALIDATE.sql](sql/lowify/VALIDATE.sql) no banco `lowify`.
2. Se as duas tabelas não existirem, executar [DEPLOY.sql](sql/lowify/DEPLOY.sql) uma única vez.
3. Executar novamente `VALIDATE.sql`; devem existir `affiliate_bans` e `affiliate_ban_events` com as colunas esperadas.
4. Se uma tabela já existir ou a estrutura divergir, interromper a operação e registrar o resultado. Não executar o DDL parcialmente nem apagar tabelas existentes.

A mudança é aditiva. Em rollback, não remover as tabelas nem os eventos de auditoria já gravados.

## Sequência de deploy

Modo de rebuild: incremental.

### 1. Commerce V2 — atualizar e construir (`144.126.149.57`)

No host principal, em `/opt/lowify/services/service-commerce-v2`:

```bash
git fetch origin --prune
git switch fix/affiliate-qa-hotfixes
git pull --ff-only origin fix/affiliate-qa-hotfixes
docker compose build
```

### 2. Aplicar o ajuste de banco

Executar os SQLs da seção **Banco de dados** após o build do Commerce e antes de iniciar o container novo.

### 3. Iniciar Commerce V2

```bash
cd /opt/lowify/services/service-commerce-v2
docker compose up -d
docker compose ps
```

### 4. Atualizar Public API e Gateway (`144.126.149.57`)

Atualizar e reconstruir sequencialmente:

```bash
cd /opt/lowify/edge/edge-public-api
git fetch origin --prune
git switch fix/affiliate-qa-hotfixes
git pull --ff-only origin fix/affiliate-qa-hotfixes
docker compose up --build -d
docker compose ps

cd /opt/lowify/edge/edge-gateway
git fetch origin --prune
git switch fix/affiliate-qa-hotfixes
git pull --ff-only origin fix/affiliate-qa-hotfixes
docker compose up --build -d
docker compose ps
```

### 5. Atualizar o Dashboard Seller (`144.126.149.57`)

O Dashboard usa o código do repositório como volume; atualizar somente o Git, sem build ou restart:

```bash
cd /opt/lowify/front/dashboard-seller
git fetch origin --prune
git switch fix/affiliate-qa-hotfixes
git pull --ff-only origin fix/affiliate-qa-hotfixes
```

### 6. Atualizar Integrações de venda por último (`147.93.180.183`)

No host de integrações, em `/opt/lowify/services/services-sale-integrations`:

```bash
git fetch origin --prune
git switch fix/affiliate-webhook-payload
git pull --ff-only origin fix/affiliate-webhook-payload
docker compose up --build -d
docker compose ps
```

Não consumir, apagar ou reprocessar filas manualmente durante o deploy.

## Validação pós-deploy

1. Abra um detalhe de afiliado como produtor e confira que “Outros produtos afiliados” não repete uma afiliação histórica do mesmo produto.
2. Abra `affiliates.php` e confirme que cada afiliado/produto aparece apenas uma vez, com o estado mais recente.
3. Bloqueie uma afiliação aprovada, preenchendo o motivo interno.
   - Resultado esperado: a afiliação fica desativada e o motivo aparece somente para o produtor no detalhe.
4. Com a conta do afiliado bloqueado, abra o convite e tente solicitar a afiliação.
   - Resultado esperado: abertura informa convite não encontrado e a solicitação não cria registro.
5. Reverta o bloqueio.
   - Resultado esperado: a reversão é confirmada, mas a afiliação não é reativada automaticamente.
6. Valide uma alteração de comissão dentro dos limites configurados e a remoção de uma oferta.
7. Faça uma venda de teste com afiliado e confira no endpoint de webhook de teste que o payload possui os campos opcionais de afiliado, incluindo e-mail.
8. Abra as abas de Entrega e Recuperação no detalhe de produto afiliado.
   - Resultado esperado: suas tabelas aparecem somente dentro da aba selecionada, sem conteúdo no fim da página.

Se algum caso falhar, registrar horário, URL/tela, usuário de teste e resultado visível. Não apagar vendas, dados de afiliação nem mensagens de fila para forçar repetição.

## Rollback

1. Retornar Dashboard, Gateway, Public API, Integrações e Commerce às referências anteriores aprovadas, na ordem inversa do deploy.
2. Reconstruir somente Commerce, Public API, Gateway e Integrações; o Dashboard requer apenas atualização Git.
3. Não remover `affiliate_bans` ou `affiliate_ban_events`: as tabelas e os eventos são aditivos e devem ser preservados.
4. Não apagar webhooks já enviados, vendas, comissões ou afiliações históricas.

## Fora de escopo

- Bloqueio global de afiliado por seller.
- Reativação automática após reversão de bloqueio.
- Alteração de saldos, comissões, vendas, pagamentos ou transferências já registrados.
- Mudança de infraestrutura, Redis ou bancos compartilhados fora do DDL descrito.
