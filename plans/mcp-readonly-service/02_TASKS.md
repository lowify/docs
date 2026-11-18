# Tasks executáveis — serviço MCP de consultas

> Estado: planejamento. Estas tasks não autorizam deploy, migração, alteração de fila ou abertura pública sem a aprovação correspondente.

## Regras de execução

- Executar em ordem de dependência. Uma task só inicia após o aceite da anterior.
- O primeiro release aceita somente o login do seller proprietário. Colaboradores, Wallet, Banking, PII de comprador e qualquer tool de escrita ficam fora.
- O acesso externo entra por `edge-gateway` e segue diretamente para `services-ai-mcp`; não passa por `edge-public-api`.
- `services-ai-mcp` nunca acessa diretamente banco ou Redis de Commerce V2. Usa contratos internos de leitura ou seu read model.
- Nenhum endpoint administrativo atual de Commerce V2 pode ser reutilizado como contrato MCP.
- Tokens, refresh tokens, segredos, dados de cartão, credenciais de integração e PII proibida não podem entrar em logs, fixtures, auditoria ou documentação.
- Toda alteração de schema usa migration aditiva e rollback quando o padrão do repositório suportar. Nenhuma migration existente é alterada.
- Depois de cada bloco integrado, preparar teste de compatibilidade em homologação; não o executar na VPS sem aprovação explícita.

## Marco de entrega

O primeiro piloto será restrito a sellers e clientes OAuth em allowlist e publicará somente:

```text
get_business_overview
list_products
get_sales_summary
```

Após carga, segurança e isolamento aprovados, o mesmo MVP técnico habilita gradualmente:

```text
get_product_summary
list_sales
get_sale_summary
list_subscriptions
```

## T01 — Fechar a matriz de interoperabilidade MCP

**Repositórios:** novo `services-ai-mcp`; `services-auth`.

**Dependências:** nenhuma.

1. Homologar separadamente Codex, Claude e Gemini com um servidor de teste, confirmando suporte a MCP remoto, Streamable HTTP, OAuth Authorization Code com PKCE e renovação/revogação de token.
2. Registrar versão MCP mínima e máxima aceita pelo servidor, comportamento de `tools/list`, `tools/call`, OAuth discovery e particularidades documentadas de cada cliente.
3. Definir a política de registro de cliente: allowlist de clientes conhecidos no piloto; Dynamic Client Registration permanece desligado.
4. Cadastrar somente redirect URIs exatas e metadados confirmados de cada cliente. Não aceitar curingas, IPs arbitrários ou URIs fornecidas pela requisição.
5. Registrar incompatibilidades como bloqueio de liberação daquele cliente, sem relaxar PKCE, audience ou validação de redirect URI.

**Aceite:** existe uma matriz versionada com Codex, Claude e Gemini, incluindo cliente OAuth, redirect URI, versão MCP, fluxo testado e resultado; nenhum cliente desconhecido inicia autorização.

## T02 — Criar o esqueleto isolado do `services-ai-mcp`

**Repositório:** novo `services-ai-mcp` Hyperf/Swoole.

**Dependências:** T01.

1. Criar repositório Hyperf com convenções `Application`, `Domain`, `Infrastructure`, `Http` e `Process` compatíveis com os serviços modernos.
2. Configurar pools HTTP por dependência, Redis exclusivo do MCP e banco próprio para auditoria/read model. Não reutilizar connection pool de Commerce V2.
3. Criar health checks: processo vivo, Redis MCP, banco MCP e dependências externas separadamente; falha de Commerce não pode tornar o serviço inteiro indisponível.
4. Definir configuração sem segredos versionados: URLs internas, timeout, limites de pool, quotas, TTLs, feature flags e ambiente.
5. Adicionar pipeline mínimo de teste, lint/análise conforme o `composer.json` do novo serviço.

**Aceite:** serviço sobe isoladamente, possui health checks e não conecta a banco/Redis de domínio sem contrato explícito.

## T03 — `services-auth`: persistência de conexões OAuth

**Repositório:** `services-auth`.

**Dependências:** T01.

1. Mapear o modelo atual de login, JWT e refresh em `AuthController`, `JwtService`, modelos e migrations antes de editar.
2. Criar migrations aditivas para: clientes OAuth allowlisted, grants/conexões do seller, scopes concedidos, authorization codes de uso único, refresh tokens rotativos, revogações e eventos de auditoria OAuth.
3. Persistir refresh tokens somente como hash, com vínculo a seller, cliente, grant, escopos, expiração de 30 dias, rotação e status.
4. Modelar revogação de grant/conexão como operação atômica; revogar todos os refresh tokens do grant e publicar invalidação para consumidores MCP.
5. Manter login/JWT/refresh atuais compatíveis; tabelas e endpoints OAuth novos não podem alterar o comportamento dos fronts existentes.

**Aceite:** migrations novas criam a base OAuth sem dados sensíveis em claro; reuso de refresh token é detectado e invalida o grant; refresh comum atual continua funcionando.

## T04 — `services-auth`: Authorization Server OAuth

**Repositório:** `services-auth`.

**Dependências:** T03.

1. Implementar discovery/metadata do Authorization Server, JWKS com rotação de chave e endpoints de authorization, consentimento, token, revogação e, se necessário para interoperabilidade, introspection interna.
2. Implementar Authorization Code com PKCE obrigatório (`S256`), `state`, nonce quando aplicável, código curto de uso único e comparação exata de redirect URI.
3. Emitir access tokens com `sub`, `seller_id`, `scope`, `aud` do MCP, `iss`, `iat`, `nbf`, `exp`, `jti` e identificador de grant; o MVP aceita somente seller proprietário.
4. Fixar refresh token em 30 dias, com rotação a cada uso; não permitir aumento de scope durante refresh.
5. Implementar consentimento no Dashboard: exibir nome do cliente, seller, scopes solicitados e validade; registrar quem aprovou e quando.
6. Implementar revogação por conexão no Dashboard e por evento de segurança; retorno externo não pode enumerar seller, cliente ou token.

**Aceite:** um seller autorizado recebe access token limitado ao MCP e refresh token rotativo de 30 dias; PKCE inválido, código repetido, redirect URI diferente, audience errada e refresh repetido são recusados.

## T05 — Dashboard: gerenciamento de conexões de IA

**Repositório:** `dashboard-seller`.

**Dependências:** T04.

1. Criar área “Conexões de IA” somente para o seller proprietário autenticado.
2. Exibir conexão, cliente, scopes, criada em, último uso, expiração, status e ação de revogar.
3. Permitir escolher apenas scopes definidos pela Lowify: overview, vendas, produtos e assinaturas. Não permitir criar scope ou enviar `seller_id` manualmente.
4. Alteração de scopes deve revogar o grant anterior e exigir novo consentimento; não editar token já emitido.
5. Implementar telas de consentimento/erro neutras para autorização OAuth, sem exibir token, segredo, URL interna ou dado de outro seller.

**Aceite:** seller cria e revoga uma conexão permitida; conexão revogada desaparece/é marcada inativa e não volta a renovar token.

## T06 — Rota MCP no `edge-gateway`

**Repositório:** `edge-gateway`.

**Dependências:** T02 e T04.

1. Criar rota dedicada, por domínio `mcp.lowify.com` ou caminho `/mcp`, que encaminhe diretamente para `services-ai-mcp`.
2. Aplicar TLS, limite de tamanho de corpo, WAF e rate limit bruto por IP/cliente na borda. Limites de negócio por seller/tool pertencem ao MCP.
3. Preservar headers MCP e `Authorization` até o MCP, sem registrar seu valor no middleware de auditoria existente.
4. Validar `Origin` conforme a política do transporte MCP; negar host/origin não esperado antes do serviço.
5. Não encaminhar a rota para `edge-public-api` e não aplicar envelopes de resposta próprios das APIs atuais a respostas MCP/JSON-RPC.

**Aceite:** `/mcp` chega ao serviço MCP sem alteração do payload JSON-RPC; requests não MCP não recebem acesso às rotas atuais; headers sensíveis não aparecem nos logs do Gateway.

## T07 — Núcleo de protocolo e autorização no `services-ai-mcp`

**Repositório:** `services-ai-mcp`.

**Dependências:** T02, T04 e T06.

1. Implementar Streamable HTTP stateless e os métodos MCP necessários ao catálogo inicial: descoberta/inicialização compatível, `tools/list` e `tools/call`.
2. Implementar metadados de protected resource e resposta `401` compatível com OAuth para requisições sem token ou token inválido.
3. Validar assinatura pela JWKS de `services-auth`, issuer, audience do MCP, expiração, `jti`, grant revogado, seller e scopes antes de qualquer tool.
4. Criar `McpIdentityContext` imutável por request. O seller vem exclusivamente desse contexto.
5. Calcular `tools/list` a partir dos scopes; toda tool indisponível não deve ser anunciada nem executada.
6. Usar JSON Schema fechado e DTOs; limite tamanho, profundidade e campos desconhecidos dos argumentos.
7. Retornar erros MCP estáveis e sem detalhes de serviço: `invalid_arguments`, `forbidden`, `not_found`, `rate_limited`, `source_unavailable` e `result_too_large`.

**Aceite:** token de outro audience, token revogado, seller no argumento, schema inválido e scope ausente não chegam aos conectores; `tools/list` varia corretamente por identidade.

## T08 — Contratos internos seguros de leitura no Commerce V2

**Repositório:** `services-commerce-v2`.

**Dependências:** T04 e T07.

1. Criar autenticação serviço-a-serviço para MCP seguindo o padrão interno já aprovado, com audience/assinatura/timestamp e proteção contra replay.
2. Criar grupo `/internal/mcp/v1` exclusivo, inacessível pelo Gateway público, com DTOs mínimos e versionados.
3. Implementar policy que recebe seller autenticado do chamador interno; nunca confiar em `seller_id` de query/body externo.
4. Criar contratos para lookup barato: lista de produtos cursorizada, detalhe/resumo de produto, detalhe sanitizado de venda e lista/detalhe sanitizados de assinatura.
5. Criar DTO de venda sem comprador, e-mail, telefone, CPF/CNPJ, endereço, IP, user-agent, tracking, conteúdo de comunicação, segredo de PSP ou credencial.
6. Não reaproveitar `SearchSalesUseCase` administrativo nem `GetSaleDetailOverviewUseCase` diretamente; extrair query/use case específico e testado.
7. Garantir filtros em allowlist, cursor opaco, ordenação indexada, máximo de 50 itens e autorização de recurso em cada detalhe.

**Aceite:** Commerce V2 oferece respostas mínimas e seller-scoped; uma chamada MCP não consegue ler venda, produto ou assinatura de outro seller nem produzir resposta com PII proibida.

## T09 — Read model de métricas comerciais

**Repositórios:** `services-commerce-v2`, `services-ai-mcp`.

**Dependências:** T08.

1. Mapear os eventos existentes de criação/confirmação/refund de venda e mudança de produto antes de criar qualquer consumidor.
2. Definir contrato versionado de eventos ou feed incremental. Não alterar payload de fila existente sem compatibilidade e rollout coordenado.
3. Criar projeções próprias do MCP para overview, vendas por dia/produto/método e desempenho de produto.
4. Implementar consumidor idempotente, checkpoint, retry, DLQ, métrica de lag e reconstrução por seller/período.
5. Criar índices de consulta no read store para seller, período, produto, status e ordenação usada pelas tools.
6. Implementar reconciliação limitada e assíncrona; ela nunca executa no caminho de uma chamada MCP.

**Aceite:** overview e resumo de vendas são atendidos pelo read store para períodos suportados; evento repetido ou fora de ordem não duplica métricas; lag e DLQ são observáveis.

## T10 — Cache, quotas e resiliência do MCP

**Repositório:** `services-ai-mcp`.

**Dependências:** T07, T08 e T09.

1. Implementar Redis exclusivo com chaves que incluam versão, seller, scopes/policy, tool e argumentos normalizados.
2. Aplicar cache inicial: overview/vendas recentes 60 s; produtos 5 min; detalhe de venda 30 s; métricas históricas 5 min. Expor `generated_at` e `freshness_seconds` nas respostas agregadas.
3. Implementar single-flight por chave de cache para impedir recomputação concorrente idêntica.
4. Configurar pools por dependência, timeout de conexão, timeout por origem, timeout total, bulkhead e circuit breaker.
5. Definir quotas por conexão OAuth, seller e tool; iniciar com valores conservadores apenas em homologação e calibrar com teste de carga antes de produção.
6. Em cache vencido ou dependência degradada, responder com cache stale permitido e sinalizado para agregados ou `source_unavailable`; nunca recalcular relatório pesado no Commerce como fallback.

**Aceite:** chamadas idênticas concorrentes geram uma só leitura de origem; falha/lentidão de Commerce não satura workers MCP; cache de um seller não é retornado a outro.

## T11 — Implementar e ativar as tools do piloto

**Repositório:** `services-ai-mcp`.

**Dependências:** T07, T08, T09 e T10.

1. Implementar `get_business_overview`, limitado a hoje, 7 dias e 30 dias.
2. Implementar `list_products`, com cursor, máximo de 50 registros e campos de catálogo aprovados.
3. Implementar `get_sales_summary`, com períodos até 90 dias, agrupamentos permitidos (`day`, `product`, `payment_method`) e máximo de 100 buckets.
4. Adicionar descrição de tool orientada ao usuário, schema rigoroso, scope requerido, DTO de resposta e metadados de frescor.
5. Proteger ativação de cada tool por feature flag e allowlist de seller/cliente durante o piloto.

**Aceite:** as três tools são listadas apenas para grants autorizados, devolvem dados do seller correto, respeitam limites e não acionam consulta pesada na origem.

## T12 — Auditoria, observabilidade e testes de segurança

**Repositórios:** `services-auth`, `edge-gateway`, `services-ai-mcp`, `services-commerce-v2`.

**Dependências:** T11.

1. Criar auditoria pseudonimizada: grant/conexão, seller, cliente, tool, filtros normalizados, resultado, latência, cache hit/miss e request id.
2. Redigir centralmente Authorization, token, refresh token, CPF, e-mail, telefone, payload integral e resposta integral em logs/erros.
3. Instrumentar métricas de OAuth, tools, latência, origem, cache, quota, breaker, tamanho de resposta, read model, retry e DLQ.
4. Criar testes de segurança: PKCE, redirect URI, replay de code/refresh, audience, revogação, scope, ID de outro seller, enumeração e cache cross-tenant.
5. Criar testes de carga: repetição de consultas, pico distribuído por sellers, cache stampede, Commerce lento/indisponível e esgotamento de pool.

**Aceite:** nenhum cenário de teste expõe segredo/PII proibida; métricas e logs identificam a cadeia Gateway → MCP → Commerce sem dados sensíveis; os mecanismos de proteção operam sob carga.

## T13 — Homologação e liberação controlada

**Repositórios:** todos os anteriores e `docs`.

**Dependências:** T12.

1. Preparar documentação de deploy por repositório, migrations, variáveis sem valores, ordem de implantação e rollback.
2. Executar teste de compatibilidade em homologação com sellers sintéticos: consentimento, login OAuth, refresh, revogação, Gateway, tool call, cache, read model e falha de dependência.
3. Homologar Codex, Claude e Gemini um a um; liberar somente os clientes que passarem a matriz T01.
4. Produção: habilitar por feature flag para allowlist interna de sellers; liberar uma tool de cada vez e observar os indicadores antes da próxima.
5. Rollback: desabilitar tool/feature flag, revogar grants e retirar rota do Gateway sem alterar tabelas ou filas de Commerce.

**Aceite:** o piloto pode ser interrompido sem degradar fronts, Gateway, Commerce V2, Auth, Wallet ou bancos transacionais.

## Após o piloto

Não iniciar antes do aceite de T13:

- `get_product_summary`, `list_sales`, `get_sale_summary` e `list_subscriptions`.
- colaboradores e matriz de permissões MCP;
- Wallet, Banking, recebíveis e saldo;
- Dynamic Client Registration ou outros clientes de IA;
- tools de escrita, como publicação de produto ou reembolso.

## Referências de descoberta

- `services-auth/config/routes.php`
- `services-auth/app/{Controller,Service,Model}`
- `edge-gateway/config/routes.php`
- `edge-gateway/app/{Http,Middleware}`
- `services-commerce-v2/config/routes.php`
- `services-commerce-v2/app/Application/UseCase/{Dashboard,Product,Sale,Subscription}`
- `services-commerce-v2/app/Domain/{Product,Sale,Subscription}/Repository`
- [Planejamento e decisões MCP](README.md)
