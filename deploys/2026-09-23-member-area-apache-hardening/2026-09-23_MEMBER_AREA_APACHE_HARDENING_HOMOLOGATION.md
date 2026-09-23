# Homologação — hardening do Apache na Área de Membros

## Objetivo

Validar em homologação a redução de informações expostas pelo Apache na Área de Membros. A imagem deve responder `Server: Apache`, sem versão, sistema operacional ou assinatura em páginas de erro.

## Componentes e referências

| Repositório | Branch |
| --- | --- |
| front-member-area | `hotfix/member-area-apache-hardening` |

Todos os demais targets operáveis de `homologation-map.yaml` devem ser mantidos como estão e não receberão pré-checagem, Git ou Docker. `data_layer` e `checkout-transparent-infra` permanecem sem comandos por serem targets `hold`; itens ausentes e não mapeados também ficam fora da operação.

Modo de rebuild: incremental.

## Alterações incluídas

A configuração Apache da Área de Membros define `ServerTokens Prod` e `ServerSignature Off`. O Dockerfile instala a configuração com prefixo `zz-`, para que seja carregada após a configuração padrão de segurança da imagem Debian.

Não há alterações de rotas, JWT, banco, Redis, filas, variáveis de ambiente ou migrações.

## Pré-requisitos

- Branch remota `origin/hotfix/member-area-apache-hardening` disponível.
- Todos os targets operáveis da VPS sem mudanças locais antes da operação.

## Banco de dados

Nenhuma alteração de banco de dados.

## Sequência de homologação

1. Na VPS `root@217.216.87.77`, pré-checar somente `/root/opt/lowify/front/front-member-area` com `git status --porcelain=v1`, `git branch --show-current` e `git remote get-url origin`; interromper se houver mudança local, origem incorreta ou repositório inválido.
2. Executar `git fetch origin --prune` somente nesse repositório e confirmar `origin/hotfix/member-area-apache-hardening`.
3. Sincronizar o participante:

   ```bash
   cd /root/opt/lowify/front/front-member-area
   git switch hotfix/member-area-apache-hardening
   git pull --ff-only origin hotfix/member-area-apache-hardening
   docker compose up -d --build
   ```

4. Não executar qualquer comando nos demais targets, que foram explicitamente declarados como mantidos como estão.

## Validação pós-deploy

1. Abra a Área de Membros em homologação e confirme que ela continua carregando normalmente.
2. Abra as ferramentas do navegador, recarregue a página e confirme que o header `Server` não contém número de versão ou o termo `Debian`.
3. Se a aplicação não carregar, interrompa o teste e informe o erro; não altere banco, filas ou configurações para contorná-lo.

## Rollback

Na Área de Membros, retornar para `main`, atualizar com `git pull --ff-only origin main` e executar `docker compose up -d --build`. A alteração não possui efeitos persistentes em banco, cache ou filas.
