# Fase 7 — Edges, Dashboard e operação

## Edge Gateway e Public API

| Camada | Pendências |
| --- | --- |
| `edge-public-api/routes/api.php` | Registrar blocos de rotas de configurações, créditos, recargas, reenvio e status; imports em ordem alfabética. |
| Controllers/clients Public API | Extrair `sub`/`permissao`, repassar identidade e chamar Account, Commerce, Wallet ou Banking V2. |
| `edge-gateway` | Espelhar/proxy das rotas consumidas pelo Dashboard, preservando autenticação e erros. |
| Autorização | Admin 1/2/4 reenvia gratuito; seller/colaborador somente no escopo permitido; nunca receber owner/author como fonte de verdade do browser. |

## Dashboard Seller

| Tela/arquivo candidato | Pendência |
| --- | --- |
| `product_form.php` | Seções RDC e entrega WhatsApp do produtor, preço efetivo somente leitura. |
| `affiliate_product_detail.php` | Mesmas configurações no contexto da afiliação. |
| `products.php` + `api/products_list.php` | Badge de RDC/entrega e summary em lote. |
| Nova página raiz `communication_credits.php` + view | Saldo, bloqueado, disponível/negativo, pacotes e geração PIX. |
| Nova página raiz `sale_notifications.php` + view | Lista de RDC e entregas, filtros e paginação. |
| `sale_detail.php` | Timeline de tentativas/canais, ação de reenvio seller/colaborador e regras de visibilidade. |
| `admin_sale_detail.php` | Timeline completa e seletor admin de e-mail/WhatsApp/both gratuito. |
| `actions/` | POST de reenvio e geração de recarga. |
| `api/` | Consultas dinâmicas de saldo, pacotes, status e histórico; não criar `api/sales/`. |

As novas páginas usam arquivo de entrada na raiz e view em `views/`. Chamadas ao Gateway durante renderização devem acontecer antes de qualquer output.

## Administração

- Admin 1/2 edita preços globais/overrides e, quando a pendência for resolvida, pacotes.
- Admin 1/2/4 faz reenvio gratuito, identificando autor e owner no histórico.
- Modal/tela de restrições controla feature flag por usuário via Account, não banco local.

## Operação e observabilidade

- Cards: créditos, bloqueios, saldo negativo, RDC enviados, entregas WhatsApp, timeouts, confirmações tardias e faltas de crédito.
- Consultas: por owner, venda, produto principal, canal, status, autor e período.
- Logs estruturados com `sale_delivery_attempt_id`, `sales_delivery.id`, dispatch RDC e `owner_user_id`.
- Métricas: hold criado/liberado/consumido, topups PIX, falhas, timeout, tardio e alertas deduplicados.

## Testes integrados

- Testar caminho Dashboard → Gateway → Public API → serviço com JWT de seller, afiliado, colaborador e admin.
- Testar PIX pago repetido, hold concorrente, callback Meta repetido/tardio e timeout.
- Após implementação, sugerir teste de compatibilidade em homologação; não executar sem autorização.

## Critérios de aceite

- [ ] Nenhuma tela chama serviço interno diretamente.
- [ ] Páginas respeitam owner/afiliação/admin e não expõem dados de outro usuário.
- [ ] Reenvio seller/colaborador é cobrável; admin é gratuito.
- [ ] Saldo e histórico exibem operações idempotentes da Wallet.
