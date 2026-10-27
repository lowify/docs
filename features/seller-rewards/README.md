# Feature — recompensas do Seller Dashboard

> Status: ativo
> Última atualização: 2026-10-26
> Confiança: confirmada no código

## Objetivo

Exibir a jornada de recompensas do vendedor, liberar o pedido de envio dos prêmios atingidos e mostrar no sidebar a próxima meta de faturamento.

## Fluxo principal

```text
Vendedor -> dashboard-seller/recompensas.php -> UserRewardLookupService
         -> tabela user_reward (ou cálculo de fallback) -> progresso e cards
Vendedor elegível -> recompensas_process.php -> tbl_premio_resgate
```

## Componentes e responsabilidades

| Componente | Responsabilidade | Entrada/saída relevante |
| --- | --- | --- |
| `dashboard-seller/recompensas.php` | Exibe a jornada, metas, imagens e formulário de resgate. | Saldo de recompensa, sessão e dados de resgates anteriores. |
| `dashboard-seller/recompensas_process.php` | Autoriza e persiste um pedido de prêmio. | Título do prêmio e dados de entrega; valida o saldo no servidor. |
| `dashboard-seller/sidebar.php` | Mostra o progresso resumido na navegação. | Cache de métricas da sessão. |
| `dashboard-seller/_sidebar_metrics.php` | Atualiza assincronamente as métricas do sidebar. | JSON com total, meta, progresso e restante. |
| `dashboard-seller/app/services/UserRewardLookupService.php` | Obtém o saldo de recompensa e solicita atualização quando necessário. | `user_reward`; fila configurável de atualização. |

## Metas atuais

As metas de progresso são R$ 1 mil, R$ 10 mil, R$ 100 mil, R$ 250 mil, R$ 500 mil, R$ 1 milhão, R$ 2,5 milhões, R$ 5 milhões e R$ 10 milhões. As metas resgatáveis começam em R$ 10 mil.

Os novos níveis de placa são:

- R$ 2,5 milhões: `PREMIAÇÃO ESMERALDA`;
- R$ 5 milhões: `PREMIAÇÃO RUBI`;
- R$ 10 milhões: `PREMIAÇÃO BLACK DIAMOND`.

Os nomes dos prêmios formam o contrato entre a interface, a lista de validação de `recompensas_process.php` e `tbl_premio_resgate`; devem ser alterados de forma coordenada.

## Contratos e autorização

`recompensas_process.php` aceita apenas `POST` de usuário autenticado. O endpoint confere se o título existe na lista de níveis e se o saldo atual cobre a meta antes de inserir o resgate. Também impede novo pedido do mesmo título para o mesmo usuário.

## Dados e processamento assíncrono

`tbl_premio_resgate` registra os pedidos e seus dados de envio. `UserRewardLookupService` prefere o saldo mais recente em `user_reward`; na indisponibilidade, calcula um fallback e pode publicar uma solicitação de atualização na fila definida pela configuração do serviço.

O sidebar conserva a métrica na sessão e a atualiza por `_sidebar_metrics.php`; por isso, uma sessão que já possuía o cache pode precisar da atualização AJAX ou de nova sessão para refletir uma meta recém-adicionada.

## Operação e validação

Validar sintaxe PHP dos quatro arquivos do dashboard e confirmar visualmente os três novos cards e seus links de imagem. Para cada novo nível, verificar que o botão de resgate só aparece após atingir a meta e que uma segunda solicitação é recusada.

## Limitações e pendências

As definições dos níveis são repetidas entre a página, o endpoint de resgate e os cálculos do sidebar. Uma nova meta exige atualizar essas listas de forma consistente.

## Referências

- `dashboard-seller/recompensas.php`
- `dashboard-seller/recompensas_process.php`
- `dashboard-seller/sidebar.php`
- `dashboard-seller/_sidebar_metrics.php`
- `dashboard-seller/app/services/UserRewardLookupService.php`
