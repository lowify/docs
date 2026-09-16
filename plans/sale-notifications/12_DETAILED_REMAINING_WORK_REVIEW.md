# Revisão detalhada — pendências de comunicações de venda

> Revisado em: 2026-09-10.
>
> Fonte: estado local das branches `feat/sale-notifications` no workspace.
> Não foi possível atualizar o remoto nesta revisão: a resolução de DNS para
> GitHub estava indisponível. Portanto, este documento não confirma commits que
> possam existir somente no remoto após o último `fetch` disponível localmente.
>
> “Implementado” significa que o caminho foi localizado no código. Não equivale
> a SQL aplicado, variáveis configuradas, provider homologado ou teste funcional
> executado.

## Resumo executivo

O núcleo de produto, créditos, funding, PIX, dispatch e interfaces do seller
está implementado no código. A feature ainda não está pronta para uma liberação
controlada porque faltam quatro blocos relevantes:

1. Administração: não existe ainda o caminho público/UI para configurar rollout,
   preços, overrides por seller e pacotes. Esta frente foi separada no arquivo
   [10_DASHBOARD_ADMIN_TASKS.md](10_DASHBOARD_ADMIN_TASKS.md).
2. Validação integrada: não há cobertura automatizada para Wallet, Banking V2,
   Commerce, Notifications, Webhook e edges; a maior parte da validação precisa
   ocorrer em homologação com SQL, Redis, PIX e callbacks reais.
3. Reenvio administrativo selecionável: o admin ainda não pode escolher e-mail,
   WhatsApp ou ambos pelo contrato gratuito previsto.
4. Preparação operacional: SQL manual, variáveis/templates de providers e
   observabilidade ainda precisam ser confirmados no ambiente.

Itens explicitamente adiados pelo produto — como resumo de comunicações na
listagem de produtos e resolução de produto no extrato — não são bloqueadores.

## Estado por domínio

| Domínio | Estado no código | Principal pendência |
| --- | --- | --- |
| Produto e afiliação | Implementado | Summary na listagem de produtos foi adiado. |
| Account | Implementado internamente | Exposição administrativa no Public API/Gateway e UI admin. |
| Wallet | Implementado no código | SQL e testes transacionais/concorrência. |
| Banking V2 | Implementado no código | Homologar criação, expiração, pagamento e callback PIX. |
| Commerce V2 | Fluxo principal implementado | Reenvio administrativo por canais e testes de estados assíncronos. |
| Notifications/Webhook | Fluxo implementado | Homologar providers/templates e callbacks duplicados/fora de ordem. |
| Dashboard Seller | Implementado, com QR local pendente de commit | Teste funcional das telas e dos contratos reais. |
| Dashboard Admin | Não implementado | Toda a Fase 10, descrita abaixo. |
| Deploy/operação | Não comprovado | Aplicar SQL, configurar env/templates e executar roteiro de homologação. |

## O que está implementado e deve ser preservado

### Regras comerciais e ownership

- Regras por produto para entrega e RDC, inclusive etapas e canais.
- Configuração equivalente no contexto de afiliação, reutilizando os componentes
  base do Dashboard.
- O owner de uma comunicação de venda afiliada é o afiliado; a configuração e o
  crédito do produtor não são herdados.
- RDC não usa Evolution: utiliza WhatsApp Business Platform/Meta e e-mail
  transacional.
- Venda elegível para RDC é `pending`, dentro de duas horas; a regra usa o item
  principal para decidir a configuração.
- O primeiro e-mail de entrega é gratuito. E-mail e WhatsApp de RDC usam o
  mesmo valor unitário configurado.

### Funding e créditos

- Créditos de comunicação possuem pacote, saldo, compra, razão, bloqueio,
  consumo, liberação, expiração e outbox.
- A ordem de funding é crédito de comunicação e, se permitido pelo owner,
  saldo disponível do seller. Checkout Transparente não usa saldo disponível.
- A preferência `sale_notifications_allow_seller_balance` é por usuário, com
  default efetivo `true`; fica em Perfil > Contas > Preferências.
- Entrega/RDC persistem origem, estado, referência e preço do funding.
- A cobrança ocorre em `sent_to_provider`; `delivered` e `read` permanecem
  eventos informativos e não consomem novamente.

### Experiência do seller

- Formulário de produto e afiliação para entrega/RDC.
- Página de créditos: saldo, bloqueado, disponível, pacotes, PIX, pagamento por
  saldo e polling de compra.
- Extrato de comunicações: entrega e RDC, filtros, paginação, status, funding,
  falha, sem retorno e confirmação tardia; usa `order_id` para abrir a venda e
  não resolve produto propositalmente.
- Timeline em `sale_detail` e `admin_sale_detail`, respeitando `owner_user_id`
  para seller e exibindo todos os itens para admin.
- Reenvio simples do seller pelo Commerce, sem o front gravar Redis/banco
  legado diretamente.

### QR Code PIX — pendente de commit local

Há uma alteração local no Dashboard Seller que gera QR Code PNG a partir do
PIX copia-e-cola quando o Banking não enviar uma imagem. Ela reutiliza a
biblioteca local de QR e não depende de API externa.

Arquivos locais ainda não commitados:

- `dashboard-seller/api/dashboard/communication-credits/pix-qr.php`
- `dashboard-seller/views/dashboard/communication_credits/index.php`

## Pendências obrigatórias para operar a feature

### P0 — administração e capacidade de lançamento

Sem a Administração, as configurações internas existem, mas não há como
administrar rollout e preços pela aplicação. Como o default de rollout é
desativado, isto bloqueia uma ativação segura por seller.

Esta pendência está **integralmente delegada e detalhada** em
[10_DASHBOARD_ADMIN_TASKS.md](10_DASHBOARD_ADMIN_TASKS.md). Para evitar
duplicidade, este arquivo mantém somente o impacto e a ordem global:

1. Criar os proxies administrativos no Public API e Gateway, restritos a admin
   1 e 2.
2. Criar “Comunicações de venda” em `admin_configs.php`, com global, overrides
   e pacotes.
3. Implementar o reenvio administrativo por seleção de canais e seu histórico.
4. Executar os testes de autorização, forwarding e interface definidos na Fase
   10.

O escopo da Fase 10 não redesenha Account/Wallet: as rotas internas já existem.

### P0 — persistência e homologação de dados

#### 4. Aplicar e auditar SQL manual

Os serviços principais utilizam SQL manual. Antes de subir processos, aplicar
os scripts em `docs/plans/sale-notifications/deploy/` em ambiente controlado e
registrar o resultado no documento de deploy.

Conferir especialmente:

- tabelas de créditos, pacotes, compras, razão, alertas e outbox da Wallet;
- colunas/índices de funding em `sales_delivery` e
  `sale_recovery_dispatches`;
- tabela de eventos de dispatch RDC e unicidade por venda/etapa/canal;
- existência e disponibilidade do tipo de extrato reservado para a feature;
- schema/migrations de Banking V2 e a integração isolada do Checkout
  Transparente, quando aplicável.

Não executar esse SQL sem o roteiro de deploy e backup/validação do ambiente.

#### 5. Configuração externa

Confirmar em homologação, sem versionar segredos:

- credenciais, conta padrão e templates Meta aprovados para etapa 1 e 2 de RDC;
- providers e templates Twig de e-mail primary/secondary;
- URLs e assinaturas entre Wallet, Banking V2, Commerce, Notifications,
  Webhook, Public API e Gateway;
- workers/processos para outbox, compra PIX, timeout de delivery, RDC e filas
  de outcome;
- durações configuradas: timeout Meta de 3 minutos, hold de 10 minutos, PIX
  de 2 horas e expiração da compra de 1 hora.

### P1 — reenvio administrativo por canais

O reenvio atual permite o fluxo simples do seller e a gratuidade do admin, mas
não implementa a seleção administrativa de canais nem todo o histórico de
autor. Esta é uma subtask da Fase 10; requisitos, contrato e cenários de aceite
estão exclusivamente em [10_DASHBOARD_ADMIN_TASKS.md](10_DASHBOARD_ADMIN_TASKS.md).

### P1 — testes de fluxos assíncronos

Na revisão local, apenas Account possui teste específico de notificações de
venda. Não foram encontrados testes focados nos demais repositórios.

Cobertura mínima a criar:

#### Wallet

- hold/release/consume idempotente por referência;
- concorrência de hold e bloqueio de saldo/crédito;
- expiração de hold;
- compra PIX repetida, compra pendente reutilizada e callback de pagamento
  duplicado/tardio;
- compra por saldo disponível, saldo insuficiente e saldo negativo tardio;
- publicação/retry da outbox e alerta de crédito insuficiente.

#### Banking V2

- mensagem de criação PIX repetida não cria cobrança nova;
- `expiration_seconds` da Wallet é repassado ao provider;
- PIX pago credita exatamente uma vez;
- provider/Wallet indisponível gera erro recuperável e não perde a compra.

#### Commerce V2

- produtor versus afiliado: regra e owner corretos;
- crédito prioritário, fallback de saldo permitido/bloqueado e Checkout
  Transparente sem saldo;
- e-mail RDC e WhatsApp criam hold antes do enqueue;
- `sent_to_provider` consome uma vez; eventos posteriores não duplicam consumo;
- `failed`, timeout e cancelamento liberam hold;
- callback tardio consome somente conforme a política existente;
- janela RDC, venda paga durante envio e etapas/canais válidos;
- paginação/filtros do extrato e isolamento por `owner_user_id`.

#### Notifications e Webhook

- Meta `sent`, `delivered`, `read`, `failed` e payload fora de ordem;
- callback duplicado e correlação delivery/RDC;
- e-mail primary/secondary e outcome antes/depois de provider reference;
- alerta de crédito insuficiente chega ao template de e-mail do seller;
- payload interno não é enviado à Meta.

#### Edges e Dashboard

- JWT/escopo de seller, afiliado, colaborador e admin;
- proxies preservam status e erro dos serviços;
- polling PIX e QR local;
- extrato, timeline e reenvio não expõem comunicação do afiliado ao produtor.

### P1 — teste de compatibilidade em homologação

Depois do SQL e da configuração, executar uma suíte coordenada com dados
sintéticos/reversíveis:

1. Admin habilita override e preço para um seller de teste.
2. Seller compra créditos via PIX, consulta o mesmo UUID enquanto pendente e
   recebe crédito uma única vez após confirmação.
3. Venda paga com entrega WhatsApp cria hold, envia e consome em
   `sent_to_provider`.
4. Timeout/falha libera hold e envia e-mail pelo provider secondary.
5. Venda `pending` gera RDC em e-mail/WhatsApp, respeita janela e ownership.
6. Webhook Meta de `delivered`/`read` posterior não gera nova cobrança.
7. Afiliado visualiza somente comunicações cujo owner é ele; produtor não as vê.
8. Admin consulta tudo e realiza reenvio gratuito com os canais selecionados.

Registrar executor, comandos, pré-condições, IDs sintéticos e limpeza no
documento de deploy. Não testar com uma venda real ou com saldo de usuário real.

## Pendências de baixo risco ou deliberadamente adiadas

### Summary na listagem de produtos — adiado

O endpoint de summaries existe, mas a exibição discreta na listagem de produtos
foi removida da prioridade por decisão de produto. Não bloqueia configuração,
envio, cobrança ou operação.

### Produto no extrato — fora de escopo atual

O extrato usa a venda e seu `order_id`; ele não resolve produto principal. Esta
é a decisão atual e evita uma consulta adicional. O produto pode ser consultado
no detalhe da venda.

### Métricas e observabilidade ampliada — recomendação posterior

Após a homologação, adicionar métricas por canal/status/funding, alertas de
falha de provider, lag de filas e dashboard operacional. Não é pré-requisito
para concluir a primeira liberação, desde que logs atuais e roteiro de suporte
sejam validados.

## Ordem recomendada de execução

1. Commitar o QR Code PIX do Dashboard Seller e reconciliar a `main` de Docs.
2. Executar integralmente [a Fase 10](10_DASHBOARD_ADMIN_TASKS.md): contratos
   administrativos, tela de configurações, pacotes e reenvio por canais.
5. Criar a suíte de testes unitários e de forwarding dos pontos críticos.
6. Preparar deploy: SQL, env, processos, templates e permissões.
7. Executar compatibilidade em homologação e corrigir divergências antes de
   qualquer rollout por seller.

## Referências

- [Fase 10 — Dashboard Admin](10_DASHBOARD_ADMIN_TASKS.md)
- [Fase 11 — Dashboard Seller](11_DASHBOARD_SELLER_TASKS.md)
- [Auditoria anterior](09_IMPLEMENTATION_AUDIT_AND_REMAINING_TASKS.md)
- Diretório de SQL/deploy: `docs/plans/sale-notifications/deploy/`
