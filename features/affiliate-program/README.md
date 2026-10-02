# Feature — Programa de afiliados

> Status: em evolução
> Última atualização: 2026-10-02
> Confiança: confirmada no código

## Objetivo

Permitir que um produtor habilite afiliados para um produto, controle aprovação, comissão, ofertas e privacidade, e atribua vendas originadas por esses afiliados. A feature inclui visualização para produtor e afiliado, comissão financeira e configurações próprias de entrega/recuperação de venda.

## Fluxo principal

```text
Produtor configura programa por produto
-> afiliado abre convite e solicita afiliação
-> aprovação automática ou manual cria afiliação ativa
-> afiliado divulga link/ofertas autorizadas
-> checkout atribui affiliate_id à venda
-> Commerce V2 cria sales_affiliates
-> evento pago retém/libera em carteira ou conclui gateway split
-> dashboards, notificações e relatórios exibem o resultado
```

## Componentes e responsabilidades

| Componente | Responsabilidade | Entrada/saída relevante |
| --- | --- | --- |
| `dashboard-seller` | Configura programa e oferece telas de afiliado, produtor, venda e relatório. | Dashboard e rotas de afiliados. |
| `edge-public-api` | Expõe rotas, resolve o usuário autenticado pelo JWT e encaminha ao Commerce V2. | `/affiliates/*` e rotas de programa em `/products/*`. |
| `services-commerce-v2` | Persiste programa/afiliação, valida estados, processa venda, comissão e regras de notificações. | `affiliates`, `sales.affiliate_id` e `sales_affiliates`. |
| Carteira/gateway | Recebe a consequência financeira da comissão. | `wallet` ou `gateway_split`. |

## Contratos e autorização

O programa aceita `approval_type` manual ou automático e configura comissão, `pay_upsell` e `expose_buyer_data`. Um convite só aceita usuário seller válido; a solicitação do próprio produtor é recusada. Uma solicitação existente em estado pendente ou aprovado para o mesmo produto e usuários é recusada.

As rotas públicas de afiliado resolvem o identificador do usuário pelo payload JWT e acrescentam esse identificador antes de encaminhar a requisição. Operações de gestão de afiliado usam o usuário autenticado como proprietário; detalhes de produto afiliado usam o usuário autenticado como afiliado.

## Dados e processamento assíncrono

`affiliates` registra produto, produtor, afiliado, estado, comissão e código. A venda recebe `affiliate_id`. `sales_affiliates` possui unicidade por venda e registra valor, percentual, estado, taxas e método de liquidação.

Para carteira, o evento de pagamento coloca a comissão em retenção até a data de liberação; o processo de liberação publica uma operação de extrato e marca o registro como liberado de forma condicional. Para `gateway_split`, o checkout cria o settlement e o evento pago marca a comissão como liberada no fluxo do split. O valor da comissão é calculado a partir da venda e do percentual gravado para a afiliação no momento da criação do registro.

## Operação e validação

O plano de validação integrada e carga controlada está em [Plano de QA do programa de afiliados](../../plans/affiliate-program-qa/README.md). A validação deve ocorrer em homologação/sandbox e precisa cobrir autorização, atribuição, idempotência, conciliação e filas, sem pagamentos ou dados reais.

## Limitações e pendências

- Este mapa descreve o comportamento confirmado no código; disponibilidade e regras comerciais dos gateways devem ser confirmadas no ambiente de teste.
- A performance sob volume ainda precisa ser medida formalmente na rodada de QA.
- A regra operacional para programas desativados com links históricos deve ser confirmada nos testes integrados antes de qualquer decisão comercial baseada nela.

## Referências

- `services-commerce-v2/app/Http/Controller/ProductAffiliateProgramController.php`
- `services-commerce-v2/app/Http/Controller/AffiliateController.php`
- `services-commerce-v2/app/Application/UseCase/Affiliate/RequestAffiliateInviteUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPaidSaleEventTransferUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ReleaseDueSaleAffiliateTransfersUseCase.php`
- `edge-public-api/app/Http/Controllers/AffiliateController.php`
- `dashboard-seller/app/services/AffiliateDashboardService.php`
