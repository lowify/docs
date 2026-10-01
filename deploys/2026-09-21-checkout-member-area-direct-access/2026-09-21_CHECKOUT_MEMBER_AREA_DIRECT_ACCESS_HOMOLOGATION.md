# Homologação — Acesso direto ao conteúdo pós-pagamento

## Objetivo

Publicar em homologação o acesso direto ao conteúdo de produtos com entrega por
e-mail, os cookies de acesso, o modal pós-PIX e o histórico de acesso via link.

## VPS

root@217.216.87.77

## Branches por repositório

| Chave no mapa de homologação | Branch |
| --- | --- |
| services-commerce-v2 | feat/checkout-email-direct-access |
| dashboard-seller | feat/checkout-email-direct-access |
| front-checkout | feat/checkout-email-direct-access |
| front-member-area | feat/checkout-email-direct-access |
| Todos os demais targets de homologation-map.yaml | main |

Não participam desta operação os repositórios marcados como
absent_from_vps ou unmapped_vps_repositories no mapa oficial.

## Pré-requisito de banco

Aplicar as migrations do Commerce V2, incluindo:

- 20260916120000_add_cookie_to_sales_access_sessions.sql;
- 20260921120000_add_access_link_sales_delivery_statuses.sql.

## Sequência

1. Verificar que todos os repositórios mapeados na VPS estão limpos.
2. Buscar e validar as branches remotas declaradas.
3. Atualizar cada repositório com git switch e git pull --ff-only.
4. Reconstruir com Docker todos os componentes atualizados, exceto
   dashboard-seller, que recebe apenas a atualização Git.
5. Aplicar as migrations do Commerce V2 e validar os containers.

## Validação

1. Concluir um PIX de homologação para produto de entrega por e-mail.
2. Confirmar o modal de pagamento e o conteúdo em members.lowify.com.br/access.
3. Confirmar que o histórico da venda mostra Acesso via link.
4. Como admin de perfil 1 ou 2, ocultar e restaurar esse registro.
