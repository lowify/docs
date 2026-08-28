# Tasks executáveis — JWT de colaborador

## Regras de execução

- Executar em ordem; uma task só inicia quando suas dependências estiverem aceitas.
- O CRUD de colaboradores permanece no `dashboard-seller`.
- Não criar permission keys. Reutilizar exatamente: `dashboard`, `products`, `products_edit`, `sales`, `sale_detail`, `balance`, `membros`, `order_bumps`, `upsells`, `integracoes` e `disputes`.
- Aplicar o guard apenas às rotas que o Dashboard já chama via Gateway/Public API.
- Manter a whitelist/sessão local durante toda esta entrega.
- `LoginAccessService` não será alterado no MVP. Auditoria detalhada de ator/owner fica como evolução posterior.

## T01 — Fechar inventário de rotas remotas ✅

**Dependências:** nenhuma.

Levantamento concluído em 2026-08-26. Foram inspecionados os usos de `GatewayJwtClient`/serviços correlatos no Dashboard e as declarações correspondentes em `edge-public-api/routes/api.php`.

### Rotas incluídas no MVP

| Método e rota Public API | Origem atual no Dashboard | Permission key existente | Tipo | Regra de seller |
| --- | --- | --- | --- | --- |
| `GET /products/overview` | `products.php` via `ProductsService::overview()` | `products` | navigation | Resolver pelo JWT para colaborador. |
| `GET /products/{product_id}/form-data` | `product_form.php` via `ProductsService::formData()` | `products_edit` | navigation | Ignorar o `user_id` opcional enviado hoje e usar o seller do JWT. |
| `POST /products` | `api/product/create.php` quando Commerce V2 está ativo | `products_edit` | api | Forçar owner/seller do JWT no payload interno. |
| `PATCH /products/{product_id}` | `api/product/update.php` quando Commerce V2 está ativo | `products_edit` | api | Validar ownership pelo seller do JWT; não confiar no payload. |
| `PATCH /products/{product_id}/banners` | `api/product/update_banners.php` quando Commerce V2 está ativo | `products_edit` | api | Validar ownership pelo seller do JWT. |
| `GET /sales` | `api/dashboard/sales/list.php` | `sales` | api | O controller deve usar `seller_id` do JWT em vez de `sub` para colaborador. |
| `GET /checkout-transparent/integrations` | `api/dashboard/checkout_transparent/integrations.php` | `integracoes` | api | Seller do JWT. |
| `POST /checkout-transparent/integrations` | mesmo endpoint local | `integracoes` | api | Seller do JWT. |
| `POST /checkout-transparent/integrations/{id}/validate` | mesmo endpoint local | `integracoes` | api | Validar que a integração pertence ao seller do JWT. |
| `POST /checkout-transparent/integrations/{id}/remove` | mesmo endpoint local | `integracoes` | api | Validar que a integração pertence ao seller do JWT. |
| `POST /checkout-transparent/integrations/{id}/primary` | mesmo endpoint local | `integracoes` | api | Validar que a integração pertence ao seller do JWT. |
| `POST /oauth/mercado-pago/authorization` | `CheckoutTransparentIntegrationService` | `integracoes` | api | Autorizar somente dentro do seller do JWT. |
| `GET /checkout-transparent/seller/overview` | `api/dashboard/checkout_transparent/overview.php` | `integracoes` | api | Seller do JWT. |
| `GET /checkout-transparent/billing/*` | handlers em `api/dashboard/checkout_transparent/` | `integracoes` | api | Seller do JWT; validar UUID/charge antes de retornar dados. |
| `POST /checkout-transparent/billing/open-charges/{uuid}/pix` | `billing_pix.php` | `integracoes` | api | Seller do JWT; validar ownership da cobrança. |
| `POST /checkout-transparent/billing/open-charges/{uuid}/confirm-balance` | `billing_pay_balance.php` | `integracoes` | api | Seller do JWT; validar ownership da cobrança. |

`GET /checkout-transparent/billing/*` representa somente as rotas já usadas pelo Dashboard: `charges`, `charges/{uuid}/items`, `pending-items`, `open-charges` e `open-charges/{uuid}`. Não libera rotas administrativas nem futuras rotas adicionadas sob esse prefixo.

### Rotas explicitamente excluídas

| Grupo | Motivo |
| --- | --- |
| `/admin/*`, `/baas/*`, `/reports/meds/*`, `/sales/search`, `/subscriptions/*` | Fluxos administrativos ou já negados pela whitelist de colaborador; não há permission key de colaborador aplicável. |
| `/financial-password/*`, `/auth/2fa/*`, `/user/credentials`, `/user/*` de perfil sensível | Não há key correspondente e representam credenciais/dados sensíveis do owner. |
| `/in-app-notifications/*` e `/delivery-status` | Chamadas auxiliares sem permission key de colaborador e hoje não estão liberadas pela whitelist local de API; permanecem fora deste MVP. |
| Integrações, produtos, vendas ou billing chamados fora da tabela acima | Deny-by-default até uma task futura adicionar rota e teste ao inventário. |

### Observações de compatibilidade

- As rotas de produto `POST/PATCH` dependem de `COMMERCE_V2_PRODUCTS_PATH`, cujo padrão atual é `/products`; o guard será aplicado à rota Public API correspondente somente quando o Commerce V2 estiver ativo.
- A classificação `navigation` é usada apenas para os carregamentos de página que chamam o Gateway no PHP. Os demais itens são endpoints dinâmicos do Dashboard e devem usar a resposta curta de `/api/` definida no contrato.
- A tabela não remove nem altera a whitelist em `dashboard-seller/includes/init.php`; ela define somente a segunda validação no Public API.

**Aceite:** concluído. Não há rota remota do MVP sem permission key e sem regra de owner/seller scope definida.

## T02 — Account: resolver login de colaborador ✅

**Dependências:** T01 (para validar o contrato final de permissions).

**Implementado em 2026-08-26:** modelo `Collaborator`, `LoginCollaboratorUseCase` e seleção por `type` no `AuthController`. O CRUD continua exclusivamente no Dashboard. A validação integrada contra o banco compartilhado (credencial, status do owner e atualização de `ultimo_login`) permanece prevista em T08, pois este ambiente não tem acesso de leitura ao banco remoto.

**Arquivos prováveis:**

- `services-account/app/Http/Controller/AuthController.php`
- `services-account/app/Application/UseCase/Auth/LoginCollaboratorUseCase.php` (novo)
- modelo/repositório de leitura de `tbl_colaboradores` (novo)
- testes de use case/controller (novos)

1. Criar acesso de leitura a `tbl_colaboradores`; não criar controller, rota ou use case de CRUD.
2. Validar `email`, senha por `password_verify`, `tbl_colaboradores.status = 1` e owner ativo em `tbl_usuarios`.
3. Decodificar e normalizar `permissoes`: manter somente as chaves permitidas e com valor verdadeiro.
4. Depois de validar a credencial, atualizar `ultimo_login`.
5. Retornar ao Auth somente:

```json
{
  "actor_type": "collaborator",
  "collaborator_id": 93,
  "seller_id": 1417,
  "permissao": 3,
  "permissions": ["sales", "sale_detail"],
  "identity_verification_status": "approved"
}
```

6. Manter o retorno atual de `type=user` sem mudança de semântica.
7. Para credencial inválida, colaborador inativo ou owner inativo, retornar o mesmo `invalid_credentials`/401 para não enumerar contas.

**Aceite de código:** concluído. PHPUnit direto: 4 testes/6 assertions para payload inválido e normalização de permissões; `php -l` passou nos três arquivos de produção. Os cenários que exigem banco real serão validados na homologação de T08.

## T03 — Auth: tokens tipados e refresh de colaborador 🚧

**Dependências:** T02.

**Em andamento (2026-08-26):** criada migration aditiva para `actor_type`/`actor_id` em `refresh_tokens`; emissão de token agora separa `actorId` de `sellerId`; refresh resolve colaborador novamente pelo Account. O Account recebeu `GET /auth/collaborator` interno, somente de leitura, para essa revalidação. Falta adicionar os testes específicos de emissão/rotação antes de concluir a task.

**Arquivos prováveis:**

- `services-auth/app/Controller/AuthController.php`
- `services-auth/app/Service/AccountService.php`
- `services-auth/app/Service/JwtService.php`
- `services-auth/app/Model/RefreshToken.php`
- migration aditiva de refresh tokens, se necessária
- testes unitários/integrados (novos)

1. Validar allowlist de `type` em `services-auth`: apenas `user` e `collaborator`.
2. Repassar o tipo ao Account e interpretar sua resposta tipada.
3. Para colaborador, assinar access token com `sub=collaborator_id`, `actor_type=collaborator`, `collaborator_id`, `seller_id`, `permissao` do owner e `permissions` normalizadas.
4. Para usuário, emitir `actor_type=user`, `seller_id=id_user`, preservando claims atuais.
5. Evoluir refresh tokens para guardar a identidade do ator (`actor_type` e `actor_id`) sem quebrar tokens existentes. Se a tabela atual não suportar o contexto, usar migration apenas aditiva.
6. No refresh de colaborador, consultar novamente o Account; recusar se vínculo/status deixou de ser válido e emitir tokens com permissions/seller atuais quando válido.
7. Não chamar `LoginAccessService::handleWebLogin()` para colaborador no MVP; evitar registrar `collaborator_id` como `user_id` até a auditoria ser modelada corretamente.

**Aceite:** access/refresh token de colaborador é rotacionado, contém o contexto correto e deixa de renovar após inativação/remoção; login e refresh de usuário continuam compatíveis.

## T04 — Public API: fallback do login e contexto do ator ✅

**Dependências:** T03.

**Implementado em 2026-08-26:** o endpoint de login do `edge-public-api` injeta `type=user` quando ausente e recusa tipos fora da allowlist antes de encaminhar ao Auth. Foi criado `ActorContextResolver`, que preserva o fallback de JWT legado e, para colaborador, exige `sub`, `collaborator_id`, `seller_id` e `permissions` estruturados. O resolvedor nunca usa `sub` como seller de colaborador. Testes unitários: 3 testes/6 assertions.

**Arquivos prováveis:**

- `edge-public-api/app/Http/Controllers/AuthController.php`
- `edge-public-api/app/Services/JwtPayloadService.php`
- `edge-public-api/app/Services/ActorContextResolver.php` (novo, se necessário)
- testes HTTP/unitários (novos)

1. Em `AuthController::login()`, copiar o payload e preencher `type=user` se ele estiver ausente; rejeitar tipos desconhecidos com 422 antes de chamar Auth.
2. Preservar o proxy atual do Public API para Auth e o cookie de refresh.
3. Criar resolvedor de contexto que entregue `actor_type`, `actor_id`, `seller_id`, `permissao` e `permissions`.
4. Para JWT legado sem `actor_type`, assumir `user` e resolver seller pelo comportamento atual. Isto é o fallback para quem já está rodando.
5. Para colaborador, exigir os claims estruturais e nunca usar `sub` como seller.
6. Implementar resposta 401 para contexto de ator inválido e deixar JWT inválido sob o middleware existente.

**Aceite:** login sem `type` continua funcionando como user; JWT atual de usuário continua funcionando; JWT de colaborador resolve actor e seller sem ambiguidade.

## T05 — Public API: guard reutilizável de feature 🚧

**Dependências:** T01 e T04.

**Em andamento (2026-08-26):** criado o alias `collaborator.feature` e o middleware reutilizável no `edge-public-api`. Ele resolve o contexto do ator, mantém usuário normal no fluxo atual, valida a permission key para colaborador e anexa `actor_context` à request. A negação dinâmica retorna somente o envelope curto; a de navegação retorna a primeira rota permitida. Testes unitários do resolvedor e middleware: 7 testes/14 assertions. A associação às rotas e o seller scope nos controllers permanecem em T07.

**Arquivos prováveis:**

- middleware/guard novo em `edge-public-api/app/Http/Middleware` ou serviço de autorização
- `edge-public-api/routes/api.php`
- controllers das rotas mapeadas em T01
- testes HTTP (novos)

1. Implementar guard que recebe a permission key da rota/ação.
2. Se `actor_type=user`, manter a regra atual da rota.
3. Se `actor_type=collaborator`, negar se a permission key não existir no claim `permissions`.
4. Forçar `seller_id` do contexto no controller/serviço interno e ignorar qualquer `seller_id`, `user_id` ou `id_user` recebido do cliente.
5. Revisar cada controller mapeado para não decidir acesso administrativo apenas pelo claim `permissao` quando o ator for colaborador.
6. Manter deny-by-default para rotas remotas não mapeadas.

**Contrato de negação:**

- Navegação: HTTP `403`, `error_code=feature_permission_denied` e `redirect_to` apontando para uma página permitida.
- Chamada dinâmica `/api/`: HTTP `403`, `success=false`, `data=null`, `error_code=feature_permission_denied`, sem mensagem e sem `redirect_to`.

**Aceite:** colaborador autorizado usa somente o seller do token; colaborador sem permission key recebe 403 no formato correto; owner/admin preserva o comportamento anterior.

## T06 — Dashboard: login JWT sem remover o fluxo local 🚧

**Dependências:** T03 e T04.

**Em andamento (2026-08-26):** `GatewayJwtClient::login()` passou a aceitar `type` (padrão `user`) e o login de colaborador envia `type=collaborator`. A senha deixa de ser verificada no Dashboard: Auth/Account são a autoridade da credencial; após a resposta tipada, o Dashboard confere a identidade retornada contra o vínculo local e preserva a sessão/token legado. O cliente passa a gerar internamente `X-Dashboard-Request-Type` e o Gateway preserva `error_code`/`redirect_to`; navegações consomem `feature_permission_denied` com redirect, enquanto chamadas sob `/api/` mantêm a resposta estruturada. O `edge-gateway` já encaminha o payload e todos os headers necessários ao `edge-public-api` (incluindo `X-Dashboard-Request-Type`, `Authorization` e `Cookie`), portanto não exigiu alteração nesta etapa. `php -l` passou nos três arquivos alterados e os logins de colaborador/owner foram validados pelo domínio público após o deploy. A validação integrada de permissão depende da aplicação do guard nas rotas em T07.

**Ajuste identificado no teste integrado (2026-08-27):** a whitelist local avaliava apenas o basename do script e, por isso, negava endpoints AJAX antes da chamada ou resposta esperada. O caminho raiz também continha `includes/..`, enquanto o PHP informa o arquivo já normalizado; o cálculo foi corrigido com `realpath`. A regra agora usa o caminho relativo para endpoints sob `api/`, mapeia `api/dashboard/sales/list.php` para `sales` e a listagem de produtos para `products`. As páginas, processadores, uploads e endpoints atuais de adicionar, consultar detalhes e editar produto usam `products_edit`; páginas continuam usando o basename e todas as demais rotas locais permanecem deny-by-default.

**Sessão de colaborador:** os avisos superiores do owner não são resolvidos para colaborador, inclusive pelo fallback do `header.php`. Isso oculta avisos de cadastro pendente e de fatura do Checkout Transparente, cujas ações não pertencem ao colaborador; o aviso permanece inalterado para o owner.

**Reenviar acesso de venda:** `_resend_access_email.php` é uma ação local já oferecida na listagem de vendas. Ela usa a permission key `sales`, valida `sales.id_usuario` contra o seller da sessão antes de enfileirar a reentrega e não aceita um `order_id` de outro seller.

**Saldo:** a tela de saldo permanece acessível pela key `balance`, mas o card e o botão de solicitar saque são ocultos para colaborador. Solicitação de saque é uma ação exclusiva do owner neste MVP.

**Resumo do dashboard:** `api/dashboard_overview.php` usa a key `dashboard` e é marcado como AJAX. Assim, o colaborador autorizado recebe o resumo; uma negação retorna JSON em vez de redirecionar para `/index` e causar a chamada inválida para `/api/index`.

**Arquivos prováveis:**

- `dashboard-seller/app/services/GatewayJwtClient.php`
- `dashboard-seller/login_colaborador_process.php`
- helper/serviço que cria os headers internos de chamada ao Gateway
- testes manuais automatizáveis do login

1. Adicionar parâmetro `type` a `GatewayJwtClient::login()` e mantê-lo opcional com padrão `user` para o login normal.
2. No login de colaborador, chamar o Gateway com `type=collaborator` e armazenar access/refresh tokens retornados.
3. Após sucesso do JWT, preservar/criar a sessão de colaborador atual, inclusive `token_login`, para páginas e ações locais.
4. Não usar a sessão para decidir acesso às rotas remotas incluídas; ela serve somente como compatibilidade e proteção local.
5. Nas chamadas ao Gateway, enviar `X-Dashboard-Request-Type=navigation` para navegações e `api` para fluxos dinâmicos sob `/api/`. O valor deve ser criado no PHP do Dashboard, não repassado de header controlado pelo navegador.
6. Para resposta 403 de navegação, consumir `redirect_to` e redirecionar. Para `/api/`, devolver o corpo vazio/estruturado do contrato sem redirect automático.

**Aceite:** um colaborador consegue continuar usando páginas locais e também recebe JWT para as chamadas remotas autorizadas; 401 continua acionando o fluxo já existente de renovação/login.

## T07 — Aplicar o guard rota por rota

**Dependências:** T05 e T06.

1. Aplicar T05 somente à tabela final fechada em T01.
2. Para cada rota, criar teste de: owner, colaborador autorizado, colaborador sem key e tentativa de trocar seller.
3. Validar que rotas que continuam locais não sofreram mudança de comportamento.
4. Atualizar a matriz em `04_ACEITE_E_MATRIZ.md` com a rota concreta e o status de implementação.

**Aceite:** todas as rotas remotas selecionadas possuem teste e permission key; nenhuma rota fora da lista é alterada.

## T08 — Validação integrada, rollout e operação

**Dependências:** T07.

1. Validar em ambiente de homologação: login normal, login de colaborador, refresh, navegação permitida, navegação negada, `/api/` negada e seller scope forçado.
2. Validar que desativar/remover colaborador impede refresh subsequente, conforme a política de TTL escolhida.
3. Liberar por feature flag de emissão de JWT de colaborador.
4. Monitorar erros 401, `feature_permission_denied`, `seller_scope_denied` e falhas de refresh, sem logar token/senha.
5. Documentar o comportamento de rollback: desativar a emissão JWT de colaborador e manter login/sessão local intactos.

**Aceite:** rollout pode ser revertido sem afetar JWT de usuário nem páginas locais do Dashboard.

## Pós-MVP — auditoria de login de colaborador

Não bloqueia T01–T08. Quando priorizado, evoluir `auth_sessions` para registrar owner e ator em campos distintos, sem usar `tbl_colaboradores.id` no atual `user_id` que representa `tbl_usuarios`.
