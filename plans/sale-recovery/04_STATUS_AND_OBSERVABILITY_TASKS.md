# Fase 4 — Status e observabilidade

## Dependências

Esta fase depende dos dispatches e eventos da Fase 3. Pode ser liberada antes da liquidação financeira: ela mostra o ciclo de envio, sem expor valores financeiros como condição para existir.

## Página de status de RDC

Criar uma página para acompanhar recuperações por WhatsApp oficial e e-mail.

### Informações exibidas

- Total de RDC enviados por período.
- Total sem retorno do provedor: dispatch em `sent_to_provider` sem evento posterior `confirmed`, `failed` ou `read`.
- Lista paginada: venda, produto principal, canal, etapa, destinatário mascarado, data/hora de envio e status atual.
- Filtros: período, produto, canal e status (`sent_to_provider`, `confirmed`, `failed`, `read`, `skipped`, `canceled`). `read` é evento posterior a `confirmed`, não uma nova cobrança.

### Visibilidade

- Produtor vê apenas dispatches de que é `owner_user_id`.
- Afiliado vê apenas dispatches de que é `owner_user_id`.
- Admin vê todos e identifica o responsável.
- O detalhe de venda normal continua ocultando RDC de afiliado do produtor; `admin_sale_detail` sempre exibe.

## Arquivos e rotas

| Arquivo/rota | Tipo | Responsabilidade |
| --- | --- | --- |
| Use case/repository de status em `services-commerce-v2` | Novo | Consultar dispatches + último evento, aplicar filtros, paginação e visibilidade. |
| `GET /sale-recovery/status` | Nova | Retornar cards e lista paginada ao usuário autenticado. |
| `dashboard-seller/sale_recovery_status.php` | Novo | Nova página de status de RDC. |
| `dashboard-seller/api/sale-recovery/status.php` | Novo | Proxy autenticado para o Commerce. |
| `dashboard-seller/sidebar.php` | Alterar | Adicionar acesso condicionado à feature flag efetiva. |
| Componentes de tabela e filtros | Novos | Renderizar cards, lista e estados dos canais oficiais. |
| Consulta de detalhes de venda | Alterar | Fornecer timeline com o filtro de visibilidade do seller e visão completa para admin. |

## Observabilidade e suporte

- Registrar métricas de dispatch criado, enviado ao provedor, confirmado, falho, ignorado por saldo e cancelado por mudança no estado da venda, segmentadas por canal.
- Manter consulta por venda, produto, responsável e referência do provedor para suporte.
- A timeline deve explicar `skip_reason` e erro do provedor em linguagem adequada à tela, sem expor dados sensíveis do destinatário.

## Critérios de aceite

- [ ] A página lista todos os dispatches oficiais do responsável, sem qualquer fluxo legado ativo.
- [ ] O card “sem retorno” corresponde a `sent_to_provider` sem resultado final posterior.
- [ ] Produtor, afiliado e admin enxergam somente os registros permitidos.
- [ ] O detalhe de venda respeita o isolamento do RDC do afiliado e o admin sempre tem visão completa.
- [ ] Um atendimento consegue localizar uma tentativa pela venda, pelo dispatch ou pela referência do provedor.
