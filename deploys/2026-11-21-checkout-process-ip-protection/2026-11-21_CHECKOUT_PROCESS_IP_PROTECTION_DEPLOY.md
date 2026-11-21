# Deploy — proteção do IP no processamento de checkout

## Objetivo

Impedir que uma chamada direta à origem do Checkout manipule o IP associado ao
processamento de pagamento. A proteção é aplicada apenas ao `POST /process`
(e à forma direta `POST /process.php`): o Traefik do Front Checkout aceita
essas requisições somente das redes públicas do Cloudflare. O Gateway recebe
os headers de IP encaminhados pelo Front Checkout e substitui o campo `ip` do
payload assinado pelo IP resolvido desses headers.

Fora do escopo: alterar outras rotas do Checkout, criar regras no painel
Cloudflare, modificar firewall da origem, alterar bancos, filas, Redis ou
dados de vendas.

## Componentes e referências

| Repositório | Diretório de produção | Branch de deploy | Commit mínimo | Papel |
| --- | --- | --- | --- | --- |
| `front-checkout` | `/opt/lowify/front/front-checkout` | `main` | `829ccd0266a4a7a8f80264f2d4c799def2f5b63c` | Restringe a rota de processamento às faixas do Cloudflare e encaminha os headers de IP válidos ao Gateway. |
| `edge-gateway` | `/opt/lowify/edge/edge-gateway` | `feat/checkout-apple-google-pay` | `851fc79e13df9af1b0b5c78463362f3e1ab1adfc` | Após validar a HMAC da chamada interna, substitui `data.ip` pelo IP resolvido dos headers encaminhados. |

Não incluir outros repositórios, serviços, banco, Redis ou infraestrutura
nesta entrega.

## Alterações incluídas

- O Front Checkout cria um router Traefik de maior prioridade para `POST
  /process` e `POST /process.php`, nos hosts públicos `checkout` e `pay`.
- O router aplica allowlist dos ranges IPv4 e IPv6 públicos oficiais do
  Cloudflare. Uma conexão que não venha dessas redes é recusada antes de
  alcançar PHP ou o processamento do pagamento.
- O Front Checkout encaminha somente os headers de IP reconhecidos
  (`CF-Connecting-IP`, `X-Real-IP` e `X-Forwarded-For`), depois de validar que
  contêm um endereço IP.
- No Gateway, a rota interna assinada `/internal/checkout/process` mantém a
  validação HMAC e, depois dela, substitui `data.ip` pela prioridade
  `CF-Connecting-IP`, `X-Real-IP`, `X-Forwarded-For` e `remote_addr`.
- Não há alteração de JWT, contrato de fila, produtor, consumidor ou efeito
  em banco. A assinatura HMAC entre Front Checkout e Gateway permanece o
  mecanismo de autenticação da chamada interna.

## Pré-requisitos

1. Confirmar que as referências remotas listadas na tabela existem e contêm
   os commits mínimos antes de iniciar.
2. Confirmar que os repositórios produtivos estão sem alterações locais. Se
   qualquer `git status --porcelain=v1` tiver saída, interromper e preservar o
   estado encontrado; não usar stash, reset, limpeza ou checkout forçado.
3. Confirmar no Cloudflare que os DNS públicos de `checkout` e `pay` estão
   com proxy ativo. Se um deles estiver em modo DNS-only, o novo router
   recusará seus pagamentos por não receber a conexão da rede Cloudflare.
4. Confirmar que o Traefik produtivo observa labels Docker do
   `front-checkout` e que o serviço permanece conectado à rede `data_net`.
   Não reiniciar o Traefik nem alterar infraestrutura nesta entrega.
5. Registrar os commits ativos dos dois repositórios antes da atualização;
   eles são as referências de rollback.
6. Preparar um checkout e meio de pagamento de teste autorizado. Não repetir
   cobranças reais para validar esta mudança.

## Banco de dados

Não há migration, DDL, DML nem alteração de dados. Não limpar Redis, filas,
logs, cobranças, pedidos ou vendas durante o deploy ou a validação.

## Sequência de deploy

Executar a pré-checagem nos dois componentes antes de atualizar o primeiro.
Parar integralmente se qualquer uma falhar.

### 1. Pré-checagem

```bash
cd /opt/lowify/front/front-checkout
git status --porcelain=v1
git branch --show-current
git rev-parse HEAD
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/main
git merge-base --is-ancestor 829ccd0266a4a7a8f80264f2d4c799def2f5b63c origin/main

cd /opt/lowify/edge/edge-gateway
git status --porcelain=v1
git branch --show-current
git rev-parse HEAD
git remote get-url origin
git fetch origin --prune
git show-ref --verify --quiet refs/remotes/origin/feat/checkout-apple-google-pay
git merge-base --is-ancestor 851fc79e13df9af1b0b5c78463362f3e1ab1adfc origin/feat/checkout-apple-google-pay
```

Os dois comandos `git merge-base --is-ancestor` devem terminar com status
zero. Registrar os hashes retornados por `git rev-parse HEAD` para rollback.

### 2. Atualizar e reconstruir o Front Checkout

Publicar o Front antes do Gateway para que a entrada pública passe a aceitar
somente Cloudflare antes de o Gateway usar os headers encaminhados.

```bash
cd /opt/lowify/front/front-checkout
git switch main
git pull --ff-only origin main
git merge-base --is-ancestor 829ccd0266a4a7a8f80264f2d4c799def2f5b63c HEAD
docker compose up -d --build
docker compose ps
```

O rebuild é obrigatório: as labels do router e da allowlist são aplicadas
quando o container é recriado. Confirmar que o serviço `front-checkout` está
em execução antes de continuar.

### 3. Atualizar e reconstruir o Edge Gateway

```bash
cd /opt/lowify/edge/edge-gateway
git switch feat/checkout-apple-google-pay
git pull --ff-only origin feat/checkout-apple-google-pay
git merge-base --is-ancestor 851fc79e13df9af1b0b5c78463362f3e1ab1adfc HEAD
docker compose up -d --build
docker compose ps
```

Confirmar que os containers do Gateway estão em execução. Não executar ação
manual em worker, filas ou serviços vizinhos além do comportamento normal do
Compose deste repositório.

## Validação pós-deploy

1. Abra um checkout de teste pelos domínios públicos usuais (`checkout` e
   `pay`). A página e o formulário devem carregar normalmente via HTTPS.
2. Preencha os dados válidos do checkout de teste e envie uma única tentativa
   de pagamento autorizada para esse fim. O processamento deve avançar para a
   resposta normal do checkout, sem erro de acesso ou erro genérico de
   comunicação.
3. Confirme que a venda ou o estado pendente aparece conforme o método de
   pagamento usado. Não repetir a tentativa caso a primeira já tenha criado
   uma cobrança; preservar horário, identificador do pedido e mensagem para
   investigação.
4. Como conferência técnica opcional, o operador pode verificar que os logs
   recentes do Front Checkout e do Gateway não apresentam erro fatal e que o
   router do Traefik foi carregado. Não enviar requisições de pagamento fora do
   Cloudflare nem manipular headers para essa conferência em produção.
5. Se a tela retornar `403` logo ao processar, verificar primeiro se o DNS do
   host está com proxy Cloudflare ativo. Não remover a allowlist como
   contorno.

## Rollback

1. Interromper novas tentativas de pagamento se houver regressão confirmada e
   preservar a evidência da falha.
2. Voltar primeiro o Front Checkout ao hash registrado na pré-checagem e
   executar `docker compose up -d --build` para remover o router de allowlist
   caso ele seja a causa da indisponibilidade. Substituir
   `FRONT_CHECKOUT_COMMIT_ANTERIOR` pelo hash registrado no passo de
   pré-checagem; não usar o hash de outra máquina ou de outro ambiente.

   ```bash
   cd /opt/lowify/front/front-checkout
   git status --porcelain=v1
   git cat-file -e FRONT_CHECKOUT_COMMIT_ANTERIOR^{commit}
   git switch --detach FRONT_CHECKOUT_COMMIT_ANTERIOR
   git rev-parse HEAD
   docker compose up -d --build
   docker compose ps
   ```

   O `git status --porcelain=v1` deve estar vazio e o `git rev-parse HEAD`
   deve retornar exatamente o hash informado. Caso não estejam, parar antes do
   `git switch`.

3. Voltar em seguida o Gateway ao hash registrado na pré-checagem e
   reconstruir seus containers. O Gateway anterior permanece compatível com o
   Front retornado. Substituir `EDGE_GATEWAY_COMMIT_ANTERIOR` pelo hash
   registrado no passo de pré-checagem.

   ```bash
   cd /opt/lowify/edge/edge-gateway
   git status --porcelain=v1
   git cat-file -e EDGE_GATEWAY_COMMIT_ANTERIOR^{commit}
   git switch --detach EDGE_GATEWAY_COMMIT_ANTERIOR
   git rev-parse HEAD
   docker compose up -d --build
   docker compose ps
   ```

   O `git status --porcelain=v1` deve estar vazio e o `git rev-parse HEAD`
   deve retornar exatamente o hash informado. Caso não estejam, parar antes do
   `git switch`.

4. A recuperação definitiva deve ocorrer em seguida por commits de reversão
   revisados e publicados nas respectivas branches. Não usar `git reset`,
   `push --force`, limpeza de Redis, exclusão de logs ou remoção de pedidos e
   cobranças.

## Riscos e pendências

- A allowlist usa uma fotografia das faixas públicas oficiais do Cloudflare na
  data deste documento. A alteração futura dessas faixas exige atualização
  coordenada da configuração antes que afete o tráfego legítimo. Antes de
  cada alteração nessa allowlist, comparar integralmente as labels com
  `https://www.cloudflare.com/ips-v4` e
  `https://www.cloudflare.com/ips-v6`; a lista desta entrega contém as 15
  faixas IPv4 e as 7 faixas IPv6 retornadas por esses endpoints na revisão do
  documento.
- A proteção impede manipulação básica por acesso direto à origem somente se
  o tráfego público do Checkout realmente atravessar o Traefik configurado.
  Ela não substitui uma regra de firewall/origem privada para todos os demais
  endpoints.
- O teste de homologação desta entrega foi cancelado antes da execução. A
  validação funcional em produção deve ser feita com checkout e meio de
  pagamento de teste autorizados.
