# Instruções para o agente de implantação

Execute este pacote na VPS de produção como `root`. Esta é uma instalação local
de monitoramento, somente leitura; não faça deploy de aplicação, rebuild de
containers, restart de serviços, migration ou limpeza de dados.

## Procedimento obrigatório

1. Descompacte o ZIP em um diretório temporário seguro.
2. Crie o diretório de instalação e de relatórios:

   ```bash
   mkdir -p /opt/lowify-monitoring/monitoring
   mkdir -p /var/log/lowify-storage-inventory
   chmod 700 /var/log/lowify-storage-inventory
   ```

3. Copie `artifacts/storage_inventory.sh` para
   `/opt/lowify-monitoring/storage_inventory.sh` e copie o conteúdo de
   `artifacts/monitoring/` para `/opt/lowify-monitoring/monitoring/`.
4. Marque os scripts como executáveis:

   ```bash
   chmod 755 /opt/lowify-monitoring/storage_inventory.sh
   chmod 755 /opt/lowify-monitoring/monitoring/run_storage_inventory.sh
   ```

5. Execute uma coleta manual e confirme que ela não reiniciou containers:

   ```bash
   /opt/lowify-monitoring/monitoring/run_storage_inventory.sh
   docker ps --format '{{.Names}}\t{{.Status}}'
   ```

6. Confirme que há um relatório `storage-*.txt` em
   `/var/log/lowify-storage-inventory/`.
7. Instale no `crontab` de `root` exatamente a linha de
   `artifacts/monitoring/crontab.example`, sem duplicá-la.
8. Informe: caminho de instalação, caminho do primeiro relatório, resultado
   da execução manual e a linha de cron instalada.

## Limites

- Não exponha rota HTTP, webhook ou porta de rede.
- Não imprima nem altere segredos, `.env`, senhas de banco ou Redis.
- Se o container MariaDB principal não se chamar `data-layer-mariadb`, pare e
  informe o nome encontrado; não adivinhe o valor de `MARIADB_CONTAINER`.
