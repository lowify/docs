# Homologação — Acesso web e e-mail de entrega v3

## Objetivo

Publicar a feature `feat/checkout-email-direct-access` em homologação para validar o acesso direto ao conteúdo, o histórico Acesso web e o e-mail de entrega v3.

## Participantes

| Chave | Branch |
| --- | --- |
| services-commerce-v2 | `feat/checkout-email-direct-access` |
| services-notification | `feat/checkout-email-direct-access` |
| edge-gateway | `feat/checkout-email-direct-access` |
| edge-public-api | `feat/checkout-email-direct-access` |
| front-member-area | `feat/checkout-email-direct-access` |
| front-checkout | `feat/checkout-email-direct-access` |
| dashboard-seller | `feat/checkout-email-direct-access` |

Todos os demais targets operáveis do `homologation-map.yaml` devem ser sincronizados em `main`. `data_layer` e `checkout-transparent-infra` permanecem como estão; itens ausentes ou não mapeados não participam.

## Targets mantidos como estão

| Chave | Motivo |
| --- | --- |
| ct-webhook | Alteração local de outra frente de trabalho; não receberá pré-checagem adicional, Git ou Docker nesta homologação. |

## Banco de dados

O operador executa manualmente, no banco Commerce de homologação, os arquivos [DEPLOY.sql](sql/lowify/DEPLOY.sql) e [VALIDATE.sql](sql/lowify/VALIDATE.sql) deste diretório. Não executar migrations automáticas no Commerce.

Após o build do Notification e antes do `up`, executar sua migration normalmente:

```bash
cd /root/opt/lowify/services/services-notifications
docker compose run --rm services-notifications php bin/hyperf.php migrate --force
```

## Sequência

1. Pré-checar todos os targets operáveis que serão alterados. Se qualquer um estiver sujo, parar toda a operação.
2. Fazer `fetch`, validar todas as branches remotas e só depois trocar participantes para a feature e demais targets para `main`, sempre com `pull --ff-only`.
3. Reconstruir, se o commit tiver mudado: Commerce, Notification, Public API, Gateway, Área de Membros, Checkout e Dashboard. Embora os três fronts usem bind mount de código e OPcache com validação de timestamps, as imagens agora carregam configurações Apache (incluindo `ServerTokens Prod` e `ServerSignature Off`); após o Git, cada front alterado exige `docker compose up --build -d`.
4. Executar o SQL manual do Commerce, validar o resultado e rodar a migration do Notification.
5. Executar `docker compose up -d` para os serviços reconstruídos, em ordem: Commerce, Notification, Public API e Gateway.
6. Reconstruir sequencialmente cada front cujo commit mudou:

```bash
cd /root/opt/lowify/front/front-member-area
docker compose up --build -d
cd /root/opt/lowify/front/front-checkout
docker compose up --build -d
cd /root/opt/lowify/front/dashboard-seller
docker compose up --build -d
```

Nesta VPS, use o diretório do serviço antes do `docker compose`; a opção `-C` não é suportada pela versão instalada. Exemplos:

```bash
cd /root/opt/lowify/services/service-commerce-v2
docker compose build
cd /root/opt/lowify/services/service-commerce-v2
docker compose up -d
```

## Validação

1. Concluir uma compra de teste de conteúdo e confirmar o e-mail v3 com botão tokenizado.
2. Abrir o link e confirmar uma entrada Acesso web com origem Link de acesso.
3. Abrir um produto pela Área de Membros e confirmar origem Área de membros, sem duplicação ao recarregar na mesma sessão.
4. Validar Área de Membros para nova conta e conta existente.
5. Como admin 1 ou 2, ocultar um acesso; confirmar que o vendedor não o vê.
6. Abrir uma URL inexistente em Área de Membros, Checkout e Dashboard e confirmar a tela 404 clara, com lupa e atalho para suporte.
