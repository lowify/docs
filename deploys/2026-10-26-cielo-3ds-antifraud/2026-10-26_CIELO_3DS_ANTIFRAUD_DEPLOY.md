# Deploy — correções Cielo 3DS e antifraude

## Objetivo

Publicar as correções do checkout Cielo para impedir o envio de uma autenticação 3DS 2.x sem `Xid` e delegar à Cielo/Cybersource a captura ou o void conforme a análise de risco.

O deploy não habilita o 3DS em produção. `CIELO_3DS_ENABLED` deve permanecer com o valor atual até existir uma transação controlada e credenciais MPI confirmadas.

## Componentes e referências

| Repositório | Diretório de produção | Branch | Commit mínimo | Entrega |
| --- | --- | --- | --- | --- |
| `services-banking-v2` | `/opt/lowify/services/services-banking-v2` | `main` | `9b83b41` | Exige `ExternalAuthentication.Xid` para 3DS 2+ na entrada e antes da chamada Cielo. Mantém a captura diferida quando o antifraude gerencia a decisão. |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `main` | `5921535` | Envia `AuthorizeFirst`, `CaptureOnLowRisk: true` e `VoidOnHighRisk: true` no `FraudAnalysis` Cielo. |
| `front-checkout` | `/opt/lowify/front/front-checkout` | `main` | `c86a45c` | Interrompe o checkout antes do envio quando o MPI devolver 3DS 2+ sem `Xid`. |

São os únicos componentes deste deploy. Não há alteração em edge, banco de dados, Redis, filas, webhooks ou variáveis de ambiente.

## Alterações incluídas

O fluxo final é:

```text
Front Checkout (MPI) -> Commerce V2 (FraudAnalysis) -> Banking V2 (validação e payload Cielo) -> Cielo/Cybersource
```

- O Front só aceita o retorno 3DS quando contiver `Cavv`, `Eci`, `Version` e, para versão 2 ou superior, `Xid`.
- O Commerce usa `AuthorizeFirst`. O Banking reconhece essa combinação e envia `Payment.Capture: false`; a Cielo captura automaticamente em baixo risco, faz void em alto risco e mantém revisão pendente até a decisão final.
- Sem 3DS, `ExternalAuthentication` não é enviado. A análise de fraude continua independente, desde que o checkout possua o browser fingerprint configurado.

## Pré-requisitos

1. Publicar os três commits da tabela em suas respectivas `main`. O PR do Commerce V2 deve estar mergeado e o commit `5921535` deve ser ancestral da `origin/main` antes de iniciar a operação.
2. Confirmar que cada repositório está limpo antes da atualização. Na VPS, o Commerce V2 possui o arquivo não rastreado `.env.bak-pre-cielo-recurring`; não apagar, limpar ou versionar esse arquivo como parte deste deploy.
3. Confirmar que `CIELO_3DS_ENABLED` continua desabilitado. Esta entrega corrige o contrato, mas não autoriza a ativação do 3DS.
4. Registrar os commits atuais na pré-checagem para rollback. No estado observado antes deste deploy: Banking V2 `e737cb4`, Commerce V2 `feat/optional-cpf-pagarme-pix` em `b12c73b` e Front Checkout `412486b`.

## Banco de dados

Não há migration, DDL ou DML neste deploy.

## Sequência de deploy

Modo de rebuild: incremental. Publicar Banking antes de Commerce, pois o Commerce passa a produzir a nova política de antifraude. O Front entra por último.

### 1. Banking V2

```bash
cd /opt/lowify/services/services-banking-v2
git status --porcelain=v1
git fetch origin --prune
git switch main
git pull --ff-only origin main
git merge-base --is-ancestor 9b83b41 HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100
```

Se o `git merge-base` não retornar sucesso, interromper o deploy: o commit necessário não chegou à `main` remota.

### 2. Commerce V2

Antes de trocar a branch, confira o `git status`. Se o único item for `.env.bak-pre-cielo-recurring`, preserve-o sem apagá-lo. Qualquer outro arquivo modificado ou não rastreado deve ser avaliado antes de continuar.

```bash
cd /opt/lowify/services/service-commerce-v2
git status --porcelain=v1
git fetch origin --prune
git switch main
git pull --ff-only origin main
git merge-base --is-ancestor 5921535 HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100
```

Essa etapa migra o repositório atualmente em `feat/optional-cpf-pagarme-pix` para `main`. Não prosseguir se a `main` remota ainda não contiver o PR e o commit indicado.

### 3. Front Checkout

```bash
cd /opt/lowify/front/front-checkout
git status --porcelain=v1
git fetch origin --prune
git switch main
git pull --ff-only origin main
git merge-base --is-ancestor c86a45c HEAD
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=100
```

## Validação pós-deploy

1. Abra um checkout Cielo de teste com fingerprint de antifraude disponível e conclua uma tentativa de cartão autorizada. Confirme que a compra aprovada continua chegando à confirmação normal.
2. Em cenário Cielo controlado de alto risco, confirme que a venda não libera o produto. Não force uma rejeição com cartão real em produção.
3. Se uma venda for para revisão, ela pode permanecer pendente até a decisão da Cielo. Confirme que somente `Paid` libera a venda; `Voided` não libera.
4. Mantenha o 3DS desabilitado nesta validação. Quando for autorizado ativá-lo, faça uma transação controlada de 3DS 2.x e confirme que uma resposta sem `Xid` é recusada antes da autorização; não registrar PAN, CVV, CAVV ou XID em logs.
5. Como conferência técnica opcional, verificar que o payload de fraude contém `AuthorizeFirst`, `CaptureOnLowRisk` e `VoidOnHighRisk`, e que o Banking envia captura diferida. Não limpar Redis, filas, cobranças ou webhooks durante a validação.

## Rollback

1. Interromper novas tentativas de teste se houver erro de autorização ou liberação indevida.
2. Retornar primeiro o Front Checkout ao commit registrado antes do deploy (`412486b`) e reconstruir o container.
3. Retornar o Commerce V2 à referência registrada na pré-checagem — no estado conhecido, `feat/optional-cpf-pagarme-pix` em `b12c73b` — e reconstruir o container. Preservar `.env.bak-pre-cielo-recurring`.
4. Retornar o Banking V2 ao commit registrado antes do deploy (`e737cb4`) e reconstruir o container.
5. Não apagar ou alterar vendas, cobranças, registros de antifraude, webhooks, filas ou chaves Redis criados durante a janela. O rollback é somente de código; estados persistidos devem ser avaliados caso a caso.

## Testes de compatibilidade em homologação

Recomendado antes da ativação do 3DS: validar uma compra Cielo de baixo risco, uma recusa controlada e uma revisão, com o fingerprint ativo. A execução na VPS de homologação depende de autorização específica e de credenciais de teste válidas.
