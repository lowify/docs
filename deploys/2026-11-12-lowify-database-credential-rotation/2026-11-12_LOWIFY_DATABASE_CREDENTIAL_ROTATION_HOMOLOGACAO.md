# Homologação — rotação da credencial do banco `lowify`

## Objetivo

Rotacionar a senha da conta MariaDB usada pelo banco compartilhado `lowify` na VPS de homologação. A execução interrompe temporariamente somente os consumidores desse banco e bloqueia a entrada HTTP no `edge-gateway` até que todos os consumidores revalidem a conexão.

Não há migration, DDL ou alteração de dados de negócio. A senha não deve ser colocada neste documento, no histórico do shell, em logs, em Git ou em mensagens de chat.

## Escopo

| Componente | Caminho na VPS | Ação |
| --- | --- | --- |
| MariaDB compartilhado | `/root/opt/lowify/data_layer/mariabd` | Atualizar `MARIADB_PASSWORD` e executar `ALTER USER`. |
| edge-gateway | `/root/opt/lowify/edge/edge-gateway` | Pausar a entrada HTTP antes da rotação; iniciar por último. |
| edge-webhook | `/root/opt/lowify/edge/edge-webhook` | Atualizar `DB_PASSWORD` e recriar se estava ativo. |
| services-account | `/root/opt/lowify/services/services-account` | Atualizar `DB_PASSWORD` e recriar se estava ativo. |
| services-auth | `/root/opt/lowify/services/services-auth` | Atualizar `DB_PASSWORD` e recriar se estava ativo. |
| services-commerce | `/root/opt/lowify/services/services-commerce` | Atualizar `DB_PASSWORD`; preservar o estado prévio se já estava parado. |
| services-commerce-v2 | `/root/opt/lowify/services/service-commerce-v2` | Atualizar `DB_PASSWORD`; preservar o estado prévio se já estava parado. |
| services-wallet | `/root/opt/lowify/services/services-wallet` | Atualizar `DB_PASSWORD`; preservar o estado prévio se já estava parado. |
| services-banking | `/root/opt/lowify/services/services-banking` | Atualizar a configuração parada para não reintroduzir a senha antiga futuramente. |
| services-banking-v2 | `/root/opt/lowify/services/services-banking-v2` | Atualizar a configuração parada para não reintroduzir a senha antiga futuramente. |
| services-notification | `/root/opt/lowify/services/services-notifications` | Atualizar `DB_PASSWORD` e recriar se estava ativo. |
| dashboard-seller | `/root/opt/lowify/front/dashboard-seller` | Atualizar `DB_PASSWORD`, recriar web e workers se estavam ativos. |
| front-member-area | `/root/opt/lowify/front/front-member-area` | Atualizar `DB_PASSWORD` e recriar se estava ativo. |
| services-commerce-worker | `/root/opt/lowify/services/services-commerce-worker` | Atualizar a configuração parada para não reintroduzir a senha antiga futuramente. |
| account JWT deploy | `/root/opt/lowify/services/.deploy/services-account-jwt` | Atualizar a configuração parada para não reintroduzir a senha antiga futuramente. |
| auth JWT deploy | `/root/opt/lowify/services/.deploy/services-auth-jwt` | Atualizar a configuração parada para não reintroduzir a senha antiga futuramente. |

`front-docs` está fora do escopo por decisão do solicitante. Não iniciar, parar nem alterar esse componente durante esta operação.

## Pré-requisitos

- Acesso SSH administrativo à VPS de homologação.
- A conta MariaDB administrativa existente e a conta da aplicação devem estar disponíveis somente no ambiente; nunca copiar os valores para o terminal compartilhado ou para este documento.
- A janela deve considerar indisponíveis, enquanto durar a operação, os fluxos que dependem dos consumidores listados.
- Registrar quais Compose projects estão ativos antes de parar qualquer container. Um componente que já estava parado deve continuar parado ao final.

## Pré-checagem

Na VPS, confirmar containers e o usuário/host da conta de aplicação. Os comandos abaixo não exibem senhas:

```bash
ssh root@217.216.87.77
docker ps --format 'table {{.Names}}\t{{.Status}}'

cd /root/opt/lowify/data_layer/mariabd
set -a
. ./.env
set +a
docker exec -e MYSQL_PWD="$MARIADB_ROOT_PASSWORD" data-layer-mariadb \
  mariadb -uroot --batch --skip-column-names \
  -e "SELECT User, Host FROM mysql.user WHERE User = '${MARIADB_USER}';"
```

Se não houver exatamente uma conta de aplicação esperada ou o host for diferente do planejado, parar e corrigir o comando `ALTER USER` antes de prosseguir.

## Sequência de rotação

### 1. Pausar ingresso e consumidores

Parar primeiro o gateway. Em seguida, parar os consumidores que estavam ativos. Não parar MariaDB nem Redis.

```bash
cd /root/opt/lowify/edge/edge-gateway && docker compose stop
cd /root/opt/lowify/services/services-account && docker compose stop
cd /root/opt/lowify/services/services-auth && docker compose stop
cd /root/opt/lowify/services/services-notifications && docker compose stop
cd /root/opt/lowify/edge/edge-webhook && docker compose stop
cd /root/opt/lowify/front/dashboard-seller && docker compose stop
cd /root/opt/lowify/front/front-member-area && docker compose stop
```

Para `services-commerce`, `service-commerce-v2` e `services-wallet`, executar `docker compose stop` somente se a pré-checagem mostrar containers ativos. Os componentes já parados não devem ser iniciados pela rotação.

### 2. Atualizar os arquivos de ambiente sem revelar a senha

Gerar a senha em um arquivo temporário com permissões restritas. Atualizar as chaves sem interpolar a senha na linha de comando. O script deve atualizar exatamente `MARIADB_PASSWORD` no banco e `DB_PASSWORD` nos consumidores do escopo.

```bash
umask 077
rotation_secret_file="$(mktemp)"
trap 'rm -f "$rotation_secret_file"' EXIT
printf '%s' "$(openssl rand -hex 32)" >"$rotation_secret_file"

update_env_password() {
  local env_file="$1"
  local key="$2"
  local temp_file
  temp_file="$(mktemp)"
  awk -v key="$key" -v secret_file="$rotation_secret_file" '
    BEGIN { found = 0 }
    index($0, key "=") == 1 {
      printf "%s=", key
      while ((getline secret < secret_file) > 0) printf "%s", secret
      close(secret_file)
      printf "\n"
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        printf "%s=", key
        while ((getline secret < secret_file) > 0) printf "%s", secret
        close(secret_file)
        printf "\n"
      }
    }
  ' "$env_file" >"$temp_file"
  mv "$temp_file" "$env_file"
}

update_env_password /root/opt/lowify/data_layer/mariabd/.env MARIADB_PASSWORD
update_env_password /root/opt/lowify/services/services-account/.env DB_PASSWORD
update_env_password /root/opt/lowify/services/services-auth/.env DB_PASSWORD
update_env_password /root/opt/lowify/services/services-commerce/.env DB_PASSWORD
update_env_password /root/opt/lowify/services/service-commerce-v2/.env DB_PASSWORD
update_env_password /root/opt/lowify/services/services-wallet/.env DB_PASSWORD
update_env_password /root/opt/lowify/services/services-banking/.env DB_PASSWORD
update_env_password /root/opt/lowify/services/services-banking-v2/.env DB_PASSWORD
update_env_password /root/opt/lowify/services/services-notifications/.env DB_PASSWORD
update_env_password /root/opt/lowify/front/dashboard-seller/.env DB_PASSWORD
update_env_password /root/opt/lowify/front/front-member-area/.env DB_PASSWORD
update_env_password /root/opt/lowify/services/services-commerce-worker/.env DB_PASSWORD
update_env_password /root/opt/lowify/services/.deploy/services-account-jwt/.env DB_PASSWORD
update_env_password /root/opt/lowify/services/.deploy/services-auth-jwt/.env DB_PASSWORD
update_env_password /root/opt/lowify/edge/edge-gateway/.env DB_PASSWORD
update_env_password /root/opt/lowify/edge/edge-webhook/.env DB_PASSWORD
```

### 3. Alterar a senha efetiva no MariaDB

Usar o usuário e host confirmados na pré-checagem. Este passo é o que efetivamente muda a senha persistida no MariaDB; modificar `.env` sozinho não faz isso.

```bash
cd /root/opt/lowify/data_layer/mariabd
set -a
. ./.env
set +a

{
  printf "ALTER USER '%s'@'%%' IDENTIFIED BY '" "$MARIADB_USER"
  cat "$rotation_secret_file"
  printf "';\n"
} | docker exec -i -e MYSQL_PWD="$MARIADB_ROOT_PASSWORD" data-layer-mariadb mariadb -uroot
```

Substituir somente o host (`'%'`) pelo host confirmado na pré-checagem, se necessário. Não reiniciar o container do MariaDB.

### 4. Validar a nova credencial antes de iniciar aplicações

```bash
{
  printf '[client]\nuser=%s\npassword=' "$MARIADB_USER"
  cat "$rotation_secret_file"
  printf '\nhost=data-layer-mariadb\n'
} >/tmp/lowify-db-client.cnf
chmod 600 /tmp/lowify-db-client.cnf

docker run --rm --network data_net \
  -v /tmp/lowify-db-client.cnf:/tmp/client.cnf:ro \
  mariadb:11.8 mariadb --defaults-extra-file=/tmp/client.cnf -e 'SELECT 1;' lowify

rm -f /tmp/lowify-db-client.cnf
```

O resultado esperado é uma única linha com `1`. Se falhar, manter gateway e consumidores parados, revisar usuário/host e não reverter automaticamente a senha.

### 5. Recriar somente os componentes que estavam ativos

Não usar `--build`: as imagens não mudaram. Recriar os containers ativos para que recarreguem o `.env`.

```bash
cd /root/opt/lowify/services/services-account && docker compose up -d --force-recreate
cd /root/opt/lowify/services/services-auth && docker compose up -d --force-recreate
cd /root/opt/lowify/services/services-notifications && docker compose up -d --force-recreate
cd /root/opt/lowify/front/dashboard-seller && docker compose up -d --force-recreate
cd /root/opt/lowify/front/front-member-area && docker compose up -d --force-recreate
cd /root/opt/lowify/edge/edge-webhook && docker compose up -d --force-recreate
```

Incluir `services-commerce`, `service-commerce-v2` e `services-wallet` somente se estavam ativos antes da operação. Não iniciar `services-commerce-worker`, `services-account-jwt`, `services-auth-jwt`, `services-banking`, `services-banking-v2` ou `front-docs` como consequência da rotação.

### 6. Conferir e reabrir o gateway

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
docker logs --since 5m services-account-services-account-1 2>&1 | grep -iE 'access denied|authentication failed' && exit 1 || true
docker logs --since 5m services-auth-services-auth-1 2>&1 | grep -iE 'access denied|authentication failed' && exit 1 || true

cd /root/opt/lowify/edge/edge-gateway && docker compose up -d --force-recreate
```

## Validação funcional

1. Abrir a homologação e fazer login. O login deve concluir sem erro.
2. Abrir o dashboard do seller. A página deve carregar dados sem mensagem de indisponibilidade.
3. Confirmar uma ação somente de leitura que dependa de saldo ou conta. O resultado deve carregar normalmente.
4. Confirmar que os logs recentes não têm `Access denied`, `authentication failed` ou falhas de conexão ao banco.

Se qualquer validação falhar, parar o gateway novamente e manter os demais componentes em estado controlado até identificar o consumidor com configuração divergente.

## Resultado da execução em homologação

Executado em 12/11/2026.

- A conta MariaDB rotacionada foi confirmada como `app`@`%`.
- A descoberta durante a operação mostrou que a mesma conta também é usada pelos bancos `services-gateway`, `services-webhook`, `services-notification` e `services-banking`; por isso os respectivos arquivos de ambiente foram alinhados à nova senha.
- Foram pausados e recriados os componentes ativos: `services-account`, `services-auth`, `services-notifications`, `dashboard-seller` (incluindo workers), `front-member-area`, `edge-webhook` e `edge-gateway` (por último).
- `services-commerce`, `services-commerce-v2`, `services-wallet`, Banking e os artefatos de deploy que já estavam parados permaneceram parados.
- A nova credencial foi validada por conexão MariaDB direta antes de subir os consumidores.
- Uma varredura final confirmou que todas as configurações descobertas que usam a conta compartilhada `app` estão alinhadas à nova senha.
- Os containers recriados estavam em execução e sem mensagens recentes de erro de autenticação MariaDB.

Não foi executado um fluxo autenticado de interface por não haver uma credencial de teste fornecida para este procedimento.

## Segunda execução em homologação

Executada em 12/11/2026 com nova senha aleatória para a conta `app`@`%`.

- Foram atualizados os 13 arquivos de ambiente encontrados na VPS que usam a conta MariaDB `app`, além de `MARIADB_PASSWORD` na infraestrutura.
- Foram coordenados os mesmos consumidores ativos da primeira execução: Account, Auth, Notifications, Webhook, Dashboard Seller e seus workers, Member Area e Gateway.
- A conexão com a nova credencial foi validada antes de reiniciar consumidores.
- Após a retomada, os consumidores e o gateway estavam em execução sem erros de autenticação MariaDB; a varredura de hashes confirmou que as configurações da conta `app` permanecem alinhadas.

### Indisponibilidade medida

A indisponibilidade do ingresso HTTP foi medida na VPS desde o instante imediatamente anterior a `docker compose stop` do Gateway até os containers web e worker do Gateway voltarem a `running` sem erro de autenticação: **190,618 segundos** (**3 minutos e 10,618 segundos**).

O período inclui a parada coordenada, a rotação da senha, a validação MariaDB, a recriação dos consumidores ativos e a retomada final do Gateway.

## Rollback

Não executar rollback automático. A rotação de senha revoga a credencial anterior e deve permanecer assim caso a nova conexão falhe. Para recuperar um componente, corrigir o `.env` dele para a senha nova e recriá-lo. Não apagar dados, volumes MariaDB, Redis, filas ou logs.
