# Plano — acesso direto ao conteúdo por e-mail após pagamento

> Status: primeira implementação concluída; aguardando validação integrada
> Última atualização: 2026-09-16

## Objetivo

Após a confirmação de uma compra com entrega por e-mail, levar o comprador diretamente à página `access` do `front-member-area`, sem exibir a página de sucesso genérica. O acesso deve continuar seguro e conservar o funil de upsell já existente.

## Vocabulário confirmado

| Termo de produto | Campo no código | Valor |
| --- | --- | --- |
| Entrega única | `tbl_produtos.purchase_type` | `ONE_TIME` |
| Assinatura | `tbl_produtos.purchase_type` | `SUBSCRIPTION` |
| Área de membros | `tbl_produtos.tipo_entrega` | `members_area` |
| Entrega por e-mail/conteúdo | `tbl_produtos.tipo_entrega` | `email` |

Produtos `members_area` permanecem sem alteração. A nova regra vale para `tipo_entrega = email`, tanto em `ONE_TIME` quanto em `SUBSCRIPTION`, reutilizando a página de conteúdo/acesso já existente no `front-member-area`.

## Fluxo atual confirmado

```text
Pagamento aprovado
  -> Commerce V2: GET /checkout/check-payment-status
  -> redirect_url_after_payment configurada, se existir
  -> primeiro upsell ativo, se existir
  -> front-checkout/success.php
```

O processamento assíncrono de venda paga marca a venda como `paid` e, para produtos `members_area`, gera um token de ativação no cliente. O link atual abre `membros_autologin.php?token=...`, cria a sessão e termina no dashboard, não na página do produto.

## Fluxo alvo proposto

```text
Pagamento aprovado
  -> mantém redirect customizado explícito, se houver
  -> mantém upsell; ao fim/recusa do funil usa o destino final da venda
  -> email (ONE_TIME ou SUBSCRIPTION)
       -> URL de acesso com token da venda
       -> front-member-area/access.php valida o token e renderiza o conteúdo do produto
  -> demais produtos
       -> success.php ou comportamento já configurado
```

## Decisões de precedência propostas

1. `redirect_url_after_payment` preenchida pelo produtor permanece como override explícito.
2. Upsell permanece antes do acesso direto: não deve ser pulado pela nova regra.
3. Ao terminar, pular ou recusar todos os upsells, o funil usa o mesmo destino final calculado para a compra principal.
4. Sem upsell, o comprador segue imediatamente para o destino final.
5. A regra nova vale para qualquer venda paga cuja entrega do produto principal seja `email`, seja `ONE_TIME` ou `SUBSCRIPTION`; produtos `members_area` permanecem no comportamento atual.

## Alterações previstas

### Commerce V2

- Extrair um resolvedor único do destino final pós-pagamento, usado por `GetCheckoutPaymentStatusUseCase` e pelo término do funil de upsell.
- Carregar `tipo_entrega` e o produto principal no contexto de roteamento.
- Para a combinação elegível, criar ou reutilizar o token de acesso da venda antes de devolver o status `paid`; a rota de polling não pode depender da conclusão posterior da fila de entrega.
- Reutilizar o `CreatePaidSaleAccessLinkUseCase`, que já gera o token da venda para produtos que não são `members_area`, garantindo idempotência em consultas repetidas.
- Retornar uma URL absoluta `https://members.lowify.com.br/access?t={token}`, sem expor senha ou e-mail.
- Adaptar o contexto/declínio do upsell para receber o destino final; hoje ele cai diretamente em `/success` quando não há próxima etapa.

### Front checkout

- Manter `api/check_payment_status.php` como adaptador do contrato do Commerce V2, aceitando o novo destino de member area.
- Atualizar a normalização de URLs e testes para não transformar uma URL absoluta de `members.lowify.com.br` em rota local.
- Garantir que as saídas de upsell (aceite, recusa, downsell e cross-sell) respeitem o destino final calculado pelo backend.
- Não alterar tracking de Purchase: o redirecionamento ocorre após a confirmação, como hoje.

### Front member area

- Reutilizar `access.php`, que já consulta `POST /sales/access/content` com o token da venda e renderiza título, descrição, PDFs e produtos.
- Transformar `access_check.php` na entrada de autorização por e-mail do terceiro ao quinto IP, ou quando esses IPs não tiverem cookie válido.
- Não alterar `membros_autologin.php`, `membros_view.php` ou o login da área de membros, pois eles pertencem ao fluxo que continuará existente para `members_area`.

## Segurança e consistência

- Não aceitar uma URL de retorno arbitrária enviada pelo browser; o destino é composto exclusivamente pelo backend a partir da venda paga.
- O token de acesso da venda deve ser criado/reutilizado de forma idempotente por venda; o novo controle por cookie/IP preserva o acesso público inicial e acrescenta a validação por e-mail após o segundo IP.
- O endpoint de status continua a devolver destino somente para venda paga e encontrada.
- Vendas estornadas, contestadas ou com acesso revogado não devem ganhar sessão nem abrir o produto.
- Uma compra com order bump não deve alterar o destino decidido pelo produto principal.

## Controle de sessões de acesso por IP e cookie

### Comportamento atual confirmado

- Uma venda paga de produto que não é `members_area` recebe um único token UUID em `sales_access_links`.
- `access.php` envia somente `token` e IP para `POST /sales/access/content`. Enquanto o link está em modo `public`, o conteúdo abre sem pedir e-mail.
- O Commerce V2 registra IP em `sales_access_sessions`, mas não cria nem valida cookie de acesso.
- O reuso de um IP só vale por 30 minutos. Depois desse intervalo, o mesmo IP pode gerar outro registro; o contador é cumulativo.
- O limite configurado é 3, mas a condição atual é `> 3`: o quarto IP ainda recebe o conteúdo e só então o link se torna `restricted`.
- Quando o link é restrito, até os IPs já usados precisam informar e-mail. Não há reconhecimento dos três acessos anteriores.
- Há ainda uma rotina que restringe todo link público após 24 horas, independentemente de cookie ou quantidade de IPs.

### Regra alvo confirmada

1. Os dois primeiros IPs distintos abrem `access?t=...` em modo público, sem pedir e-mail, e recebem cookie persistente e seguro.
2. Do terceiro ao quinto IP distinto, a página pede o e-mail usado na compra antes de liberar e gravar o cookie.
3. Cookie válido **e** IP correspondente liberam diretamente o conteúdo, sem novo formulário e sem criar nova sessão.
4. Um novo navegador no mesmo IP rotaciona/repõe o cookie da sessão daquele IP, sem consumir uma vaga adicional.
5. A partir do sexto IP distinto, não há conteúdo nem criação de sessão. Sem expor o motivo, a tela informa que o conteúdo agora é acessível apenas pela Área de Membros e oferece o botão para enviar o link de login.
6. O link de login leva ao dashboard existente, que já lista compras de entrega por e-mail e abre seu conteúdo. Ele não cria uma nova sessão de `sales_access_sessions`.
7. Sem cookie válido, o IP pode reutilizar a sessão existente por 24 horas. Com cookie válido, essa consulta de reuso é ignorada: a validação do cookie/IP é suficiente e tem prioridade.

### Implementação proposta

#### Commerce V2

- Evoluir `sales_access_sessions` para guardar um identificador secreto de cookie em hash, ligado a `sales_access_link_id`, IP, e datas de criação/último acesso/expiração. O valor bruto nunca é persistido.
- Criar índice único por link + IP e consultas explícitas para: validar cookie no IP, localizar sessão reutilizável por IP em até 24 horas, criar/rotacionar a sessão daquele IP e contar IPs distintos autorizados.
- Manter o modo público para os dois primeiros IPs e trocar para estado `email_required` do terceiro ao quinto. O endpoint deve retornar estados explícitos: `content`, `email_required` e `session_limit_reached`.
- Exigir e validar o e-mail da venda para criar ou repor sessão a partir do terceiro IP. A contagem de cinco deve ocorrer antes da criação, dentro de transação/lock que impeça duas requisições paralelas de abrir sexto IP.
- Configurar `reuse_window_seconds` para 24 horas. A janela serve somente para encontrar um IP sem cookie que possa receber cookie reposto; ela não é consultada quando cookie e IP já forem válidos.
- Remover ou adaptar a restrição global de 24 horas, pois ela contradiz o acesso posterior por cookie dos cinco IPs autorizados.
- Manter os tokens UUID das vendas e a verificação de venda/conteúdo; a mudança não deve expor conteúdo em resposta de erro.

#### Front member area

- `access.php` lê o cookie específico da venda e o envia ao Commerce V2 com token e IP. O nome do cookie é derivado do hash do token de acesso, permitindo várias compras no mesmo navegador. Se a sessão for válida, renderiza o conteúdo e ignora a janela de reuso de IP. Sem cookie, tenta reutilizar IP visto nas últimas 24 horas; fora dessa janela, mantém o acesso público até dois IPs e encaminha o terceiro ao quinto IP para `access_check.php`.
- `access_check.php` envia token, e-mail, IP e cookie específico da venda (se existir). Ao receber uma sessão criada/rotacionada, grava o cookie com `Secure`, `HttpOnly`, `SameSite=Lax`, `Path=/` e `Max-Age` de 30 dias; em seguida redireciona para `access?t=...` para a validação normal renderizar o conteúdo.
- Guardar no `$_SESSION` PHP apenas o contexto de navegação necessário. A autorização durável fica no Commerce V2; não colocar IP, e-mail ou autorização confiável dentro do cookie do navegador.
- Para `session_limit_reached` (sexto IP), exibir uma tela sem conteúdo, com botão “Enviar link de acesso”. O botão chama um endpoint dedicado e recebe uma resposta genérica, evitando enumeração de e-mails.
- Reutilizar o envio de magic link existente para levar o cliente ao dashboard. Antes disso, mover o cooldown do envio para armazenamento compartilhado/servidor e manter reCAPTCHA, pois o limitador atual depende só da sessão PHP e é facilmente reiniciado.

### Decisões de segurança

- O cookie será opaco e aleatório; IP não deve ser gravado nele. O IP é armazenado e comparado exclusivamente no servidor.
- A sessão persistida no Commerce V2 terá a mesma expiração de 30 dias do cookie. Após esse prazo, o cookie deixa de liberar conteúdo e o IP segue novamente a regra de acesso aplicável.
- A posse do cookie sem o IP correspondente não libera conteúdo. Do terceiro ao quinto IP, a mudança de IP solicita e-mail; o sexto IP não recebe uma sessão nova.
- A janela de reuso de IP é de 24 horas e vale somente sem cookie. Ela não adiciona novo IP ao limite de cinco; passado o prazo, o IP continua no histórico e não deve reabrir vaga, mas volta ao fluxo aplicável a acessos sem cookie.
- O IP deve ser resolvido apenas a partir de cabeçalhos encaminhados por proxies confiáveis. O uso atual de `X-Forwarded-For` no front precisa ser validado contra a configuração de proxy para evitar falsificação de IP.
- O envio de magic link no sexto IP deve usar mensagem genérica, cooldown persistente por e-mail/IP e auditoria sem registrar tokens ou dados sensíveis em log.

### Cenários adicionais de aceite

1. Primeiro e segundo IP sem cookie: abrem conteúdo público e cada um recebe seu cookie.
2. Retorno no mesmo navegador/IP: abre direto e atualiza `accessed_at`, sem formulário nem nova sessão.
3. Cookie apagado no mesmo IP: repõe/rotaciona o cookie, sem aumentar o total de IPs autorizados; no terceiro ao quinto IP, solicita e-mail antes de repor.
4. Terceiro, quarto e quinto IP: e-mail correto cria as respectivas sessões e cookies.
5. Sexto IP: e-mail correto não retorna conteúdo, não grava cookie de acesso e oferece envio de link mágico; os cinco IPs anteriores continuam funcionando com seus cookies.
6. Cookie copiado para IP diferente, cookie inválido e e-mail incorreto: não retornam conteúdo nem criam sessão.
7. Dois acessos simultâneos tentando ocupar a quinta vaga não podem resultar em seis IPs autorizados.
8. Após 30 dias, um cookie expirado não libera conteúdo; o comportamento seguinte respeita a quantidade de IPs já autorizados e não reabre vagas indevidamente.
9. Sem cookie, o mesmo IP acessado há menos de 24 horas recebe cookie reposto sem consumir vaga. Com cookie válido, o conteúdo abre diretamente sem executar essa checagem de reuso.

## Cenários de aceite

1. `ONE_TIME + email`, sem upsell: pagamento por Pix e cartão abre diretamente `access?t=...` com o conteúdo da compra.
2. Mesmo produto com upsell: a oferta abre primeiro; aceitar, recusar, downsell e cross-sell terminam em `access?t=...`.
3. `ONE_TIME + members_area`: continua o fluxo atual de área de membros.
4. `SUBSCRIPTION + email`: a confirmação que ocorre no navegador após a contratação segue para `access?t=...`; renovações automáticas, que não têm navegador ativo, mantêm a entrega assíncrona existente. `SUBSCRIPTION + members_area` mantém o fluxo atual de área de membros.
5. URL customizada do produto: mantém prioridade sobre a regra nova.
6. Token inválido ou adulterado não entrega conteúdo; do terceiro ao quinto IP, acesso sem cookie válido exige o e-mail correto no `access_check.php`.
7. Repetir o polling/recarregar a página de confirmação devolve o mesmo token de acesso, sem efeitos extras.

## Componentes e referências

- `front-checkout/api/check_payment_status.php`
- `front-checkout/show_upsell.php`
- `services-commerce-v2/app/Application/UseCase/Product/GetCheckoutPaymentStatusUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Product/GetCheckoutUpsellContextUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/CreatePaidSaleAccessLinkUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPaidSaleEventUseCase.php`
- `front-member-area/access.php`
- `front-member-area/access_check.php`

## Implementação realizada

- `services-commerce-v2` — commit `7ef097a`: destino pós-pagamento para `access` em produtos `email`, preservação do destino após upsell, migração de sessão por IP/cookie e estados de autorização.
- `front-member-area` — commit `3c0a249`: leitura e emissão do cookie seguro de 30 dias, encaminhamento para validação de e-mail e tela de limite de dispositivos.
- `front-checkout` — commit `1d99550`: término de upsell usa o destino final calculado, inclusive downsell e cross-sell.

### Validação pendente

- Executar a migração `20260916120000_add_cookie_to_sales_access_sessions.sql` no banco do Commerce V2 antes da homologação.
- Validar em homologação a matriz de IPs/cookie, Pix, cartão, assinatura e todos os desfechos do funil de upsell.
- A suíte local do Commerce V2 não foi executada porque o binário `co-phpunit` não está disponível no workspace.
