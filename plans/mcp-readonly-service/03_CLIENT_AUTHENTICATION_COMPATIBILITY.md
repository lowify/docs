# Autenticação de clientes MCP — OAuth e compatibilidade com Grok

> Estado: decisão de produto para o piloto MCP.
>
> Atualizado em: 2026-11-19

## Decisão

OAuth 2.1 é o método padrão e obrigatório para clientes MCP que o suportam, como ChatGPT e Claude. O Grok, na interface atualmente disponível para conectores MCP customizados, aceita somente URL e cabeçalhos estáticos; ele não abre o navegador para autorização OAuth nem administra tokens por usuário.

Não será introduzida uma chave estática apenas para contornar essa limitação durante o piloto. O Grok permanece como cliente pendente de compatibilidade OAuth. Caso a prioridade de produto mude, a alternativa de chave de integração deverá ser implementada como uma capacidade separada, com os controles descritos neste documento.

## OAuth 2.1 — ChatGPT e Claude

### Fluxo

```text
Seller conecta o MCP no cliente de IA
  → cliente descobre que a tool exige OAuth
  → cliente abre o Dashboard Lowify
  → seller faz login e aprova os scopes
  → Authorization Server emite access token de curta duração
  → cliente chama MCP com Authorization: Bearer <access_token>
  → cliente usa refresh token rotativo quando o access token expira
```

O fluxo usa Authorization Code com PKCE (`S256`). O cliente não recebe senha da Lowify e o MCP não recebe refresh token.

### Escopos iniciais

| Scope | Permite |
| --- | --- |
| `mcp.sales.read` | Resumos agregados de vendas e visão do negócio. |
| `mcp.products.read` | Listagem de produtos do seller. |

Os scopes não substituem a policy de ownership: o seller efetivo vem do token assinado e nunca de argumento da tool.

### Tokens e revogação

| Item | Política atual |
| --- | --- |
| Access token | Curta duração; usado nas chamadas MCP. |
| Refresh token | Validade máxima de 30 dias, rotação a cada uso e armazenamento somente como hash. |
| Revogação | O seller pode revogar a conexão no Dashboard; o grant deixa de renovar e novas chamadas são negadas. |
| Escopos | Alterar scopes exige novo consentimento; não se amplia escopo em refresh. |

### Benefícios

- O seller autentica diretamente no Dashboard Lowify.
- Não há cópia manual de chave de API nem compartilhamento de senha com a IA.
- Access tokens curtos reduzem a janela de exposição.
- Refresh token permite continuidade sem pedir login a cada consulta, com rotação e prazo limitado.
- Cada conexão pode ser revogada individualmente.
- O mesmo cliente pode atender vários sellers sem misturar identidades.
- Scopes limitam a superfície de dados que cada conexão consegue consultar.

### Limitações

- Depende de suporte OAuth no cliente MCP.
- Exige compatibilidade entre descoberta MCP, redirect URI, PKCE, consentimento, token e refresh.
- Uma revogação, expiração de refresh ou mudança de escopo pode exigir novo login do seller.
- A homologação deve ser feita por cliente de IA; não se assume que todo cliente MCP implementa OAuth da mesma forma.

## Grok — estado atual

### Limitação observada

A criação de servidor MCP customizado no Grok disponível no piloto fornece campos para:

- nome;
- URL do servidor;
- cabeçalhos estáticos chave/valor.

Ela não expõe configuração OAuth, não abre o Dashboard Lowify para consentimento e não armazena/renova tokens por seller. O Grok consegue descobrir e mostrar as tools, mas chama uma tool protegida sem `Authorization: Bearer`, sendo corretamente recusado pelo MCP.

Esta é uma limitação do cliente Grok/xAI, não do Authorization Server da Lowify. O mesmo OAuth MCP foi validado de ponta a ponta com ChatGPT.

### Caminho preferido

Quando o Grok/xAI disponibilizar OAuth ou Dynamic Client Registration (DCR) em conectores MCP customizados, validar:

1. cadastro do conector em `https://mcp.statuslive.site/mcp`;
2. descoberta de protected resource e Authorization Server;
3. registro dinâmico do cliente, quando adotado pelo Grok;
4. redirect ao Dashboard Lowify;
5. login do seller e consentimento de `mcp.sales.read` e/ou `mcp.products.read`;
6. troca de código com PKCE;
7. chamada autenticada de `list_products` e `get_sales_summary`;
8. renovação e revogação da conexão.

A infraestrutura Lowify já suporta OAuth 2.1, PKCE, DCR, escopos, refresh token rotativo e revogação; a pendência é a capacidade na interface/API do Grok.

## Alternativa condicional: chave de integração para Grok

Esta alternativa só deve ser aprovada se houver necessidade comercial de suportar o Grok antes de OAuth estar disponível nele. Ela **não substitui OAuth** e não deve ser usada por clientes que suportam OAuth.

### Experiência do seller

```text
Seller autenticado no Dashboard
  → cria “Chave para Grok”
  → escolhe scopes de leitura permitidos
  → copia o valor uma única vez
  → configura no Grok:
       Authorization: Bearer lfy_mcp_<segredo>
  → Grok envia esse mesmo cabeçalho em cada chamada MCP
```

O MCP valida a chave, resolve o seller e aplica os mesmos scopes e policies das conexões OAuth.

### Controles obrigatórios

| Controle | Regra |
| --- | --- |
| Formato | Segredo aleatório de alta entropia, com prefixo identificável, por exemplo `lfy_mcp_...`. |
| Armazenamento | Persistir somente hash; o valor integral é exibido uma única vez. |
| Escopo | Apenas scopes MCP predefinidos e somente leitura. |
| Seller | Chave vinculada a um único seller proprietário. Nunca aceita `seller_id` em header, query ou tool. |
| Expiração | Máximo inicial de 30 dias; sem renovação automática. |
| Revogação | Ação imediata no Dashboard; regenerar invalida a chave anterior. |
| Inventário | Dashboard lista nome, scopes, criação, expiração, último uso e status, sem expor o segredo. |
| Auditoria | Registrar criação, uso, revogação, falhas e request ID, sem registrar a chave. |
| Limites | Mesmo rate limit por seller/tool do OAuth, além de limites de IP e proteção contra tentativas de adivinhação. |
| Transporte | Aceitar apenas por HTTPS no header `Authorization`; nunca em URL, query string, logs ou mensagens de erro. |

### Benefícios

- Funciona com o formulário atual do Grok, que aceita cabeçalhos estáticos.
- Mantém o seller e os scopes vinculados à credencial.
- Não requer callback, navegador ou suporte OAuth do cliente.
- Pode ser revogada pelo seller sem alterar a conta Lowify.

### Riscos e desvantagens

- A chave precisa ser copiada e colada manualmente.
- Quem a obtiver poderá consultar os dados liberados até expiração ou revogação.
- O Grok não consegue renovar a chave: o seller deve gerar e colar outra ao expirar.
- Não há consentimento OAuth dentro da conversa do Grok.
- A implementação adiciona gestão de segredos, inventário, auditoria e suporte operacional que OAuth já entrega de forma padronizada.

## Comparativo

| Tema | OAuth 2.1 — ChatGPT/Claude | Chave de integração — Grok atual |
| --- | --- | --- |
| Login no Dashboard | Sim, a cada autorização necessária | Apenas para gerar/revogar a chave |
| Segredo copiado manualmente | Não | Sim |
| Renovação automática | Sim, por refresh token | Não |
| Expiração | Access token curto + refresh de até 30 dias | Chave com prazo fixo, inicialmente até 30 dias |
| Revogação | Por conexão OAuth | Por chave no Dashboard |
| Scopes | Sim | Sim |
| Isolamento por seller | Sim | Sim, se a chave for vinculada ao seller |
| Risco de vazamento | Menor, por tokens curtos e fluxo gerenciado | Maior, por segredo estático copiado pelo usuário |
| Compatibilidade com o Grok atual | Não | Sim |
| Recomendação | Padrão oficial | Exceção de compatibilidade, mediante aprovação |

## Critério para decisão futura

Priorizar a alternativa de chave somente se a necessidade de operar no Grok antes de OAuth superar o custo e o risco de uma credencial estática. Caso aprovada, abrir uma entrega própria com alterações em `services-auth`, `services-ai-mcp` e `dashboard-seller`, migrations aditivas, testes de revogação/expiração e validação de segurança em homologação.
