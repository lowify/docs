# Homologação — administração e relatório de comunicações

## Objetivo

Publicar em homologação a configuração de provider por template de e-mail, o overview administrativo e o relatório agregado de e-mail e WhatsApp. O relatório não apresenta destinatários, conteúdo ou erros brutos.

## Componentes e referências

| Repositório | Branch | Commit |
| --- | --- | --- |
| `services-notification` | `feat/checkout-transparent-billing-whatsapp-audit` | `428ae90` |
| `services-account` | `feat/checkout-transparent-billing-whatsapp-audit` | `93d26fc` |
| `edge-public-api` | `feat/checkout-transparent-billing-whatsapp-audit` | `8ade30d` |
| `edge-gateway` | `feat/checkout-transparent-billing-whatsapp-audit` | `07d624f` |
| `dashboard-seller` | `feat/checkout-transparent-billing-whatsapp-audit` | `daf65cb` |

Todos os demais targets operáveis em `~/opt/lowify/` devem usar `main`. Este escopo exclui tudo fora desse diretório, incluindo os componentes do Checkout Transparente em `/root/opt/lowify-ct/` e `/root/opt/lowify-ct-webhook/`, além de `data_layer`.

## Alterações incluídas

- `services-notification`: providers disponíveis, persistência por template, endpoint de overview e agregação diária em Redis.
- `services-account`: migration que inicializa todas as flags globais de WhatsApp como ativas.
- `edge-public-api` e `edge-gateway`: rotas administrativas autenticadas.
- `dashboard-seller`: aba Sistema e relatório por período, template, provider, canal e falha.
- Cashflow: custo de R$ 0,10 para Pagar.me exclusivamente em Cash In.

## Pré-requisitos

- As variáveis de ambiente do provider Resend precisam estar declaradas em `services-notification`; os nomes estão documentados no `.env.example` do repositório.
- O usuário de homologação deve possuir perfil administrativo `1` ou `2`.
- O stash `codex/homologation-2026-09-29-preserve-pagarme-psp-doc` em `services-banking-v2` preserva uma alteração local preexistente e não deve ser removido durante esta homologação.

## Banco de dados

Executar a migration `2026_09_29_000001_enable_whatsapp_flow_settings.php` de `services-account`. Ela faz upsert das nove flags globais de WhatsApp com valor `1`; não há rollback automático de valores administrativos.

## Sequência de deploy

Modo de rebuild: incremental. Atualizar os quatro participantes na branch da feature e os demais targets operáveis de `~/opt/lowify/` em `main`. Executar `docker compose up --build -d` somente quando branch ou commit mudar.

Não operar caminhos fora de `~/opt/lowify/`, `data_layer`, banco, Redis ou infraestrutura.

## Validação pós-deploy

1. Acessar Configurações do sistema, aba **Sistema**, como administrador.
2. Confirmar que os providers aparecem e salvar um provider para um template de teste.
3. Abrir o relatório de comunicações e consultar um período com envios conhecidos.
4. Confirmar cards, série diária e agrupamentos de template/provider/WhatsApp/falhas.
5. Confirmar que usuário comum e colaborador não acessam as rotas administrativas.

## Rollback

Trocar os quatro participantes de volta para a referência anterior ou `main`, atualizar com fast-forward e reconstruir somente os containers alterados. Não apagar dados de `email_template`, `email_single`, `whatsapp_meta` nem chaves Redis; o cache expira em até 60 dias.
