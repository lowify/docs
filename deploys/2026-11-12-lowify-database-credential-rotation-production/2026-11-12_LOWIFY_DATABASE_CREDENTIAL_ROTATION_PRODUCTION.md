# Produção — rotação da credencial MariaDB compartilhada

## Objetivo

Rotacionar, em produção, a senha da conta MariaDB compartilhada `app`, sem executar migrations, DDL, limpeza de dados, filas ou Redis. Os caminhos de produção começam em `/opt` — não em `/root/opt`.

Este procedimento não contém nem deve produzir senha em tela, logs, histórico de shell, Git ou chat. Não executar se a auditoria da pré-checagem revelar consumidores ativos fora do escopo coordenado.

## Componentes e referências

Esta é uma operação de configuração; não há branch, commit ou imagem nova para publicar.

A conta `app` é uma só, no mesmo servidor `data-layer-mariadb`, mas cada consumidor acessa um banco diferente. Os nomes `mariadb` e `data-layer-mariadb` são aliases do mesmo container na rede `data_net`. Por isso todos os consumidores precisam ser parados e recriados na mesma janela: quem ficar de fora perde acesso no momento do `ALTER USER`.

| Componente | Caminho em produção | Banco acessado com `app`¹ | Ação |
| --- | --- | --- | --- |
| MariaDB compartilhado | `/opt/lowify/data_layer/mariabd` | — | Atualizar `MARIADB_PASSWORD` e alterar a conta no MariaDB. |
| Gateway (+ worker) | `/opt/lowify/edge/edge-gateway` | `services-gateway` | Pausar o ingresso HTTP primeiro e iniciar por último. |
| Webhook | `/opt/lowify/edge/edge-webhook` | `services-webhook` | Pausar e recriar se estiver ativo. |
| Account | `/opt/lowify/services/services-account` | `lowify` | Pausar e recriar se estiver ativo. |
| Auth | `/opt/lowify/services/services-auth` | `lowify` | Pausar e recriar se estiver ativo. |
| Notifications | `/opt/lowify/services/services-notifications` | `services-notification` | Pausar e recriar se estiver ativo. |
| Commerce (+ workers) | `/opt/lowify/services/services-commerce` | `lowify` | Pausar e recriar se estiver ativo. |
| Commerce V2 | `/opt/lowify/services/service-commerce-v2` | `lowify` | Pausar e recriar se estiver ativo. |
| Wallet | `/opt/lowify/services/services-wallet` | `lowify` | Pausar e recriar se estiver ativo. |
| Banking (+ workers) e Banking V2 | `/opt/lowify/services/services-banking`, `/opt/lowify/services/services-banking-v2` | `services-banking` | Pausar e recriar se estiverem ativos. |
| Dashboard Seller (web + workers) | `/opt/lowify/front/dashboard-seller` | `lowify` | Pausar e recriar se estiver ativo. |
| Member Area | `/opt/lowify/front/front-member-area` | `lowify` | Pausar e recriar se estiver ativo. |

¹ Bancos observados em homologação; a auditoria da pré-checagem mostra os de produção.

### Escopo confirmado pela equipe de produção

A equipe de produção confirmou que os 12 projetos acima usam a mesma credencial `app`. **`services-banking-defense` e `services-platform` usam credenciais próprias** e ficam fora desta operação: não são parados, recriados nem têm `.env` alterado.

Essa confirmação não substitui a auditoria da pré-checagem: ela é que detecta consumidores avulsos, fora de qualquer lista oficial (ver a seção seguinte).

### Consumidores que a varredura de `.env` não encontra

A etapa 2 atualiza todo `.env` sob `/opt` com `DB_USERNAME=app`. Isso **não cobre** containers cuja senha foi fixada no ambiente do container sem `.env` em disco. Em homologação foi o caso do `front-docs-app`: usava `app` no banco `lowify`, não constava em nenhuma lista e o `docker-compose.yml` dele já não existia, o que impede recriá-lo com a senha nova. Só as seções 3 e 4 da auditoria o revelaram.

A varredura também pode alterar `.env` de diretórios que não são projetos ativos (em homologação, `services/.deploy/services-auth-jwt` e `services/.deploy/services-account-jwt`). Isso é esperado e inofensivo, mas deve ser conferido na seção 5 da auditoria.

## Pré-requisitos

1. Ter uma janela de manutenção aprovada e acesso administrativo ao host de produção.
2. Executar todos os comandos como usuário `root` no host de produção; não usar `sudo` parcial, nem os caminhos de homologação.
3. Ter acesso de teste autorizado à aplicação de produção para a validação final.

## Banco de dados

Não há migration, DDL ou DML de dados. A única alteração é `ALTER USER 'app'@'%'`, que troca a senha da conta e não afeta grants nem dados.

## Pré-checagem — auditoria somente leitura

Executar antes da janela e de novo imediatamente antes da etapa 1. O bloco abaixo pode ser colado inteiro no terminal SSH: ele roda em um `bash` separado (um erro não fecha a sessão), não altera arquivos, containers nem o banco, e não imprime senhas nem hashes — cada senha é apenas comparada com `MARIADB_PASSWORD` e reportada como `igual`, `DIFERENTE` ou `vazio`.

```bash
BASE=/opt bash <<'AUDIT'
set -uo pipefail
MARIADB_ENV="$BASE/lowify/data_layer/mariabd/.env"
MARIADB_CONTAINER="${MARIADB_CONTAINER:-data-layer-mariadb}"
[ -r "$MARIADB_ENV" ] || { echo "Não encontrei $MARIADB_ENV (ajuste BASE)"; exit 1; }

env_get() {
  awk -F= -v k="$2" '$1==k {sub(/^[^=]*=/, ""); v=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v);
    q=sprintf("%c",39); if ((substr(v,1,1)=="\"" && substr(v,length(v),1)=="\"") || (substr(v,1,1)==q && substr(v,length(v),1)==q)) v=substr(v,2,length(v)-2);
    print v; exit}' "$1"
}
cmp_secret() { if [ -z "$1" ]; then echo "vazio"; elif [ "$1" = "$2" ]; then echo "igual"; else echo "DIFERENTE"; fi; }

DB_USER="$(env_get "$MARIADB_ENV" MARIADB_USER)"
DB_PASS="$(env_get "$MARIADB_ENV" MARIADB_PASSWORD)"
ROOT_PASS="$(env_get "$MARIADB_ENV" MARIADB_ROOT_PASSWORD)"
echo "Host: $(hostname)   BASE=$BASE   conta compartilhada: ${DB_USER:-<não definida>}"
sql() { docker exec -e MYSQL_PWD="$ROOT_PASS" "$MARIADB_CONTAINER" mariadb -uroot --batch --skip-column-names -e "$1" 2>&1; }

echo; echo "== 1. Contas '$DB_USER' no MariaDB"
sql "SELECT CONCAT(User,'@',Host) FROM mysql.user WHERE User='${DB_USER}';"

echo; echo "== 2. Bancos com privilégio para '$DB_USER'"
sql "SELECT DISTINCT CONCAT(Db,'  (',Host,')') FROM mysql.db WHERE User='${DB_USER}' ORDER BY 1;"
sql "SELECT CONCAT('*GLOBAL* Select=',Select_priv,' Insert=',Insert_priv,' Super=',Super_priv) FROM mysql.user WHERE User='${DB_USER}';"

echo; echo "== 3. Conexões ativas de '$DB_USER' por origem e banco"
printf '%-16s %-28s %-24s %s\n' IP CONTAINER BANCO CONEXOES
sql "SELECT SUBSTRING_INDEX(HOST,':',1), IFNULL(DB,'-'), COUNT(*) FROM information_schema.PROCESSLIST WHERE USER='${DB_USER}' GROUP BY 1,2 ORDER BY 1;" \
| while IFS=$'\t' read -r ip db n; do
    name="$(docker ps -q | xargs -r docker inspect -f '{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' \
            | awk -v ip="$ip" '{for(i=2;i<=NF;i++) if ($i==ip) {sub(/^\//,"",$1); print $1; exit}}')"
    printf '%-16s %-28s %-24s %s\n' "$ip" "${name:-?}" "$db" "$n"
  done

echo; echo "== 4. Containers em execução que usam '$DB_USER'"
printf '%-62s %-20s %-24s %s\n' CONTAINER DB_HOST DB_DATABASE SENHA_vs_MARIADB_PASSWORD
for c in $(docker ps --format '{{.Names}}' | sort); do
  envs="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c")"
  u="$(printf '%s\n' "$envs" | sed -n 's/^\(DB_USERNAME\|DB_USER\|MYSQL_USER\)=//p' | head -1)"
  [ "$u" = "$DB_USER" ] || continue
  h="$(printf '%s\n' "$envs" | sed -n 's/^\(DB_HOST\|MYSQL_HOST\)=//p' | head -1)"
  d="$(printf '%s\n' "$envs" | sed -n 's/^\(DB_DATABASE\|MYSQL_DATABASE\)=//p' | head -1)"
  p="$(printf '%s\n' "$envs" | sed -n 's/^\(DB_PASSWORD\|MYSQL_PASSWORD\)=//p' | head -1)"
  printf '%-62s %-20s %-24s %s\n' "$c" "$h" "$d" "$(cmp_secret "$p" "$DB_PASS")"
done

echo; echo "== 5. Arquivos .env sob $BASE com DB_USERNAME=$DB_USER"
printf '%-70s %-20s %-24s %s\n' ARQUIVO DB_HOST DB_DATABASE SENHA_vs_MARIADB_PASSWORD
find "$BASE" -type f -name .env -not -path '*/vendor/*' -not -path '*/node_modules/*' -print0 2>/dev/null \
| while IFS= read -r -d '' f; do
    [ "$(env_get "$f" DB_USERNAME)" = "$DB_USER" ] || continue
    printf '%-70s %-20s %-24s %s\n' "$f" "$(env_get "$f" DB_HOST)" "$(env_get "$f" DB_DATABASE)" \
      "$(cmp_secret "$(env_get "$f" DB_PASSWORD)" "$DB_PASS")"
  done

echo; echo "== 6. Nomes de rede do $MARIADB_CONTAINER"
docker inspect "$MARIADB_CONTAINER" -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}: {{$v.Aliases}}{{println}}{{end}}'
AUDIT
```

Critérios para seguir:

1. **Seção 1:** a conta deve ser `app@%`. Se o host for outro, ajustar o `ALTER USER` da etapa 2–5 para o host retornado.
2. **Seções 3 e 4:** todo container listado deve pertencer a um dos 12 projetos da tabela. Containers de `services-banking-defense` e `services-platform` não devem aparecer; se aparecerem, a confirmação da equipe de produção está desatualizada e a execução para até que se decida.
3. **Container fora da tabela usando `app`:** não executar. Decidir explicitamente entre incluí-lo na parada e retomada (precisa ter `docker-compose.yml` e `.env` em disco) ou aceitá-lo fora, sabendo que perderá acesso ao banco após a rotação.
4. **`DIFERENTE` antes da rotação:** o consumidor já está com senha divergente ou aponta para outro servidor; investigar antes de seguir.
5. **Seção 5:** conferir a lista de `.env` que a etapa 2 vai alterar; arquivos fora dos 12 projetos devem ser compreendidos (ex.: diretórios `.deploy/`).

## Sequência de execução

### 1. Parar ingresso e consumidores

Registrar os Compose projects que efetivamente estavam ativos. O arquivo de inventário é a fonte de verdade para a retomada: um projeto que já estava parado não será iniciado ao final. Não parar o MariaDB nem o Redis.

Os comandos `docker compose` dentro de laços `while read` recebem `</dev/null`; sem isso, o `docker compose` pode consumir o restante do inventário pela entrada padrão e pular projetos.

As checagens não usam `docker compose ... | grep -q`: com `pipefail`, o `grep -q` encerra na primeira linha, o `docker compose` recebe SIGPIPE e o pipeline falha de forma intermitente — tanto acusando falha inexistente quanto escondendo um erro de autenticação real.

```bash
rotation_active_projects=/tmp/lowify-rotation-active-projects
: >"$rotation_active_projects"

for project_dir in \
  /opt/lowify/edge/edge-gateway \
  /opt/lowify/edge/edge-webhook \
  /opt/lowify/services/services-account \
  /opt/lowify/services/services-auth \
  /opt/lowify/services/services-notifications \
  /opt/lowify/services/services-commerce \
  /opt/lowify/services/service-commerce-v2 \
  /opt/lowify/services/services-wallet \
  /opt/lowify/services/services-banking \
  /opt/lowify/services/services-banking-v2 \
  /opt/lowify/front/dashboard-seller \
  /opt/lowify/front/front-member-area; do
  (
    cd "$project_dir"
    if [ -n "$(docker compose ps --status running -q </dev/null)" ]; then
      printf '%s\n' "$project_dir" >>"$rotation_active_projects"
    fi
  )
done

echo "--- projetos ativos registrados:"
cat "$rotation_active_projects"

date +%s%3N >/tmp/lowify-gateway-rotation-start-ms

while IFS= read -r project_dir; do
  (cd "$project_dir" && docker compose stop </dev/null)
done <"$rotation_active_projects"

echo "--- containers ainda em execução:"
docker ps --format '{{.Names}}' | sort
```

Confirmar que o inventário contém todos e apenas os projetos que estavam em execução, e que nenhum container dos 12 projetos segue em execução. **Guardar uma cópia da lista impressa** (no registro da janela): se algo falhar adiante, é ela que diz o que precisa ser retomado.

### 2 a 5. Rotacionar, validar, retomar e reabrir o gateway

As etapas 2 a 5 formam **um único bloco**, para colar inteiro no terminal. Motivos:

- a senha nova vive apenas num arquivo temporário apagado ao final do bloco; ela precisa existir da geração até a validação;
- o bloco roda em um `bash` separado: `set -euo pipefail` interrompe o bloco no primeiro erro **sem fechar a sessão SSH**, e o que falhou fica na tela;
- em qualquer falha antes da etapa 4, nada é retomado: gateway e consumidores continuam parados, como exige o procedimento.

Os arquivos de inventário em `/tmp` só são apagados quando o bloco termina com sucesso; numa falha eles permanecem para orientar a correção manual.

```bash
bash <<'ROTATION'
set -euo pipefail
umask 077
rotation_secret_file="$(mktemp)"
client_config_file="$(mktemp)"
trap 'rm -f "$rotation_secret_file" "$client_config_file"' EXIT
printf '%s' "$(openssl rand -hex 32)" >"$rotation_secret_file"

# ---------- 2. Gerar a senha e sincronizar configurações ----------
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
  # Reescreve o conteúdo no próprio arquivo: mantém dono, grupo, modo, ACLs e
  # inode (ex.: .env pertencente a www-data). Não usar mv aqui.
  cat "$temp_file" >"$env_file" && rm -f "$temp_file"
}

echo "=== ETAPA 2"
while IFS= read -r -d '' env_file; do
  username="$(awk -F= '$1=="DB_USERNAME" {v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); q=sprintf("%c", 39); if ((substr(v, 1, 1)=="\"" && substr(v, length(v), 1)=="\"") || (substr(v, 1, 1)==q && substr(v, length(v), 1)==q)) v=substr(v, 2, length(v)-2); print v; exit}' "$env_file")"
  [ "$username" = app ] || continue
  update_password "$env_file" DB_PASSWORD
  echo "atualizado: $env_file"
done < <(find /opt -type f -name .env -not -path '*/vendor/*' -not -path '*/node_modules/*' -print0)

update_password /opt/lowify/data_layer/mariabd/.env MARIADB_PASSWORD
echo "atualizado: /opt/lowify/data_layer/mariabd/.env (MARIADB_PASSWORD)"

# ---------- 3. Alterar a senha persistida no MariaDB e validar ----------
echo "=== ETAPA 3"
set -a
. /opt/lowify/data_layer/mariabd/.env
set +a

{
  printf "ALTER USER '%s'@'%%' IDENTIFIED BY '" "$MARIADB_USER"
  cat "$rotation_secret_file"
  printf "';\n"
} | docker exec -i -e MYSQL_PWD="$MARIADB_ROOT_PASSWORD" data-layer-mariadb mariadb -uroot
echo "ALTER USER ok"

{
  printf '[client]\nuser=%s\npassword=' "$MARIADB_USER"
  cat "$rotation_secret_file"
  printf '\nhost=data-layer-mariadb\n'
} >"$client_config_file"
chmod 600 "$client_config_file"

docker run --rm --network data_net -v "$client_config_file:/tmp/client.cnf:ro" mariadb:11.8 \
  mariadb --defaults-extra-file=/tmp/client.cnf -e 'SELECT 1;' lowify </dev/null

# ---------- 4. Retomar somente os componentes que estavam ativos ----------
echo "=== ETAPA 4"
restart_if_previously_active() {
  local project_dir="$1"
  grep -Fxq "$project_dir" /tmp/lowify-rotation-active-projects || return 0
  (cd "$project_dir" && docker compose up -d --force-recreate </dev/null)
}

restart_if_previously_active /opt/lowify/services/services-account
restart_if_previously_active /opt/lowify/services/services-auth
restart_if_previously_active /opt/lowify/services/services-notifications
restart_if_previously_active /opt/lowify/services/services-commerce
restart_if_previously_active /opt/lowify/services/service-commerce-v2
restart_if_previously_active /opt/lowify/services/services-wallet
restart_if_previously_active /opt/lowify/services/services-banking
restart_if_previously_active /opt/lowify/services/services-banking-v2
restart_if_previously_active /opt/lowify/edge/edge-webhook
restart_if_previously_active /opt/lowify/front/dashboard-seller
restart_if_previously_active /opt/lowify/front/front-member-area

# ---------- 5. Validar consumidores e reabrir o gateway ----------
echo "=== ETAPA 5"
sleep 10
auth_error_pattern='access denied|authentication failed|sqlstate\[hy000\] \[1045\]'

while IFS= read -r project_dir; do
  [ "$project_dir" = /opt/lowify/edge/edge-gateway ] && continue
  cd "$project_dir"
  if [ -z "$(docker compose ps --status running -q </dev/null)" ]; then
    echo "FALHA: nada em execução em $project_dir — gateway permanece parado"; exit 1
  fi
  if docker compose logs --since 5m </dev/null 2>&1 | grep -iE "$auth_error_pattern" >/dev/null; then
    echo "FALHA: erro de autenticação MariaDB em $project_dir — gateway permanece parado"; exit 1
  fi
  echo "ok: $project_dir"
done </tmp/lowify-rotation-active-projects

if grep -Fxq /opt/lowify/edge/edge-gateway /tmp/lowify-rotation-active-projects; then
  cd /opt/lowify/edge/edge-gateway
  docker compose up -d --force-recreate </dev/null
  sleep 10
  if [ -z "$(docker compose ps --status running -q </dev/null)" ]; then
    echo "FALHA: gateway não está em execução"; exit 1
  fi
  if docker compose logs --since 5m </dev/null 2>&1 | grep -iE "$auth_error_pattern" >/dev/null; then
    echo "FALHA: erro de autenticação MariaDB no gateway"; exit 1
  fi
  echo "ok: /opt/lowify/edge/edge-gateway"
  start_ms=$(cat /tmp/lowify-gateway-rotation-start-ms)
  end_ms=$(date +%s%3N)
  awk -v start="$start_ms" -v end="$end_ms" \
    'BEGIN { printf "gateway_downtime_seconds=%.3f\n", (end - start) / 1000 }'
else
  printf '%s\n' 'gateway estava parado antes da janela; permaneceu parado.'
fi

rm -f /tmp/lowify-gateway-rotation-start-ms /tmp/lowify-rotation-active-projects
echo "=== ROTAÇÃO CONCLUÍDA"
ROTATION
```

Leitura do resultado:

- **`=== ROTAÇÃO CONCLUÍDA`** no final: seguir para a validação pós-execução e registrar `gateway_downtime_seconds`.
- **Falha na etapa 2** (antes de `ALTER USER ok`): a senha do MariaDB ainda é a antiga, mas parte dos `.env` pode já ter a nova. Rodar a auditoria; não retomar consumidores até `.env` e banco estarem alinhados.
- **Falha na etapa 3** (sem `1` após `ALTER USER ok`): manter tudo parado; corrigir a conta, host ou configuração divergente. Não reverter a senha automaticamente.
- **Falha na etapa 5:** os consumidores anteriores ao que falhou já estão recriados; o gateway continua parado. Corrigir o componente indicado (ver Rollback) e retomar manualmente os que restarem do inventário em `/tmp/lowify-rotation-active-projects`, gateway por último.

### 6. Auditoria pós-execução

Rodar novamente o bloco da pré-checagem. Todos os containers e `.env` dos 12 projetos devem aparecer como `igual`. Qualquer `DIFERENTE` restante é um consumidor fora do escopo que ficou com a senha antiga e perderá acesso ao banco.

## Validação pós-execução

Validação feita por uma pessoa com conta de teste autorizada; não exige terminal.

1. Abra a aplicação de produção e faça login com a conta de teste. **Esperado:** o login conclui e a tela inicial carrega. Se aparecer erro ou a tela ficar carregando, avise o operador da janela antes de qualquer outro teste.
2. Abra o dashboard do seller. **Esperado:** a página carrega com os dados da conta (vendas, saldo). Página em branco ou mensagem de erro: avise o operador.
3. Abra a área de membros. **Esperado:** a lista de conteúdos carrega normalmente.
4. No dashboard, abra a tela de saldo ou extrato. **Esperado:** os valores aparecem como antes da manutenção.

Conferência técnica complementar (opcional, para o operador): `gateway_downtime_seconds` registrado e a auditoria pós-execução sem `DIFERENTE` nos 12 projetos.

## Execução de referência em homologação

Executado em 2026-11-12 na VPS de homologação (caminhos em `/root/opt`), com o procedimento equivalente ao bloco das etapas 2 a 5:

- os 12 projetos estavam ativos e foram parados e recriados; MariaDB e Redis não foram tocados;
- 14 `.env` atualizados (os 12 projetos mais `services/.deploy/services-auth-jwt` e `services/.deploy/services-account-jwt`) e o `MARIADB_PASSWORD`;
- validação de login retornou `1`; nenhum erro de autenticação nos logs;
- indisponibilidade do gateway: **224 segundos**;
- `front-docs-app` foi deixado de fora por decisão explícita: usa `app` no banco `lowify`, mas não tem `docker-compose.yml` em disco e ficou com a senha antiga.

Segunda execução em homologação, no mesmo dia, com este documento: pré-checagem e etapas 1 a 4 sem desvios; a etapa 5 acusou falha falsa em `dashboard-seller` (todos os containers estavam em execução) por causa do `grep -q` com `pipefail`. A validação foi concluída manualmente com a checagem corrigida, o gateway foi reaberto (indisponibilidade de **251 segundos**) e a auditoria pós-execução ficou limpa, exceto `front-docs-app`. Depois disso: as checagens passaram a não usar `grep -q` em pipeline e a gravação dos `.env` passou de `mv` para `cat >`, preservando o arquivo original e seu dono (ex.: `www-data`).

Achados que motivaram esta revisão: o `trap` da etapa 3 apagava o inventário ao fechar o shell, impedindo as etapas 4 e 5 em sessões separadas; `docker compose` dentro de `while read` podia consumir o inventário; a checagem de erro do gateway não interrompia a execução; e havia consumidores fora de qualquer lista, visíveis só pela auditoria.

## Rollback

Não há rollback automático da senha. Se um consumidor falhar após a rotação, manter o gateway pausado, corrigir o `.env` desse consumidor para a senha nova e recriar somente esse componente com `docker compose up -d --force-recreate` (sem `--build`). Para confirmar qual `.env` diverge sem expor valores, usar a auditoria (seção 5). Não apagar volumes, dados, bancos, Redis, filas ou logs.
