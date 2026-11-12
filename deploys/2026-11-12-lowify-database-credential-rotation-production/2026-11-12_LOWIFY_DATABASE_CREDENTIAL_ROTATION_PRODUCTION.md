# Produção — rotação da credencial MariaDB compartilhada

## Objetivo

Rotacionar, em produção, a senha da conta MariaDB compartilhada `app`, sem executar migrations, DDL, limpeza de dados, filas ou Redis. Os caminhos de produção começam em `/opt` — não em `/root/opt`.

Este procedimento não contém nem deve produzir senha em tela, logs, histórico de shell, Git ou chat. Não executar se o inventário de pré-checagem revelar consumidores ativos fora do escopo coordenado.

## Componentes e referências

Esta é uma operação de configuração; não há branch, commit ou imagem nova para publicar.

| Componente | Caminho em produção | Ação |
| --- | --- | --- |
| MariaDB compartilhado | `/opt/lowify/data_layer/mariabd` | Atualizar `MARIADB_PASSWORD` e alterar a conta no MariaDB. |
| Gateway | `/opt/lowify/edge/edge-gateway` | Pausar o ingresso HTTP primeiro e iniciar por último. |
| Webhook | `/opt/lowify/edge/edge-webhook` | Pausar e recriar se estiver ativo. |
| Account | `/opt/lowify/services/services-account` | Pausar e recriar se estiver ativo. |
| Auth | `/opt/lowify/services/services-auth` | Pausar e recriar se estiver ativo. |
| Notifications | `/opt/lowify/services/services-notifications` | Pausar e recriar se estiver ativo. |
| Commerce | `/opt/lowify/services/services-commerce` | Atualizar configuração; recriar somente se estava ativo. |
| Commerce V2 | `/opt/lowify/services/service-commerce-v2` | Atualizar configuração; recriar somente se estava ativo. |
| Wallet | `/opt/lowify/services/services-wallet` | Atualizar configuração; recriar somente se estava ativo. |
| Banking e Banking V2 | `/opt/lowify/services/services-banking`, `/opt/lowify/services/services-banking-v2` | Atualizar configuração; recriar somente se estavam ativos. |
| Dashboard Seller | `/opt/lowify/front/dashboard-seller` | Pausar web e workers; recriar se estavam ativos. |
| Member Area | `/opt/lowify/front/front-member-area` | Pausar e recriar se estava ativo. |

Também devem ser incluídos quaisquer outros `.env` sob `/opt` que tenham `DB_USERNAME=app`. A descoberta é obrigatória porque a conta MariaDB é compartilhada entre bancos diferentes.

## Pré-requisitos e pré-checagem

1. Ter uma janela de manutenção aprovada e acesso administrativo ao host de produção.
2. Executar todos os comandos como usuário `root` no host de produção; não usar `sudo` parcial, nem os caminhos de homologação.
3. Confirmar os consumidores ativos e a conta MariaDB antes de parar qualquer container:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'

set -a
. /opt/lowify/data_layer/mariabd/.env
set +a

docker exec -e MYSQL_PWD="$MARIADB_ROOT_PASSWORD" data-layer-mariadb \
  mariadb -uroot --batch --skip-column-names \
  -e "SELECT User, Host FROM mysql.user WHERE User = '${MARIADB_USER}';"

find /opt -type f -name .env -not -path '*/vendor/*' -not -path '*/node_modules/*' -print0 \
  | while IFS= read -r -d '' env_file; do
      [ "$(awk -F= '$1==\"DB_USERNAME\" {print $2; exit}' "$env_file")" = app ] \
        && printf '%s\n' "$env_file"
    done
```

4. Confirmar que a conta é `app`@`%` ou ajustar todos os comandos SQL para o host efetivamente retornado. Se algum consumidor ativo não estiver coberto, incluí-lo na parada e retomada antes de continuar.

## Sequência de execução

### 1. Parar ingresso e consumidores

Registrar o momento da parada do gateway para medir indisponibilidade. Não parar o MariaDB nem o Redis.

```bash
date +%s%3N >/tmp/lowify-gateway-rotation-start-ms

cd /opt/lowify/edge/edge-gateway && docker compose stop
cd /opt/lowify/edge/edge-webhook && docker compose stop
cd /opt/lowify/services/services-account && docker compose stop
cd /opt/lowify/services/services-auth && docker compose stop
cd /opt/lowify/services/services-notifications && docker compose stop
cd /opt/lowify/front/dashboard-seller && docker compose stop
cd /opt/lowify/front/front-member-area && docker compose stop
```

Parar também, somente se ativos na pré-checagem, Commerce, Commerce V2, Wallet, Banking e Banking V2. Componentes que já estavam parados devem permanecer parados.

### 2. Gerar a senha e sincronizar configurações

O comando abaixo gera uma senha hexadecimal sem quebra de linha, atualiza todos os arquivos de ambiente encontrados para a conta `app` e atualiza o valor preservado para recriações futuras do MariaDB.

Execute as seções 2 e 3 na mesma sessão de shell: a variável e o arquivo temporário da nova senha precisam permanecer disponíveis até a validação concluir.

```bash
set -euo pipefail
umask 077
rotation_secret_file="$(mktemp)"
trap 'rm -f "$rotation_secret_file"' EXIT
printf '%s' "$(openssl rand -hex 32)" >"$rotation_secret_file"

update_password() {
  local env_file="$1" key="$2" temp_file
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

while IFS= read -r -d '' env_file; do
  [ "$(awk -F= '$1=="DB_USERNAME" {print $2; exit}' "$env_file")" = app ] || continue
  update_password "$env_file" DB_PASSWORD
done < <(find /opt -type f -name .env -not -path '*/vendor/*' -not -path '*/node_modules/*' -print0)

update_password /opt/lowify/data_layer/mariabd/.env MARIADB_PASSWORD
```

### 3. Alterar a senha persistida no MariaDB e validar

```bash
set -a
. /opt/lowify/data_layer/mariabd/.env
set +a

{
  printf "ALTER USER '%s'@'%%' IDENTIFIED BY '" "$MARIADB_USER"
  cat "$rotation_secret_file"
  printf "';\n"
} | docker exec -i -e MYSQL_PWD="$MARIADB_ROOT_PASSWORD" data-layer-mariadb mariadb -uroot

client_config_file="$(mktemp)"
trap 'rm -f "$rotation_secret_file" "$client_config_file" /tmp/lowify-gateway-rotation-start-ms' EXIT
{
  printf '[client]\nuser=%s\npassword=' "$MARIADB_USER"
  cat "$rotation_secret_file"
  printf '\nhost=data-layer-mariadb\n'
} >"$client_config_file"
chmod 600 "$client_config_file"

docker run --rm --network data_net -v "$client_config_file:/tmp/client.cnf:ro" mariadb:11.8 \
  mariadb --defaults-extra-file=/tmp/client.cnf -e 'SELECT 1;' lowify
```

O resultado esperado é `1`. Em falha, manter gateway e consumidores parados; corrigir a conta, host ou configuração divergente. Não reverter a senha automaticamente.

### 4. Retomar somente os componentes que estavam ativos antes da janela

Não usar `--build`; nenhuma imagem mudou. O objetivo é restaurar exatamente o estado anterior à manutenção: se um componente já estava parado antes da janela, **não o inicie agora**. Recriar somente cada Compose project que a pré-checagem identificou como ativo, respeitando dependências:

```bash
cd /opt/lowify/services/services-account && docker compose up -d --force-recreate
cd /opt/lowify/services/services-auth && docker compose up -d --force-recreate
cd /opt/lowify/services/services-notifications && docker compose up -d --force-recreate
cd /opt/lowify/edge/edge-webhook && docker compose up -d --force-recreate
cd /opt/lowify/front/dashboard-seller && docker compose up -d --force-recreate
cd /opt/lowify/front/front-member-area && docker compose up -d --force-recreate
```

Incluir Commerce, Commerce V2, Wallet, Banking e Banking V2 somente se estavam ativos antes da parada. Por exemplo: se Wallet estava parado antes da manutenção, atualize seu `.env`, mas não execute `docker compose up` nele.

### 5. Validar consumidores e reabrir o gateway

```bash
sleep 10

for name in \
  services-account-services-account-1 \
  services-auth-services-auth-1 \
  services-notifications-services-notifications-1 \
  edge-webhook-edge-webhook-1 \
  front-dashboard-seller \
  front-members-area; do
  docker inspect -f '{{.State.Status}}' "$name" | grep -qx running
  ! docker logs --since 5m "$name" 2>&1 \
    | grep -qiE 'access denied|authentication failed|sqlstate\[hy000\] \[1045\]'
done

cd /opt/lowify/edge/edge-gateway && docker compose up -d --force-recreate
sleep 10

for name in edge-gateway-edge-gateway-1 edge-gateway-edge-gateway-worker-1; do
  docker inspect -f '{{.State.Status}}' "$name" | grep -qx running
  ! docker logs --since 5m "$name" 2>&1 \
    | grep -qiE 'access denied|authentication failed|sqlstate\[hy000\] \[1045\]'
done

start_ms=$(cat /tmp/lowify-gateway-rotation-start-ms)
end_ms=$(date +%s%3N)
awk -v start="$start_ms" -v end="$end_ms" \
  'BEGIN { printf "gateway_downtime_seconds=%.3f\n", (end - start) / 1000 }'
```

## Validação pós-execução

1. Abrir a aplicação de produção e fazer login com uma conta de teste autorizada.
2. Abrir o dashboard do seller e a área de membros; ambos devem carregar sem indisponibilidade.
3. Confirmar uma consulta de leitura de conta ou saldo.
4. Confirmar que a métrica de indisponibilidade foi registrada e que não há erros de autenticação MariaDB nos logs dos containers recriados.

## Rollback

Não há rollback automático da senha. Se um consumidor falhar após a rotação, manter o gateway pausado, corrigir o `.env` desse consumidor para a senha nova e recriar somente esse componente. Não apagar volumes, dados, bancos, Redis, filas ou logs.
