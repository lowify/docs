# Plano — serviço MCP de consultas da Lowify

> Estado: planejamento. Nenhuma rota, serviço, migration, fila ou alteração de autenticação foi implementada por este documento.
>
> Data: 2026-11-11

## Objetivo

Criar o `services-ai-mcp`, um serviço dedicado em **Hyperf/Swoole** que disponibiliza, via Model Context Protocol (MCP), consultas seguras e eficientes sobre a operação da Lowify para clientes de IA autorizados.

O serviço será estritamente de leitura nesta primeira etapa. Ele deve responder perguntas como “como foram minhas vendas esta semana?”, “quais produtos venderam mais?”, “qual o saldo disponível?” ou “quais assinaturas vencem em breve”, sem permitir criar, editar, publicar, cancelar, reenviar ou disparar qualquer ação no domínio.

O projeto tem duas premissas não negociáveis:

1. O tráfego de IA não pode degradar Commerce, Wallet, Banking, Account, Redis compartilhado nem os bancos transacionais.
2. Uma resposta útil nunca pode expor dados de outro seller, credenciais, meios de pagamento, documentos, PII além do necessário ou informação administrativa a uma identidade comum.

## Escopo e fronteiras

### Incluído

- Servidor MCP remoto, hospedado separadamente, usando Streamable HTTP e JSON-RPC.
- Autorização por usuário/seller, escopos e políticas de visibilidade.
- Tools de consulta com schemas fechados, filtros limitados e paginação cursorizada.
- Dados comerciais: visão executiva, vendas, produtos, ofertas, assinaturas e afiliação.
- Dados financeiros permitidos: saldo/disponibilidade e movimentos agregados, sem instrumentos financeiros ou dados bancários.
- Cache temporário, limites de concorrência, timeouts, circuit breakers, auditoria e observabilidade.
- Read model/aggregates assíncronos para consultas históricas ou dispendiosas.

### Explicitamente fora do escopo inicial

- Publicar, criar, alterar, excluir, pausar ou reativar produtos.
- Reembolso, saque, pagamento, cancelamento de assinatura, reenvio de entrega ou qualquer mutação.
- Execução de SQL livre, filtros arbitrários, exportação ilimitada ou acesso direto a bancos de outros serviços.
- Tools administrativas, KYC/documentos, credenciais de gateway, dados de cartão, tokenização, senha financeira, chaves Pix, payloads BaaS ou logs brutos.
- Conversas longas, memória da IA ou persistência de prompts; isso pertence ao cliente de IA, não ao servidor MCP.
- Substituir as APIs existentes, Gateway ou as regras de negócio dos serviços de domínio.

## Estado atual confirmado

| Área | Evidência atual | Uso previsto no MCP |
| --- | --- | --- |
| Commerce V2 | Hyperf; domínios de Product, Sale, Report, Dashboard, Affiliate e Subscription. Há endpoints de overview, busca de vendas, detalhes, produtos, afiliação e assinaturas. | Fonte principal de catálogo, vendas e métricas comerciais. |
| Wallet | Hyperf; oferece `balances`, `metrics`, `summary` e `availability` para extrato/saldo, além de filas de eventos. | Fonte de visão financeira resumida, depois de revisão de autorização e mascaramento. |
| Banking V2 | Hyperf; possui leituras de recebíveis de cartão, status e disponibilidade de refund. | Fonte futura para recebíveis consolidados; não entra no MVP até contrato e classificação de sensibilidade serem aprovados. |
| Account | Hyperf; concentra dados do usuário, perfil de pagamento, canais de suporte, preferências e fluxos sensíveis. | Só resolução de identidade e perfil mínimo; não expor dados de pagamento, documentos ou credenciais. |
| Edge Gateway/Public API | Já encaminha parte relevante dos caminhos de dashboard, vendas, produtos, assinaturas e wallet. | Referência de contratos atuais; o MCP não deve contornar a autorização de domínio. |

Fatos importantes para o desenho:

- `services-commerce-v2` já possui casos de uso de dashboard, busca e detalhe de venda, produto, afiliação, relatório e assinatura.
- O detalhe atual de venda pode conter comprador, UTM, IP/user-agent, dados financeiros e comunicações. Portanto, ele **não pode** ser repassado como tool genérica sem uma projeção específica e política de campos.
- `services-wallet` usa Redis e filas para processamento de extrato. O MCP não pode competir com seus consumidores nem criar chaves genéricas no namespace de negócio.
- A arquitetura existente é orientada a filas; projeções assíncronas são preferíveis a recalcular histórico sobre tabelas transacionais a cada pergunta.

## Arquitetura alvo

```text
Cliente MCP / IA
  └─ HTTPS + OAuth 2.1 / Bearer token
       └─ services-ai-mcp (Hyperf/Swoole, pool isolado)
            ├─ autenticação, escopos e policy de seller
            ├─ parser/validador MCP + registry de tools
            ├─ quota, rate limit, timeout, cache e auditoria
            ├─ conectores internos de leitura
            │    ├─ Commerce V2 read API
            │    ├─ Wallet read API
            │    ├─ Account identity/entitlement API
            │    └─ Banking V2 read API (fase posterior)
            ├─ Redis exclusivo: cache, locks e rate limit do MCP
            └─ banco/read store próprio: auditoria e projeções analíticas

Serviços de domínio
  └─ eventos existentes ou contratos internos de leitura
       └─ worker MCP/projeções → read store agregado (assíncrono)
```

O MCP é uma camada de adaptação, não um agregador que consulta bancos alheios. Toda consulta deve usar um contrato de leitura explícito do dono dos dados ou um read model próprio alimentado assincronamente.

### Decisão de isolamento

Criar um repositório novo `services-ai-mcp`, com a convenção Hyperf já usada pelos serviços modernos:

```text
app/
  Application/UseCase/Mcp/
  Domain/Mcp/{Policy,Tool,Repository}/
  Infrastructure/{Commerce,Wallet,Account,Banking,Cache,Audit,Projection}/
  Http/{Controller,Middleware,Request,Response}/
  Process/
config/{routes.php,autoload/processes.php}
```

Ele terá deployment, pods/processos, pool HTTP, Redis e banco próprios. Dependências em Commerce, Wallet, Account e Banking ocorrerão por HTTP interno autenticado, com limites de conexão e timeout. Não compartilhará uma connection pool de banco com serviços transacionais.

## Protocolo MCP

O endpoint público será único, por exemplo `POST`/`GET https://mcp.lowify.com/mcp`, com suporte a:

- `initialize`: negociação da versão MCP e capacidades;
- `tools/list`: catálogo das tools liberadas para aquela identidade;
- `tools/call`: execução de uma tool;
- respostas JSON-RPC compatíveis, com erros padronizados e sem detalhes internos;
- HTTP Streamable; SSE só quando uma resposta assíncrona/streaming for realmente necessária.

As tools usam JSON Schema. A descrição melhora a escolha da IA, mas não é um controle de segurança: o serviço valida tipo, enum, limites, escopo e identidade antes de executar.

O catálogo é calculado conforme o token. Uma conta sem permissão financeira não recebe tools financeiras em `tools/list`; um admin não recebe acesso administrativo por acidente apenas por conectar o MCP.

## Identidade, autenticação e autorização

### Fluxo proposto

```text
Cliente MCP → /mcp sem token → 401 + metadados do resource server
Cliente MCP → Authorization Code + PKCE no Authorization Server Lowify
Authorization Server → access token curto, audience do MCP e scopes concedidos
Cliente MCP → Authorization: Bearer <token> em toda chamada /mcp
services-ai-mcp → valida assinatura, expiração, issuer, audience, scopes e claims
services-ai-mcp → resolve actor e seller efetivo → executa policy por tool
```

O servidor será um resource server OAuth. O Authorization Server pode evoluir a partir do stack de autenticação atual, mas essa decisão exige um contrato próprio: emissão OAuth, consentimento, refresh token, revogação, discovery e rotação de chaves não devem ser simulados com um JWT de front-end.

### Claims e regras mínimas

| Item | Regra |
| --- | --- |
| `sub` | Identidade autenticada; nunca aceita do argumento de uma tool. |
| `seller_id` | Seller efetivo, obtido de claim assinada ou resolução segura. Para colaborador, respeita o owner e as permissões já definidas para ele. |
| `actor_type` | Diferencia usuário, colaborador e futuro service account; deny-by-default para tipo desconhecido. |
| `scope` | Autoriza capacidade granular; não usar uma permissão genérica de “logado”. |
| `aud` | Deve ser o recurso MCP; tokens emitidos para outro edge/API são rejeitados. |
| tempo | Access token curto, validação de `exp`, `nbf`, `iss`, `jti` e revogação quando aplicável. |

Escopos iniciais propostos:

```text
mcp:overview:read
mcp:sales:read
mcp:products:read
mcp:subscriptions:read
mcp:affiliates:read
mcp:wallet:read
```

O escopo concede apenas a categoria. A policy ainda verifica propriedade do recurso, papel do ator, máscara de campos e limites. Um `sale_id`, `product_id`, e-mail, CPF ou `seller_id` fornecido pela IA nunca amplia acesso.

## Catálogo de consultas

### Fase 1 — MVP de baixo risco

| Tool | Perguntas atendidas | Fonte/estratégia | Dados retornados | Limites iniciais |
| --- | --- | --- | --- | --- |
| `get_business_overview` | “Como está meu negócio hoje/esta semana?” | Contrato de overview do Commerce ou snapshot agregado. | totais de vendas, receita definida pelo contrato, status e comparação curta. | períodos pré-definidos: hoje, 7, 30 dias; cache 60 s. |
| `list_products` | “Quais produtos ativos tenho?” | Read API de produtos própria para MCP. | id, título, status, tipo, preço/oferta resumida, data de atualização. | cursor; máximo 50; cache 5 min. |
| `get_product_summary` | “Como está o produto X?” | produto + métrica agregada. | metadados seguros, oferta, vendas/receita do período, sem conteúdo privado completo. | período até 90 dias; cache 5 min. |
| `get_sales_summary` | “Quanto vendi por dia/produto/método?” | snapshot/read model de vendas agregadas. | contagem, valores, série curta e agrupamento permitido. | janela máxima 90 dias; 100 buckets; cache 60–300 s. |
| `list_sales` | “Mostre as vendas pagas de ontem.” | Read API paginada/projeção. | order id parcial, produto, status, valor, método, datas; PII mascarada ou ausente. | cursor; máximo 50; janela 90 dias. |
| `get_sale_summary` | “Qual o status do pedido ABC?” | projeção de venda com policy de ownership. | status, itens, valores permitidos, datas e situação de entrega; nenhum IP, user-agent ou log de comunicação. | um recurso; cache 30 s. |
| `list_subscriptions` | “Quais assinaturas estão ativas?” | contrato/projeção de Subscription. | produto, status, periodicidade, próxima cobrança e valor permitido. | cursor; máximo 50; cache 60 s. |

As respostas precisam retornar campos canônicos e metadados de frescor, por exemplo:

```json
{
  "data": { "period": { "from": "2026-11-01", "to": "2026-11-07" }, "paid_sales": 42 },
  "meta": { "generated_at": "2026-11-11T10:30:00-03:00", "source": "mcp_read_model", "freshness_seconds": 45 }
}
```

`source` e `freshness_seconds` são importantes para que a IA informe corretamente que dados de analytics podem ter pequena defasagem.

### Fase 2 — após validação operacional

| Tool | Condição para entrar | Proteções adicionais |
| --- | --- | --- |
| `get_wallet_summary` | Contrato Wallet específico que defina saldo disponível, reservado e data de referência. | Não retornar chave Pix, conta bancária, extrato detalhado ou identificadores de contraparte sem revisão. Cache curto, no máximo 30 s. |
| `list_wallet_movements` | Read model de movimentos paginado, indexado e com classificação de PII. | Janela limitada, cursor, valores e descrições normalizados; sem payload bruto de evento. |
| `get_affiliate_summary` | Contrato que respeite visibilidade entre owner, afiliado e produto. | Nunca revelar dados de comprador a afiliado quando a regra do produto não autorizar. |
| `get_receivables_summary` | Revisão de Banking V2 e semântica financeira aprovada. | Apenas consolidação por data/status; sem dados bancários, chaves ou payloads de PSP. |
| `get_notification_delivery_summary` | Projeção de comunicações, não consulta de filas ou logs. | Totais por status/canal, sem corpo da mensagem, telefone ou e-mail. |

### Categorias proibidas até nova decisão explícita

- Perfil financeiro, conta bancária, documentos/KYC, senha financeira e token de recuperação.
- Checkout público, endereço, CPF, cartão, segredo de integração, webhook, payload de PSP ou dados de antifraude.
- Auditorias, IP, user-agent e eventos detalhados de usuário.
- Métricas ou dados globais de plataforma, exceto se for desenhado um MCP administrativo independente, com outro audience, outro catálogo e controle reforçado.

## Contratos de leitura

Cada tool terá um use case MCP, DTO de entrada/saída e conector de domínio. Não chamar controllers nem reutilizar respostas acidentalmente amplas do Dashboard.

```text
Tool MCP
  → Input DTO e JSON Schema
  → Scope + ResourcePolicy
  → Query use case
  → Connector interno ou ReadModelRepository
  → DTO público com classificação de campos
  → resposta MCP
```

Para cada fonte, criar uma read API interna, versionada e mínima, ou projetar o evento correspondente. Exemplo de contrato interno:

```text
GET /internal/mcp/v1/sellers/{sellerId}/sales/summary?from=...&to=...&group_by=product
```

Esse endpoint só aceita autenticação serviço-a-serviço; não fica exposto pelo Gateway público. O serviço dono dos dados aplica o `sellerId` recebido após verificar assinatura, audience e permissão do cliente MCP. O MCP não ganha acesso de banco por saber o id.

### Padrões de resposta e erro

- Valores monetários como string decimal, nunca `float`.
- Datas ISO 8601 com timezone, e período explícito em toda agregação.
- Cursor opaco assinado; nunca offset infinito.
- Máximo de 50 registros por página e 100 buckets agregados.
- Erros públicos estáveis: `invalid_arguments`, `forbidden`, `not_found`, `rate_limited`, `source_unavailable`, `result_too_large` e `query_not_supported`.
- Falha de fonte retorna indisponibilidade controlada; nunca stack trace, URL interna, SQL, header de serviço ou detalhe de Redis.

## Desempenho e proteção do sistema principal

### Regra de ouro

Uma pergunta da IA não pode disparar N+1 chamadas, varredura de vendas, joins sem índice, exportação integral ou recálculo de dashboard em Commerce/Wallet. O MCP só permite operações com custo conhecido e teto baixo.

### Camadas de leitura

1. **L1 por requisição:** memoização de conectores durante a execução de uma tool, para não repetir a mesma chamada.
2. **L2 Redis exclusivo do MCP:** cache de respostas serializadas e de projeções pequenas, com chave incluindo versão, seller, escopo de visibilidade, ferramenta e filtros normalizados.
3. **Read store próprio:** tabelas agregadas por seller/data/produto/status para séries, ranking e consultas acima de poucos dias.
4. **Fonte transacional:** somente lookups pontuais e APIs internas baratas; não é fallback para consultas históricas custosas.

O cache nunca deve ser compartilhado com chaves funcionais de Commerce ou Wallet. Usar prefixo, conexão/DB lógico e política próprios, por exemplo `mcp:v1:*`.

### Política de cache proposta

| Tipo de consulta | TTL base | Stale-while-revalidate | Invalidação |
| --- | ---: | ---: | --- |
| Catálogo de produto | 5 min | 10 min | evento de produto, quando disponível; expiração como fallback. |
| Overview e resumo de vendas recente | 60 s | 60 s | evento de venda/refund; expiração como fallback. |
| Série e ranking históricos | 5 min | 15 min | atualização da projeção por lote/evento. |
| Detalhe de venda | 30 s | não aplicar se o status for mutável/pending | evento de mudança de status. |
| Saldo/disponibilidade | 15–30 s | no máximo 15 s, exibindo frescor | evento de ledger; nunca cache de longa duração. |

TTL, tamanho máximo e comportamento stale serão configuráveis, monitorados e revisados com carga real. A resposta deve indicar quando veio de snapshot/cache e sua idade; não prometer “tempo real” se não for.

### Contenção de carga

- Pool HTTP por dependência, com conexões, concorrência e fila locais limitadas.
- Timeout de conexão curto e timeout total por tool; orçamento inicial: 200 ms conexão, 800 ms para fonte interna e 2 s totais para a resposta síncrona.
- Circuit breaker por origem. Em degradação, responder com cache ainda válido quando permitido ou `source_unavailable`; nunca formar fila infinita.
- Bulkhead por grupo (`sales`, `products`, `wallet`), impedindo que a lentidão de uma fonte consuma todos os workers Swoole.
- Rate limit por `sub`, `seller_id`, cliente OAuth/IP e tool, além de limite global do serviço. Valores iniciais devem ser calibrados em homologação; não fixar números de produção neste plano.
- Coalescing/single-flight por cache key: múltiplas perguntas idênticas fazem uma única recomputação.
- Payload máximo de resposta e truncamento semântico com cursor. Não retornar listas enormes para a IA.
- Consultas custosas: retornar apenas o snapshot pré-computado; se estiver defasado além do SLA, informar indisponibilidade/defasagem, não calcular on demand no banco principal.

### Projeções assíncronas

Para vendas, produtos e receitas, implementar um consumidor dedicado que atualize agregados idempotentes no read store a partir de eventos já publicados ou de um contrato incremental do dono. A decisão sobre qual evento usar depende de um pente-fino de produtores/consumidores antes da implementação.

O consumidor precisa de:

- chave de idempotência por evento/versão;
- checkpoints e métricas de lag;
- retry com dead-letter queue;
- reconstrução por seller/período sem bloquear o tráfego online;
- contrato versionado e compatível com eventos existentes;
- reconciliação periódica limitada, fora do horário de pico, para detectar divergência.

Não consumir uma fila existente de forma concorrente sem garantir consumer group/semântica compatível; não alterar payloads de eventos de Commerce ou Wallet para o MCP sem rollout coordenado.

## Segurança e privacidade

### Controles obrigatórios

- HTTPS obrigatório; validação de `Origin` no transporte HTTP MCP e proteção contra DNS rebinding.
- OAuth 2.1 com Authorization Code + PKCE para clientes interativos; tokens com audience do MCP, expiração curta e rotação/revogação.
- Service-to-service separado do token de usuário: mTLS e/ou assinatura/HMAC/credencial de serviço rotacionável conforme padrão aprovado da plataforma. Não propagar token externo como credencial interna.
- Deny-by-default: tool, campo ou domínio sem policy aprovada não aparece nem executa.
- Autorização por recurso em todo detalhe: `sale_id`, produto, assinatura e movimento precisam pertencer ao seller/ator efetivo.
- Schema rígido, allowlist de filtros/ordenação e normalização de datas. Não construir SQL a partir de texto da IA.
- Mascaramento de PII no padrão de menor privilégio. E-mail, telefone, CPF, endereço, IP e identificadores de comprador ficam ausentes salvo decisão e scope específico futuros.
- Sanitização de conteúdo que será mostrado a um modelo. Campos vindos de produto, comprador ou integração são dados, não instruções; não permitir que texto armazenado altere a tool, o escopo ou a política.
- Logs estruturados sem access token, refresh token, header Authorization, PII desnecessária, credenciais ou payload completo de respostas.
- Audit trail imutável/retido conforme política: request id, token/client id pseudonimizado, ator, seller, tool, versão, filtros normalizados, status, latência, cache hit e número de registros. Nunca armazenar a conversa completa sem decisão de privacidade.
- Segregação de administração: catálogo, audience, client registration e roles administrativos devem ser separados do MCP de seller.

### Riscos de IA que precisam de tratamento

| Risco | Controle |
| --- | --- |
| Prompt injection em nomes, descrições ou campos de produto | Tratar todo retorno como dado; schemas fechados; não executar texto retornado. |
| Exfiltração por paginação/consultas repetidas | Quotas, cursores, data minimization, limites temporais e auditoria. |
| Escalada por `seller_id` no argumento | Seller vem exclusivamente da identidade; argumentos não podem substituir escopo. |
| Confusão de token/audience | Validar issuer, audience, resource indicator e cliente autorizado. |
| Enumeração de IDs | Responder `not_found`/`forbidden` de forma não reveladora e limitar tentativas. |
| Cache cruzado entre sellers | Cache key contém seller, papel/escopo e versão; testes obrigatórios de isolamento. |
| Vazamento em erro/telemetria | Erros públicos mínimos, redaction centralizada e revisão de logs. |

## Observabilidade e operação

O serviço terá health check simples e health checks de dependência separados, para que uma indisponibilidade de Commerce não derrube o processo MCP inteiro.

Métricas mínimas:

- requisições, tools/list e tools/call por tool, cliente e resultado;
- latência p50/p95/p99 total e por dependência;
- cache hit/miss/stale, tamanho e evictions;
- rate-limit, bulkhead, timeout e circuit breaker;
- tamanho de resposta, resultados truncados e erros de schema;
- lag, retries, DLQ e divergência das projeções;
- consumo de workers, memória, pool HTTP e Redis do MCP.

Alertas devem se basear em erro/latência sustentados, saturação e lag de projeção. Logs correlacionam `request_id` entre MCP e conectores, sem registrar segredos.

## Qualidade, testes e aceite

### Testes automatizados

- Unitários para schemas, policies, mascaramento, normalização de filtros, cache key e serialização MCP.
- Integração para OAuth/resource server, `initialize`, `tools/list`, `tools/call`, JSON-RPC e erros.
- Contrato com cada read API interna, incluindo versionamento e casos de timeout/erro.
- Segurança: token inválido/expirado/audience incorreto, colaborador fora de escopo, ID de outro seller, enumeração, cache cross-tenant e redaction de log.
- Carga: picos de `get_sales_summary`, repetição da mesma consulta (single-flight) e falha de Commerce/Wallet, comprovando bulkhead e circuit breaker.
- Regressão de projeção: duplicidade, evento fora de ordem, retry e reconciliação.

### Critérios de aceite do MVP

1. Uma conta só recebe e consulta dados do seu seller efetivo; tentativas de trocar identificador no argumento falham.
2. `tools/list` não oferece ferramentas financeiras a quem não tenha o scope correspondente.
3. Todas as tools da fase 1 são leitura, paginadas, com schema fechado e limite de período/resultado.
4. Uma consulta repetida atende pelo cache conforme política e não multiplica chamadas à origem.
5. Indisponibilidade ou lentidão de um serviço de domínio não esgota os workers do MCP nem aumenta indefinidamente a carga da origem.
6. Respostas e logs não contêm token, PII proibida, credenciais, dados de cartão ou dados de outro seller.
7. O MCP informa timestamp/frescor em resultados agregados e não apresenta snapshot como dado em tempo real.
8. Teste de compatibilidade em homologação cobre Gateway/Auth, Commerce V2, Wallet/Redis e filas de projeção antes de qualquer produção.

## Fases de implementação

### Fase 0 — descoberta e contratos

1. Criar o repositório e ler suas instruções locais, stack e padrões de DI/HTTP/Redis.
2. Mapear, por domínio, rotas, controllers, use cases, modelos, queries, índices, variáveis, filas e consumidores que suportarão cada tool proposta.
3. Classificar todos os campos como público ao seller, PII mascarada, PII restrita, financeiro restrito ou segredo.
4. Definir o Authorization Server, claims, scopes, consentimento, client registration, revogação e estratégia de credencial interna.
5. Medir custo e índices das consultas candidatas; decidir por connector síncrono, cache ou projeção para cada uma.
6. Versionar os contratos internos de leitura com os serviços donos dos dados.

### Fase 1 — fundação MCP e MVP comercial

1. Configurar Streamable HTTP, `initialize`, `tools/list`, `tools/call`, validação JSON-RPC e middleware OAuth.
2. Implementar identity context, `ResourcePolicy`, auditoria redigida, rate limit, Redis exclusivo, timeout, circuit breaker e métricas.
3. Criar conectores internos para Commerce V2 e as tools `get_business_overview`, `list_products`, `get_product_summary`, `get_sales_summary`, `list_sales`, `get_sale_summary` e `list_subscriptions`.
4. Aplicar schemas, paginação cursorizada, DTOs públicos e classificação de campos.
5. Executar testes unitários, integração, segurança e carga; homologar de forma isolada.

### Fase 2 — read model e escala

1. Implementar projeções agregadas de vendas/produtos no banco próprio do MCP.
2. Adicionar consumer, idempotência, DLQ, métricas de lag e reconciliação.
3. Mover consultas históricas/rankings do caminho síncrono para o read store.
4. Ajustar TTLs, quotas, orçamento de latência e capacity com telemetria de homologação.

### Fase 3 — financeiro e afiliação, mediante aprovação

1. Criar contratos específicos com Wallet, Banking V2 e Commerce V2 para as tools da fase 2.
2. Concluir DPIA/revisão de segurança e matriz de campos antes de expor qualquer saldo, movimento ou recebível.
3. Liberar por feature flag, allowlist de clientes e escopos separados.

## Rollout e rollback

1. Ambiente local com fontes simuladas e tokens de desenvolvimento sem dados reais.
2. Homologação com seller de teste, quotas baixas, catálogo reduzido e observabilidade completa.
3. Produção inicialmente sem client registration público: allowlist de poucos clientes e sellers internos autorizados.
4. Habilitar uma tool por vez, por feature flag; começar por overview e catálogo, depois vendas e assinaturas.
5. Ampliar somente após métricas de isolamento, custo, latência e segurança atingirem os critérios acordados.

Rollback é desabilitar a tool/feature flag ou revogar o client OAuth, preservando os serviços de origem. Como a fase inicial não escreve em domínio, não há compensação de negócio. Projeções podem ser pausadas ou reconstruídas sem tocar nas tabelas transacionais.

## Decisões pendentes

| Tema | Decisão necessária |
| --- | --- |
| Authorization Server | Estender `services-auth` ou operar componente OAuth dedicado; definir discovery, PKCE, client registration, consentimento e revogação. |
| Transporte público | Domínio, WAF/rate limit de borda, TLS/mTLS e política de `Origin`. |
| Read store | Escolher banco/tecnologia, retenção, backup, custo e estratégia de rebuild. |
| Eventos | Confirmar eventos de venda/produto/refund que podem alimentar projeções sem alterar contratos existentes. |
| Receita e saldo | Definir terminologia financeira canônica (bruta, líquida, disponível, reservada) e quem é fonte de verdade. |
| PII | Aprovar matriz de campos e eventual escopo futuro para dados de comprador; padrão inicial é omitir. |
| Colaboradores | Mapear permission keys atuais para scopes MCP e confirmar quais consultas cada papel pode fazer. |
| Limites de produção | Definir quotas, TTL, SLO, capacidade de workers e orçamento de latência a partir de baseline em homologação. |

## Referências de descoberta

- `services-commerce-v2/config/routes.php`
- `services-commerce-v2/app/Application/UseCase/{Dashboard,Product,Sale,Subscription,Affiliate,Report}`
- `services-commerce-v2/app/Application/UseCase/Sale/GetSaleDetailOverviewUseCase.php`
- `services-wallet/config/routes.php` e `services-wallet/app/Process/`
- `services-banking-v2/config/routes.php`
- `services-account/config/routes.php`
- `edge-gateway/config/routes.php`
- `.agents/architecture.md`
- `.agents/backend/{README.md,stack-map.md,workflow.md}`
- [MCP — Authorization](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization)
- [MCP — Transports](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)
