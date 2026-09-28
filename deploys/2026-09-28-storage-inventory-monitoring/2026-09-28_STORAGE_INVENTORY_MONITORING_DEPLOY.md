# Deploy — Monitoramento local de armazenamento

## Objetivo

Instalar uma coleta recorrente, somente leitura, de disco, Docker e MariaDB na
VPS de produção. Cada execução grava um relatório local; nenhum endpoint HTTP,
credencial ou comando remoto é exposto.

O relatório permite identificar espaço disponível, inodes, volumes Docker,
logs JSON de containers e tamanho por banco no MariaDB principal. Relatórios
com mais de 30 dias são removidos pelo próprio coletor para não virarem uma
nova fonte de consumo de disco.

## Componentes e referências

| Artefato | Referência |
| --- | --- |
| Pacote standalone | `artifacts/` nesta mesma pasta; não requer alteração nem deploy de `data_layer` |

Não há alteração de front, edge, serviço de domínio, rota, JWT, fila ou
contrato de aplicação.

## Alterações incluídas

- `artifacts/storage_inventory.sh`: inventário somente leitura, com timeout
  individual para operações potencialmente lentas.
- `artifacts/monitoring/run_storage_inventory.sh`: executa a coleta, grava os
  relatórios com permissão restrita e retém 30 dias.
- `artifacts/monitoring/crontab.example`: agenda execução a cada 15 minutos.

## Pré-requisitos

- Acesso administrativo à VPS de produção e ao Docker local.
- Bash, `docker`, `timeout`, `find`, `du`, `numfmt` e `mariadb` disponíveis no
  container `data-layer-mariadb`.
- Confirmar que o container MariaDB principal de produção se chama
  `data-layer-mariadb`. Se o nome for diferente, definir `MARIADB_CONTAINER`
  no crontab; não incluir senhas ou valores de variáveis no documento.
- Diretório de instalação adotado neste roteiro: `/opt/lowify-monitoring`.
  Ajustar somente se o operador possuir uma convenção de produção diferente.

## Banco de dados

Não há migration, DDL ou DML. A coleta executa apenas consultas em
`information_schema.tables` para somar dados e índices por banco.

## Sequência de deploy

1. Descompacte o ZIP deste pacote e copie a pasta `artifacts/` para a VPS, em
   `/opt/lowify-monitoring/`.
2. Como `root`, restrinja as permissões e prepare o diretório de relatórios:

   ```bash
   chmod 755 /opt/lowify-monitoring/storage_inventory.sh
   chmod 755 /opt/lowify-monitoring/monitoring/run_storage_inventory.sh
   mkdir -p /var/log/lowify-storage-inventory
   chmod 700 /var/log/lowify-storage-inventory
   ```

3. Faça uma execução manual. Ela deve concluir sem reiniciar containers:

   ```bash
   /opt/lowify-monitoring/monitoring/run_storage_inventory.sh
   ```

4. Confirme que foi criado um arquivo `storage-AAAAMMDD-HHMMSS.txt` em
   `/var/log/lowify-storage-inventory/` e que ele contém as seções `DISK`,
   `DOCKER FOOTPRINT` e `MARIADB DATABASES`.
5. Instale o agendamento no `crontab` de `root`, ajustando o caminho do
   exemplo para o diretório de produção:

   ```cron
   */15 * * * * /opt/lowify-monitoring/monitoring/run_storage_inventory.sh >> /var/log/lowify-storage-inventory/cron.log 2>&1
   ```

6. Após 20 minutos, confirme que há dois relatórios com horários diferentes e
   que `cron.log` não contém erro.

## Validação pós-deploy

1. Peça ao operador para abrir a pasta `/var/log/lowify-storage-inventory/`.
   Ele deve ver um relatório novo a cada 15 minutos.
2. Abra o relatório mais recente e confirme que a primeira seção mostra o
   espaço livre do disco e que as seções Docker e MariaDB possuem dados.
3. Confirme que a aplicação continua acessível normalmente e que nenhum
   container foi reiniciado durante a execução manual.
4. Se uma seção indicar `unavailable` ou `timed out`, a coleta continua válida;
   encaminhe essa linha ao responsável pela infraestrutura para investigar o
   componente específico.

## Segurança e operação

- Não exponha esses scripts via rota HTTP nem aceite comandos recebidos por
  `curl`.
- Os relatórios usam `umask 077` e devem permanecer acessíveis apenas ao
  operador autorizado.
- Antes de compartilhar um relatório fora da infraestrutura, revise nomes de
  bancos, containers e caminhos internos.

## Rollback

1. Remova somente a linha adicionada ao `crontab` de `root`.
2. Mantenha os relatórios existentes para investigação ou mova-os para um
   local aprovado pela equipe.
3. Remova `/opt/lowify-monitoring` apenas após confirmar que o cron foi
   removido. Não apagar volumes Docker, logs de containers ou dados de banco.
