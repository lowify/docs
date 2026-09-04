# Feature — integração Cielo

> Status: em evolução
> Última atualização: 2026-09-02
> Confiança: parcialmente confirmada

## Objetivo

Permitir onboarding de contas, cobrança por cartão, liquidação, disputas e webhooks pelos providers Cielo E-commerce e Pagar.me. A ativação efetiva de cada conta permanece condicionada à aprovação da conta bancária.

## Fluxo principal

```text
Dashboard/Checkout -> Gateway e Public API -> Account, Banking v2, Commerce v2 e Wallet -> MySQL/Redis -> Webhook -> Banking e notificações
```

## Componentes e responsabilidades

| Componente | Branch em homologação | Responsabilidade |
| --- | --- | --- |
| `dashboard-seller` | `feat-cielo-integration` | Onboarding e operação do seller. |
| `front-checkout` | `feat-cielo-integration` | Checkout por cartão. |
| `edge-gateway` | `feat-cielo-integration` | Roteamento e worker associado. |
| `edge-public-api` | `feat-cielo-integration` | Entrada pública e contexto de autenticação. |
| `edge-webhook` | `feat-cielo-integration` | Recebimento, assinatura e deduplicação de webhooks. |
| `services-account` | `feat-cielo-integration` | Conta bancária, documentos e revisão. |
| `services-banking-v2` | `feat-cielo-integration` | Providers, cobrança, recebíveis, estornos e disputas. |
| `services-commerce-v2` | `feat-cielo-integration` | Gateway, produto, liquidação e meios de pagamento. |
| `services-wallet` | `feat-cielo-integration` | Integração da carteira ao fluxo. |
| `services-notification` | `main` | Templates e migrations de notificação Cielo. |

`front-idv` permanece na `main` e está fora da publicação desta feature.

## Contratos e autorização

- O `edge-public-api` preserva o JWT recebido nos fluxos autenticados e encaminha o contexto ao serviço de destino.
- Webhooks Cielo e Pagar.me entram pelo `edge-webhook`.
- O webhook Pagar.me usa HTTP Basic Auth; o Nginx deve encaminhar o header `Authorization` ao PHP.

## Dados e processamento assíncrono

- `lowify`: contas bancárias, revisão, gateways, produto e liquidação.
- `services-banking`: providers, contas BaaS, cobranças, parcelas, alocações, estornos e evidências de disputa.
- Redis: tráfego assíncrono entre Gateway, Banking, Commerce e seus workers; mensagens não devem ser limpas durante a validação.

## Operação e validação

A preparação aplica os SQLs de `lowify` e `services-banking` antes de reconstruir os containers. Providers/gateways entram ativos, mas só ficam utilizáveis após aprovação da conta. O roteiro operacional está no [deploy Cielo](../../deploys/2026-09-02-cielo-integration/2026-09-02_CIELO_INTEGRATION_DEPLOY.md).

## Limitações e pendências

- 3DS permanece desabilitado até que todas as credenciais correspondentes sejam configuradas.
- A validação funcional de webhooks e de transações depende de credenciais e dados de teste válidos no ambiente.

## Referências

- `services-banking-v2/config/autoload/cielo_ecommerce.php`
- `edge-webhook`
- [Deploy Cielo](../../deploys/2026-09-02-cielo-integration/2026-09-02_CIELO_INTEGRATION_DEPLOY.md)
