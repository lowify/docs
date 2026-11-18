# Plano: adequação à LGPD

## Objetivo

Estruturar e executar a adequação da plataforma Lowify à Lei Geral de
Proteção de Dados Pessoais (LGPD), priorizando a redução imediata de risco
para titulares e a criação de evidências operacionais duráveis.

Este plano decorre do levantamento técnico realizado em 2026-11-18. Ele é
um roteiro de implementação e governança, não um parecer jurídico. A base
legal definitiva, os prazos de guarda regulatórios e a qualificação jurídica
dos papéis da Lowify, sellers e parceiros devem ser validados pelo jurídico e
pelo encarregado.

## Escopo confirmado

A plataforma trata, entre outros:

- cadastro de sellers, sócios, afiliados e compradores: nome, e-mail,
  telefone, CPF/CNPJ e endereço;
- operações financeiras: dados bancários, chave Pix, saques, recebíveis,
  pagamentos, reembolsos e disputas;
- checkout: pedido, produto, comprador, endereço, telefone, documento,
  sessão, IP, dispositivo e cookies;
- KYC: RG/CNH, selfie, resultado de verificação e biometria/verificação
  facial;
- comunicações: e-mail, WhatsApp, push e registros de entrega/recuperação;
- marketing e atribuição: pixels, cookies e identificadores de Meta, TikTok,
  Google e UTMify;
- conteúdo e operação: uploads, logs, webhooks, filas, relatórios e trilhas
  administrativas.

Componentes afetados: `dashboard-seller`, `front-checkout`,
`front-member-area`, `front-idv`, `front-chat`, `edge-gateway`,
`edge-public-api`, `edge-webhook`, `services-account`, `services-auth`,
`services-commerce*`, `services-banking*`, `services-wallet`,
`services-notification`, `services-sale-integrations`,
`services-checkout-transparent` e `data_layer`.

## Princípios de execução

- Não tratar "aceite dos termos" como consentimento genérico.
- Usar a base legal e o mínimo de dados adequados para cada finalidade.
- Não registrar documentos, biometria, tokens, credenciais, URLs assinadas,
  PAN ou CVV em logs, filas, artefatos de teste ou analytics.
- Executar exclusão e retenção de modo coordenado: banco, objeto no storage,
  cache, fila, log, backup e fornecedor.
- Preservar evidências de decisões, acessos, atendimentos e controles sem
  transformar a própria auditoria em repositório excessivo de dados pessoais.
- Nenhuma funcionalidade nova de KYC, perfilamento/antifraude, pixels ou
  compartilhamento externo entra em produção sem revisão de privacidade.

## Prioridade P0 — contenção e obrigação imediata

Meta: concluir ou ter plano de resposta aprovado em até 7 dias.

| ID | Entrega | Responsáveis sugeridos | Componentes | Critério de aceite |
| --- | --- | --- | --- | --- |
| P0-01 | Tratar artefato de KYC versionado como potencial incidente: preservar evidência, revogar/rotacionar as credenciais e URLs temporárias associadas, remover o conteúdo do repositório e avaliar reescrita de histórico. | Segurança, Infra, DPO/Jurídico | `services-account`, Git, storage | Credenciais/sessões antigas inválidas; varredura não encontra o artefato ou equivalentes; decisão de incidente e comunicação registrada. |
| P0-02 | Suspender pixels/cookies não essenciais até haver consentimento válido. | Produto, Frontend, Marketing, DPO | `front-checkout`, `dashboard-seller` | Meta/TikTok/Google/UTMify não recebem evento nem gravam cookie antes do aceite granular. |
| P0-03 | Formalizar encarregado, substituto, canal e triagem de direitos/incidentes. | Diretoria, Jurídico/DPO | institucional e todos os canais | Ato formal assinado; identidade e contato públicos; ticket/protocolo, SLA e responsável de plantão definidos. |
| P0-04 | Congelar exposição ampla de KYC: revisar permissões de visualização, exportação e download de documentos/selfies. | Segurança, Account, Dashboard | `services-account`, `front-idv`, `dashboard-seller` | Somente papéis estritamente necessários acessam o material; todo acesso passa a ser auditável. |
| P0-05 | Criar procedimento de incidente de dados pessoais e realizar simulado envolvendo KYC/storage. | Segurança, Infra, DPO/Jurídico | transversal | Playbook aprovado; RACI, contatos de fornecedores, templates e exercício com lições aprendidas registrados. |

## Prioridade P1 — fundação de conformidade

Meta: concluir em até 30 dias. Estas entregas são dependências para as
mudanças sistêmicas de P2.

| ID | Entrega | Responsáveis sugeridos | Dependências | Critério de aceite |
| --- | --- | --- | --- | --- |
| P1-01 | Inventário de tratamentos (RoPA): titular, dado, finalidade, sistema, base legal, controlador/operador, destinatário, país, retenção e owner. | DPO, Produto, Tech leads | P0-03 | 100% dos fluxos do escopo mapeados e aprovados pelos donos técnicos. |
| P1-02 | Matriz de bases legais e papéis: Lowify, seller, afiliado e cada fornecedor. | Jurídico/DPO, Produto | P1-01 | Cada finalidade possui base legal, justificativa de necessidade e orientação de transparência. |
| P1-03 | RIPD de KYC/biometria, prevenção a fraude e decisões automatizadas. | DPO/Jurídico, Segurança, Account | P1-01, P1-02 | Riscos, salvaguardas, acesso, retenção, fornecedores e plano de mitigação aprovados. |
| P1-04 | Política de privacidade separada dos termos, com versão, histórico e linguagem simples. | Jurídico/DPO, Produto | P1-01, P1-02 | Publicação informa controlador, finalidades, bases, dados, compartilhamentos, retenção, transferências, direitos e canal. |
| P1-05 | Política de cookies e especificação de CMP. | DPO, Marketing, Frontend | P1-02 | Catálogo de cookies/tags por domínio, finalidade, duração e fornecedor; UX aprovada para recusar, aceitar e alterar escolhas. |
| P1-06 | Inventário de fornecedores/suboperadores e DPAs. | Jurídico/DPO, Compras, Infra | P1-01 | Contrato ou aditivo para cada fornecedor crítico com instruções, segurança, incidente, suboperadores, auditoria e eliminação. |
| P1-07 | Avaliação de transferências internacionais. | Jurídico/DPO, Infra | P1-06 | País/região, mecanismo aplicável, salvaguardas e transparência publicados para cada transferência. |
| P1-08 | Tabela corporativa de retenção e descarte. | Jurídico/DPO, Data, Tech leads | P1-01, P1-02 | Prazo, fundamento, evento inicial, destino e método de descarte definidos para cada categoria. |

## Prioridade P2 — implementação na plataforma

Meta: concluir em até 90 dias, em entregas pequenas e testáveis.

| ID | Entrega | Repositórios principais | Critério de aceite |
| --- | --- | --- | --- |
| P2-01 | CMP e governança de tags: bloquear scripts, cookies e eventos server-side por categoria de preferência. | `front-checkout`, `dashboard-seller`, `front-member-area`, `front-chat` | Testes comprovam não disparo antes do consentimento, revogação imediata e registro versionado da preferência. |
| P2-02 | Central de direitos do titular com protocolo, autenticação proporcional, atendimento humano e trilha de auditoria. | `dashboard-seller`, `edge-public-api`, `services-account` | Solicitações de acesso, correção, informação de compartilhamento, oposição, revogação e eliminação são rastreáveis ponta a ponta. |
| P2-03 | Mapa técnico de dados do titular e exportação segura. | todos os serviços de domínio | Busca localiza dados em bancos, storage, filas, logs e integrações; exportação é autorizada, minimizada e expira. |
| P2-04 | Exclusão/anonimização orquestrada e retenção automática. | `services-account`, `services-commerce*`, `services-banking*`, `services-notification`, `services-wallet`, `data_layer` | Casos de eliminação removem/anonimizam dados elegíveis e documentam exceções legais; jobs são idempotentes e monitorados. |
| P2-05 | Lifecycle de KYC: acesso de menor privilégio, expiração de upload/URLs, exclusão do objeto e retenção específica para documento/selfie. | `front-idv`, `services-account`, storage | Testes confirmam que apagar um registro não deixa cópia acessível no storage; acesso é auditado. |
| P2-06 | Sanitização central de logs, exceções, filas e webhooks; DLP e secret scanning no CI. | todos, CI/CD | Testes negativos impedem CPF, documento, token, segredo, URL assinada e cartão nos destinos proibidos. |
| P2-07 | RBAC/MFA e auditoria de acesso a dados sensíveis. | `dashboard-seller`, `edge-public-api`, `services-account` | Privilégios mínimos revisados; leitura/download/exportação de KYC e financeiro possuem ator, justificativa e retenção de auditoria. |
| P2-08 | Avaliação e controle de decisões automatizadas de fraude/KYC. | `services-account`, `services-banking*`, `front-idv` | Há explicação adequada, revisão humana, contestação, limites de retenção e teste de vieses/riscos relevantes. |
| P2-09 | Segregação de dados de comprador entre seller e afiliado. | `services-commerce-v2`, `edge-public-api`, `dashboard-seller` | `expose_buyer_data` usa padrão restritivo, campos mínimos, finalidade registrada e auditoria de consulta/exportação. |
| P2-10 | Proteção de pagamentos: confirmação de tokenização e redução de escopo PCI. | `front-checkout`, checkout transparente, banking | PAN/CVV não chegam a banco, fila, log, analytics ou backoffice Lowify; evidência de fluxo e testes arquivada. |

## Prioridade P3 — sustentação contínua

Meta: iniciar após P1 e manter como rotina.

- Treinamento anual e onboarding de privacidade para engenharia, suporte,
  atendimento, financeiro e revisão KYC.
- Revisão trimestral de acessos privilegiados e relatórios de acesso a dados
  sensíveis.
- Revisão semestral do RoPA, contratos, transferências internacionais,
  política de privacidade e matriz de retenção.
- Simulado semestral de incidente e avaliação anual de fornecedores críticos.
- Privacy review obrigatório no template de RFC/feature: dados, finalidade,
  base legal, fornecedor, país, retenção, direitos e risco.
- Métricas mensais: solicitações de titulares por prazo/status, eliminações
  executadas, acessos privilegiados, incidentes, tags bloqueadas e cobertura
  do inventário.

## Ordem de dependências

```text
P0 contenção e responsáveis
  -> P1 inventário, bases legais, RIPD, fornecedores e retenção
    -> P2 CMP, direitos, eliminação, KYC, logs, RBAC e contratos técnicos
      -> P3 auditoria, treinamento e revisão contínua
```

Não iniciar automações de eliminação em produção antes de P1-08: cada classe
de dado precisa de prazo, fundamento de conservação, dono e teste de
recuperação/backup aprovados.

## Gate de liberação

Uma entrega somente pode ser considerada concluída quando houver:

1. decisão de produto/jurídico documentada, quando aplicável;
2. implementação revisada e teste automatizado ou roteiro manual reproduzível;
3. validação dos fluxos de erro, reentrega de fila e idempotência;
4. evidência de que logs, métricas e ferramentas de terceiros não receberam
   dados excedentes;
5. owner operacional, alerta e runbook definidos.

## Referências normativas

- [Lei nº 13.709/2018 — LGPD](https://www2.camara.leg.br/legin/fed/lei/2018/lei-13709-14-agosto-2018-787077-normaatualizada-pl.html)
- [ANPD — RIPD](https://www.gov.br/anpd/pt-br/canais_atendimento/agente-de-tratamento/relatorio-de-impacto-a-protecao-de-dados-pessoais-ripd)
- [ANPD — Regulamento do encarregado](https://www.gov.br/anpd/pt-br/acesso-a-informacao/institucional/atos-normativos/regulamentacoes_anpd/processo_integra_-resolucao_cd_anpd_no_18_2024.pdf)
- [ANPD — Comunicação de incidente](https://www.gov.br/anpd/pt-br/canais_atendimento/agente-de-tratamento/comunicado-de-incidente-de-seguranca-cis)
- [ANPD — Transferência internacional de dados](https://www.gov.br/anpd/pt-br/acesso-a-informacao/institucional/atos-normativos/regulamentacoes_anpd/resolucao-cd-anpd-no-19-de-23-de-agosto-de-2024)
