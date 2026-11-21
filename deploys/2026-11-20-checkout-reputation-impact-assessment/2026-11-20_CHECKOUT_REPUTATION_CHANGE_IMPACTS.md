# Impactos das mudanças em conteúdo externo e redirecionamentos do Checkout

| Campo | Valor |
| --- | --- |
| Data | 20/11/2026 |
| Estado | Material técnico para decisão |
| Ambiente da evidência | Código disponível e base de homologação; não representa inventário, tráfego ou comportamento configurado em produção |
| Escopo | Checkout público padrão e transparente, personalização de produto, redirecionamentos, upsell e superfícies públicas relacionadas |
| Referência | `security/2026-11-12_CHECKOUT_REPUTATION_REVIEW.md` |

## Contexto da decisão

Há relato de alerta de site suspeito em `pay.lowify...`. Esse alerta é um problema de reputação a tratar, mas não identifica, por si só, qual página, produto, recurso externo ou redirecionamento originou a classificação. A hipótese de conteúdo ou destinos externos configurados por sellers é tecnicamente plausível; ela não constitui atribuição comprovada da causa por um motor antivírus.

O ponto em discussão não se limita ao Checkout Transparente. A opção **Personalizar checkout**, disponível na edição de produto, persiste dados que o Checkout público consome. O mesmo `front-checkout` recebe o contexto do produto e, somente depois, identifica se aquela requisição está no modo transparente. Portanto, uma alteração nos campos compartilhados de personalização pode alcançar checkouts padrão e transparentes que usem o produto configurado.

O objetivo deste documento é deixar explícito o efeito para sellers, compradores e operação em cada direção possível. Ele não escolhe a direção nem presume que uma mudança de cabeçalho, isoladamente, resolva a reputação do domínio.

## Estado atual que produz os impactos

| Recurso | Configuração do produto | Comportamento no Checkout público |
| --- | --- | --- |
| Vídeo por embed | `checkout_config.video_type=iframe` e `video_source` | O Dashboard remove tags `<script>` e aceita HTML que contenha `<iframe>`; o frontend insere o HTML persistido na página. |
| Vídeos, imagens e banners | `checkout_config`, `checkout_banner_url` e uploads | Há caminhos com URL externa e caminhos com upload próprio. Não há política única de origem aplicada a todos os campos no modelo de produto. |
| Saída do Checkout | `checkout_url_saida` | Sem popup de saída ativo, o navegador executa `window.location.replace()` ao detectar saída da página ou o botão Voltar, desde que o valor seja uma URL válida. |
| Pós-pagamento | `redirect_url_after_payment` | Após a venda aprovada, o Commerce V2 devolve a URL persistida como ação de redirect; o navegador recebe esse destino. |
| Upsell/downsell | URLs de próxima etapa, destino final e recusa | A página de upsell converte somente rotas internas conhecidas; os demais destinos seguem como URL externa. |

O contrato de atualização do Commerce V2 trata `checkout_exit_url` e `redirect_url_after_payment` como texto. Não há, nesse ponto, relação entre a URL, o seller e uma origem previamente aprovada. O modelo atual também não registra a navegação final do navegador: uma venda permite relacionar produto e pedido, mas não prova que o comprador abriu o destino externo ou qual conteúdo recebeu nele.

## Volume observado em homologação

As consultas abaixo foram executadas apenas para leitura na base de homologação em 20/11/2026. Homologação e produção são ambientes distintos: estes totais não podem ser usados como contagem de produção, projeção de receita, quantidade de compradores afetados ou evidência de que a mesma configuração esteja publicada em produção.

Os totais medem configuração persistida, não conteúdo malicioso, denúncia, bloqueio por antivírus ou tráfego efetivo. Um produto pode aparecer em mais de uma linha; os grupos não são somáveis.

| Configuração encontrada | Produtos | Sellers distintos | Produtos sem `deleted_at` |
| --- | ---: | ---: | ---: |
| URL de saída preenchida | 991 | 273 | 866 |
| URL pós-pagamento preenchida | 1.610 | 445 | 1.418 |
| Vídeo configurado como iframe | 120 | 55 | 106 |
| URL de saída com `http://` | 8 | 2 | 6 |
| URL pós-pagamento com `http://` | 17 | 5 | 14 |
| `video_source` iniciado por `http://` | 0 | 0 | 0 |
| `checkout_banner_url` contendo `http://` | 0 | 0 | 0 |

Entre os campos preenchidos, 983 URLs de saída e 1.590 URLs pós-pagamento começam com `https://`. Três URLs pós-pagamento não começam com `http://` nem `https://`. HTTPS protege o transporte, mas não confirma controle do domínio pelo seller nem a natureza do conteúdo hospedado nele.

O inventário não inclui o conteúdo de um gerador de páginas externo ao código disponível neste ambiente. A página pública indicada em `paginas.lowify.com.br` pode encaminhar compradores para o Checkout, mas não há fonte desse construtor neste workspace para classificar seus links, embeds ou regras de publicação.

### Consulta para dimensionar produção

Antes de usar qualquer volume para decidir escopo, prazo ou comunicação, a dimensão real deve ser obtida na base de produção. A consulta a seguir foi executada com sucesso no schema atual de homologação e retorna apenas agregados: não seleciona URLs, títulos de produtos, compradores, pedidos ou dados de pagamento. Em produção, ela produz o inventário equivalente daquele ambiente.

```sql
SELECT
  'url_saida_preenchida' AS indicador,
  COUNT(*) AS produtos,
  COUNT(DISTINCT id_usuario) AS sellers,
  COALESCE(SUM(deleted_at IS NULL), 0) AS produtos_sem_deleted_at
FROM tbl_produtos
WHERE NULLIF(TRIM(checkout_url_saida), '') IS NOT NULL

UNION ALL

SELECT
  'redirect_pos_pagamento_preenchido',
  COUNT(*),
  COUNT(DISTINCT id_usuario),
  COALESCE(SUM(deleted_at IS NULL), 0)
FROM tbl_produtos
WHERE NULLIF(TRIM(redirect_url_after_payment), '') IS NOT NULL

UNION ALL

SELECT
  'video_iframe',
  COUNT(*),
  COUNT(DISTINCT id_usuario),
  COALESCE(SUM(deleted_at IS NULL), 0)
FROM tbl_produtos
WHERE JSON_UNQUOTE(JSON_EXTRACT(
  CASE
    WHEN JSON_VALID(COALESCE(checkout_config, '{}')) THEN checkout_config
    ELSE '{}'
  END,
  '$.video_type'
)) = 'iframe'

UNION ALL

SELECT
  'url_saida_http',
  COUNT(*),
  COUNT(DISTINCT id_usuario),
  COALESCE(SUM(deleted_at IS NULL), 0)
FROM tbl_produtos
WHERE checkout_url_saida LIKE 'http://%'

UNION ALL

SELECT
  'redirect_pos_pagamento_http',
  COUNT(*),
  COUNT(DISTINCT id_usuario),
  COALESCE(SUM(deleted_at IS NULL), 0)
FROM tbl_produtos
WHERE redirect_url_after_payment LIKE 'http://%'

UNION ALL

SELECT
  'video_source_http',
  COUNT(*),
  COUNT(DISTINCT id_usuario),
  COALESCE(SUM(deleted_at IS NULL), 0)
FROM tbl_produtos
WHERE JSON_UNQUOTE(JSON_EXTRACT(
  CASE
    WHEN JSON_VALID(COALESCE(checkout_config, '{}')) THEN checkout_config
    ELSE '{}'
  END,
  '$.video_source'
)) LIKE 'http://%'

UNION ALL

SELECT
  'banner_http',
  COUNT(*),
  COUNT(DISTINCT id_usuario),
  COALESCE(SUM(deleted_at IS NULL), 0)
FROM tbl_produtos
WHERE checkout_banner_url LIKE '%http://%';
```

Os indicadores se sobrepõem. O resultado informa quantos produtos e sellers exigem classificação em cada categoria, mas não mede vendas, não identifica destino malicioso e não demonstra que um redirecionamento foi seguido pelo comprador.

## Impactos por tipo de alteração

### 1. Validação somente para novas configurações

| Aspecto | Impacto esperado |
| --- | --- |
| Checkouts e funis já configurados | Continuam usando os valores já persistidos; não há interrupção imediata desses registros. |
| Seller ao salvar alteração | Pode não conseguir salvar uma nova URL, vídeo ou embed que esteja fora da regra escolhida. O impacto aparece no momento de editar o produto, inclusive quando a alteração for apenas visual e o formulário reenviar o campo existente. |
| Risco legado | Configurações já existentes permanecem publicáveis até haver inventário, migração ou outra decisão sobre elas. |
| Operação | Passa a haver casos de suporte para explicar por que um destino anteriormente aceito não é aceito em novas edições. |

Essa direção reduz a criação de novos registros fora da regra, mas não altera, por si, o conjunto que já compõe o volume acima.

### 2. Aplicação imediata de regra sobre dados já persistidos

| Recurso afetado | Efeito para comprador | Efeito para seller e operação |
| --- | --- | --- |
| URL de saída recusada em tempo de execução | O botão Voltar ou a saída do Checkout deixa de levar ao destino configurado; a página tende a permanecer no Checkout ou seguir o comportamento alternativo implementado. | Funis de captura/retorno que dependem desse salto deixam de se comportar como configurados. Há até 991 produtos de homologação a revisar, antes de excluir sobreposições. |
| URL pós-pagamento recusada | Depois de pagar, o comprador pode permanecer na página de sucesso da Lowify, receber um fallback ou uma mensagem de erro, conforme a regra implementada. | Entrega, onboarding, upsell externo e rastreamento que dependam desse destino podem não ocorrer. Há 1.610 produtos de homologação com o campo preenchido. |
| Iframe recusado ou removido | Vídeo, VSL, player ou outro bloco incorporado deixa de ser exibido. A compra ainda pode continuar possível, mas com página visual e conversão diferentes. | O seller precisa substituir o embed, migrar para um provedor aceito ou remover a personalização. Há 120 produtos de homologação com esse tipo de vídeo. |
| Mídia HTTP recusada | Recurso visual ou vídeo que hoje depende de HTTP deixa de carregar. | O seller precisa hospedar em HTTPS ou trocar o recurso. Os campos de redirecionamento têm ao menos 25 registros HTTP no recorte, sem deduplicação entre eles. |

Esse tipo de aplicação troca exposição por compatibilidade: o bloqueio ocorre no momento de compra, e não somente no momento de configuração. A diferença é relevante para uma decisão sobre aviso prévio, exceções temporárias e ordem de migração.

### 3. Aprovação de domínio por seller e revalidação de mudança

Associar um destino a domínio aprovado altera uma função hoje livre em uma função condicionada a evidência de controle do domínio. Os efeitos dependem dos critérios escolhidos — por exemplo, aceitar subdomínios, provedores de hospedagem, encurtadores, links de área de membros ou domínios de parceiros.

| Situação | Impacto |
| --- | --- |
| Primeiro cadastro de destino externo | O seller precisa concluir uma etapa adicional antes de publicar ou alterar o funil. |
| Troca de domínio, subdomínio ou protocolo | A alteração pode ficar indisponível até nova validação, mesmo quando o caminho de campanha muda sem intenção maliciosa. |
| Domínio de terceiro usado legitimamente | O seller pode depender de autorização que não controla diretamente, como área de membros, ferramenta de webinar, agenda, LMS, rastreador ou página hospedada por parceiro. |
| Destino já existente | Sem regra de transição, sua navegação pode ser interrompida; com regra de transição, ele continua sendo uma exceção conhecida até ser revisado. |
| Operação interna | São necessários critérios de aprovação, evidência consultável, expiração/revalidação e atendimento a sellers bloqueados. |

Esse modelo reduz a liberdade de apontar o domínio de pagamento para destinos não vinculados ao seller. Ele não torna o conteúdo do domínio aprovado imutável nem garante uma revisão positiva de um motor de reputação.

### 4. Restrição do iframe e dos embeds

O formato atual aceita HTML com iframe depois de remover `<script>`. Restringir esse formato pode variar de aceitar apenas provedores conhecidos a eliminar HTML livre e guardar somente um identificador de vídeo.

| Forma de restrição | Impacto de compatibilidade |
| --- | --- |
| Exigir HTTPS no `src` | Embeds HTTP deixam de carregar ou de ser salvos. |
| Permitir somente provedores definidos | Players, formulários, calendários, widgets de chat, páginas próprias e provedores não incluídos deixam de aparecer. |
| Limitar atributos do iframe | Alguns provedores podem perder autoplay, fullscreen, permissões de pagamento, acesso a mídia ou outra funcionalidade dependente dos atributos removidos. |
| Bloquear `srcdoc` e HTML arbitrário | Conteúdo montado integralmente no embed deixa de funcionar; isso inclui usos legítimos e usos que fogem ao propósito de vídeo. |
| Aplicar sandbox | O conteúdo incorporado pode perder cookies, popups, navegação externa, formulários ou autenticação, dependendo das permissões mantidas. |

O impacto é visível dentro da página de venda antes do pagamento. Como o editor de prévia omite alguns comportamentos do Checkout público, a prévia isolada não demonstra todos os efeitos de recursos externos, pixels e redirecionamentos.

### 5. Content-Security-Policy e cabeçalhos

| Medida | Efeito técnico | Possível impacto funcional |
| --- | --- | --- |
| CSP em `Report-Only` | O navegador reporta carregamentos que seriam bloqueados, sem bloqueá-los. | Não interrompe recursos por efeito da política, mas introduz necessidade de coleta, retenção e análise dos relatórios. Uma ausência de relatório não prova cobertura de todos os checkouts. |
| CSP efetiva | O navegador bloqueia origens, scripts, frames, imagens, mídia ou conexões fora da política. | Pode afetar reCAPTCHA, antifraude, carteiras, pixels, players, imagens, vídeos e integrações externas que não estiverem previstos. O efeito alcança checkout simples e customizado conforme as diretivas. |
| `X-Content-Type-Options: nosniff` | Impede interpretação flexível de tipo MIME. | Assets servidos com tipo incorreto podem parar de carregar. |
| `Referrer-Policy` restritiva | Reduz informações enviadas na navegação para outro domínio. | Ferramentas de atribuição e análise podem receber menos detalhes de origem. |
| HSTS | Faz navegadores reutilizarem HTTPS para o host durante o período configurado. | Configurações, subdomínios ou caminhos que ainda dependam de HTTP deixam de ser acessíveis pelo navegador afetado. |
| `frame-ancestors`/`X-Frame-Options` | Restringe quem pode incorporar o Checkout. | Pode impedir integrações que coloquem o Checkout em iframe. |

CSP trata o que é carregado dentro da página; ela não valida a titularidade de um domínio de redirecionamento e não muda o conteúdo que o comprador encontrará depois de sair da Lowify.

### 6. Redirecionamento mediado por rota interna

Uma alternativa de arquitetura é o navegador receber uma rota interna da Lowify, e essa rota resolver o destino associado à venda ou ao produto. Em comparação com a URL externa entregue diretamente ao browser, os impactos de mudança são:

| Área | Impacto |
| --- | --- |
| Fluxo pós-pagamento | A rota precisa preservar corretamente pedido, estado de pagamento, destino e fallback. Um erro nessa resolução pode deixar o comprador após uma venda paga sem chegar à entrega externa. |
| Saída e upsell | Cada tipo de navegação exige regra própria; uma regra única aplicada sem distinção pode alterar a volta do navegador, recusa de upsell ou sequência do funil. |
| Rastreamento | UTMs, identificadores de afiliado, parâmetros de campanha e cookies podem mudar de origem ou de sequência. Sellers que medem conversão no destino precisam validar esse efeito. |
| Dados e operação | A plataforma passa a precisar guardar o destino aprovado, o estado de validação e registros de tentativa de redirecionamento. Isso melhora rastreabilidade, mas adiciona estados e pontos de falha. |
| Compatibilidade | Destinos existentes precisam ser migrados ou tratados por exceção; apontar diretamente para uma URL pode deixar de ser o contrato público do Checkout. |

Esse desenho não impede que um destino aprovado mude posteriormente seu próprio conteúdo. Seu alcance é controlar como e para onde o domínio da Lowify inicia a navegação.

## Impacto por público

| Público | Efeitos possíveis |
| --- | --- |
| Comprador | Menos conteúdo de terceiro exibido no domínio de pagamento; em troca, pode encontrar vídeo ausente, fluxo de saída diferente ou não chegar automaticamente a uma entrega externa após pagar se a configuração não for compatível. |
| Seller com checkout simples | Pode não perceber alteração se não usa mídia, embed ou destino externo afetado. Cabeçalhos globais ainda podem atingir recursos comuns, como pixels e antifraude. |
| Seller com checkout personalizado | Pode precisar alterar embed, player, URL de mídia, domínio de destino ou parâmetros de campanha; esse é o grupo com maior chance de mudança perceptível na página ou no funil. |
| Suporte e operações | Passam a lidar com revisão de domínios, contestação de bloqueio, orientação de migração, exceções e acompanhamento de falhas pós-pagamento. |
| Produto e comercial | Precisam equilibrar continuidade de funis existentes, prazo de adaptação, critérios de exceção e a exposição reputacional de manter destinos livres. |

## Superfícies públicas que exigem análise própria

O alerta mencionado envolve o domínio de pagamento, mas o domínio pode ser associado a uma jornada que começa ou termina em outras superfícies públicas. O tratamento abaixo não afirma que qualquer uma delas causou o alerta; ele separa o que está verificável deste código do que ainda depende de fonte e inventário próprios.

| Superfície | Situação observável | Impacto de incluí-la em uma política de conteúdo externo |
| --- | --- | --- |
| Checkout padrão e transparente | Compartilham o contexto de produto e o frontend público; campos de personalização e redirects podem alcançá-los. | Mudanças nos campos compartilhados alcançam ambos quando usados. |
| Upsell/downsell | Pode receber destino interno ou URL externa para próxima etapa, recusa e destino final. | Uma política de destino externo pode alterar a sequência de ofertas após a compra. |
| Gerador de páginas `paginas.lowify.com.br` | Há referência pública a uma página, mas o código e o banco do construtor não estão neste workspace. | Não é possível estimar quantidade de páginas, links ou embeds afetados sem inventário desse produto. A inclusão pode afetar landing pages publicadas por sellers. |
| Área de membros e entrega externa | A entrega pode depender de URL configurada pelo produto ou de serviço fora do Checkout. | Bloqueios pós-pagamento podem aparecer para o comprador como falha de acesso, embora a transação financeira tenha sido concluída. |

## Pontos que delimitam a decisão

As perguntas abaixo delimitam o impacto da escolha; não são instruções de implementação.

1. A regra atingirá apenas novos cadastros, também alterações de produtos existentes, ou também a renderização de registros já persistidos?
2. Quais destinos são parte do negócio aceito: domínio próprio do seller, subdomínios, plataformas de área de membros, provedores de vídeo, encurtadores, páginas de parceiros e ferramentas de rastreamento?
3. Qual é o comportamento aceitável depois de uma venda paga quando o destino externo não estiver apto: página de sucesso interna, exceção temporária, mensagem ao comprador ou outra regra?
4. Haverá prazo de transição e comunicação para sellers já configurados? Os 1.610 produtos com redirecionamento pós-pagamento e os 120 com iframe mostram que o efeito não é pontual em homologação.
5. Qual evidência aprova e revalida o controle de domínio, quem a opera e como exceções são registradas?
6. A política inclui somente Checkout ou também gerador de páginas, área de membros e demais domínios públicos? A resposta altera escopo, volume e equipe envolvida.
7. A implantação de uma CSP será apenas observacional inicialmente ou terá bloqueio efetivo? Quais origens de pagamento, antifraude, mídia e tracking fazem parte do contrato do Checkout?

## Limites da evidência

- A base e os serviços consultados são de homologação. Os números não devem ser usados como contagem de produção nem como estimativa de receita ou de compradores afetados.
- As consultas são somente leitura e não expõem URL, dados de compradores ou conteúdo de sellers neste documento.
- O teste de dados confirma a existência dos campos e a execução das consultas no schema atual. Ele não visita URLs externas, não executa pagamento, não confirma que um comprador seguiu um redirecionamento e não classifica domínio como seguro ou malicioso.
- O código do gerador de páginas referido na conversa não está disponível neste workspace; qualquer conclusão sobre ele exigirá inventário e acesso ao componente correspondente.
- A classificação por antivírus é externa e pode considerar fatores que não aparecem no código ou nos campos aqui descritos. Nenhum impacto listado equivale a prova de causa ou a garantia de reversão da classificação.

## Referências técnicas confirmadas

- `front/dashboard-seller/api/save_checkout_settings.php`
- `front/dashboard-seller/api/product/update_banners.php`
- `front/front-checkout/checkout_support/product.php`
- `front/front-checkout/views/checkout/_components/checkout_exit_redirect.php`
- `front/front-checkout/views/checkout/index.php`
- `front/front-checkout/show_upsell.php`
- `front/front-checkout/api/check_payment_status.php`
- `services/service-commerce-v2/app/Http/Request/UpdateProductRequest.php`
- `services/service-commerce-v2/app/Application/UseCase/Product/GetCheckoutPaymentStatusUseCase.php`
- `security/2026-11-12_CHECKOUT_REPUTATION_REVIEW.md`
