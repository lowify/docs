# Plano — abertura manual de contas BaaS

> Status: aprovado para implementação
> Última atualização: 2026-10-30
> Público: Produto, Operações e Engenharia

## Objetivo

Evitar a abertura automática de conta BaaS na Woovi, que passou a ser cobrada,
sem interromper o onboarding automático de Cielo Split. A abertura Woovi passa
a depender de uma decisão explícita na revisão da conta ou de uma ação manual
no overview administrativo do seller.

## Estado atual confirmado

- Ao completar o cadastro, `services-account` encadeia o evento
  `register_baas` em `account:user:events`.
- Sem provider explícito, o serviço Banking legado resolve `register_baas`
  como `woovi`. Esse é o envio automático que deve ser controlado.
- Após uma revisão de conta aprovada, o consumidor
  `AccountReviewApprovedQueueProcess` também cria `register_baas`.
- Cielo Split não usa esse caminho BaaS legado: sua abertura é enfileirada pelo
  fluxo de aprovação de conta bancária em `cielo_seller_onboarding`. Esse
  comportamento permanece automático e fora da nova flag.
- O fluxo existente de eventos já registra tentativas, retries e falhas. Não
  serão criadas filas paralelas.

## Decisões

| Tema | Decisão |
| --- | --- |
| Flag de Woovi | Criar `WOOVI_BAAS_AUTO_REGISTER_ENABLED`, com default `false`. |
| Cielo automático | Preservar integralmente o fluxo atual de Cielo Split. |
| Aprovação de review | Adicionar `send_to_woovi`; ausência ou `false` não abre Woovi. |
| Toggle | Começa sempre desmarcado e usa `InputToggle`, componente-base do Dashboard. |
| Abertura manual | Admin pode solicitar Woovi ou Cielo Split no overview do seller. |
| Pré-filtro | Não bloquear a solicitação por existência prévia de conta; a camada responsável pelo provider retorna o erro posterior quando aplicável. |
| Permissão | A ação de criação manual usa a mesma regra do módulo de contas BaaS: `admin_financial_providers` no Dashboard e JWT administrativo (1, 2 ou 4) no Public API. |

## Fluxo alvo

```text
Cadastro completo
  -> Cielo Split: fluxo automático atual, inalterado
  -> Woovi: somente se WOOVI_BAAS_AUTO_REGISTER_ENABLED=true

Revisão de conta aprovada
  -> toggle "Enviar conta para Woovi"
     -> marcado: evento register_baas com provider=woovi
     -> desmarcado: aprovação sem abertura Woovi

Overview administrativo -> Contas BaaS -> Criar envio
  -> Conta BaaS Woovi: solicita abertura Woovi
  -> Conta Split Cielo: solicita o onboarding Cielo usando a conta bancária aplicável
```

## Componentes envolvidos

| Repositório | Responsabilidade |
| --- | --- |
| `dashboard-seller` | Toggle de revisão, modal de criação manual, action PHP, feedback e controle de permissão. |
| `edge-gateway` | Rota autenticada e encaminhamento do pedido manual. |
| `edge-public-api` | Validação de JWT, payload e provider; proxy ao Account; encaminhamento de `send_to_woovi`. |
| `services-account` | Flag Woovi, decisão dos eventos automáticos, enfileiramento explícito no review e resolução da abertura manual Cielo/Woovi. |

## Contratos previstos

### Aprovação de review

`POST /account-reviews/{review_id}/approve` recebe:

```json
{
  "send_to_woovi": true
}
```

O identificador do revisor continua vindo do JWT no Public API; o Dashboard não
é uma fronteira de autorização.

### Abertura manual

Novo endpoint sob `/baas/accounts/` recebe `user_id` e o provider selecionado.
Os valores públicos iniciais são `woovi` e `cielo_split`. O serviço Account
traduz cada escolha para o fluxo já existente do provider, sem expor segredos
nem montar payloads de provider no Dashboard.

## Implementação por repositório

### `services-account`

1. Centralizar a leitura de `WOOVI_BAAS_AUTO_REGISTER_ENABLED` em configuração
   do domínio de revisão/eventos, com fallback `false`.
2. Impedir somente os disparos automáticos de `register_baas` quando a flag
   estiver desligada:
   - encadeamento de `AccountCompleteRegisterHandler`;
   - consumo pós-aprovação de review.
3. Manter o disparo explícito solicitado pelo toggle, sempre com provider
   `woovi`, independente da flag.
4. Criar um caso de uso administrativo para abertura manual:
   - Woovi usa o enfileiramento `register_baas` existente;
   - Cielo Split resolve uma conta bancária aplicável do seller e reutiliza o
     enfileiramento Cielo já empregado após a aprovação bancária.
5. Manter idempotência, retries e persistência em `user_events`; não limpar
   Redis nem alterar contratos de mensagens existentes.

### `edge-public-api`

1. Encaminhar `send_to_woovi` na aprovação de review.
2. Expor o endpoint de abertura manual, validando JWT administrativo, `user_id`
   positivo e provider permitido.
3. Encaminhar a chamada para o `services-account` e preservar status/erros.

### `edge-gateway`

1. Adicionar a rota manual sob o grupo `/baas`.
2. Preservar JWT, corpo e resposta no encaminhamento ao Public API.

### `dashboard-seller`

1. Inserir uma etapa antes da finalização da revisão com o `InputToggle`
   “Enviar conta para Woovi”, iniciado como desmarcado.
2. Enviar o booleano apenas na aprovação; reenvio e banimento permanecem
   inalterados.
3. Adicionar no modal “Contas BaaS” a ação “Criar envio”, visível somente para
   `admin_financial_providers`.
4. Oferecer “Conta BaaS Woovi” e “Conta Split Cielo”, com confirmação e retorno
   visível de solicitação enfileirada ou erro retornado pela API.

## Validação e aceite

1. Com `WOOVI_BAAS_AUTO_REGISTER_ENABLED=false`, completar um cadastro elegível
   e confirmar que Cielo segue o fluxo normal, sem evento automático Woovi.
2. Com a flag ligada em homologação, confirmar o comportamento automático Woovi
   já existente.
3. Aprovar uma revisão com o toggle desligado e confirmar que não há abertura
   Woovi; repetir com o toggle ligado e confirmar o evento Woovi.
4. No overview de um seller, solicitar manualmente Woovi e Cielo Split e
   confirmar o feedback de enfileiramento.
5. Repetir uma solicitação já existente para confirmar que o erro/estado
   retornado pelo fluxo posterior chega à interface sem criação de duplicidade
   no Dashboard.
6. Validar acesso negado para usuário sem a permissão administrativa.

Antes do deploy, criar e executar um teste de compatibilidade em homologação
para Dashboard -> Gateway -> Public API -> Account -> Redis -> Banking, usando
dados não sensíveis e reversíveis.

## Fora de escopo

- Alterar a política comercial, credenciais ou contratos externos da Woovi e da
  Cielo.
- Desativar o onboarding automático Cielo Split.
- Limpar, reprocessar ou remover eventos e filas existentes.
- Alterar `services-banking` ou `services-banking-v2` fora da reutilização de
  seus contratos já expostos pelo Account.
