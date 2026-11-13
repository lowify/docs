# Revisão de reputação do checkout

| Campo | Valor |
| --- | --- |
| Data | 12/11/2026 |
| Escopo | `pay.lowify.com.br`, `front-checkout` e Checkout Styler do `dashboard-seller` |
| Origem | Anexo de relatório de pentest encaminhado pela equipe e inspeção técnica do código/ambiente de homologação. |
| Estado | Diagnóstico inicial; a McAfee foi identificada como motor que bloqueia o domínio. A Avast já recebeu reporte. |

## Objetivo

Avaliar os sinais técnicos que podem contribuir para classificações de spam ou phishing em checkouts da Lowify, priorizando correções sob controle da plataforma e sem alterar conteúdo legítimo já configurado por sellers.

## Limites da evidência

- A McAfee foi identificada como o motor que bloqueia o domínio no caso relatado. A Avast já recebeu reporte; outros motores podem manter classificações independentes e não foram confirmados nesta revisão.
- A URL pública de amostra `https://pay.lowify.com.br/checkout?product_id=5Iykz3` é um checkout simples, sem estilização do Checkout Styler. Ela não continha URL efetivamente carregada por `http://` no HTML inicial analisado. Os namespaces XML de SVG não são requisições de rede.
- Essa verificação não cobre mídia criada dinamicamente, outros produtos, nem conteúdo salvo anteriormente no banco. Portanto, não exclui mixed content em outros checkouts.
- Nenhum achado, isoladamente, comprova a causa de uma classificação reputacional. Os itens abaixo são riscos confirmados no código ou na configuração analisada.

## Achados confirmados

### 1. Raiz web expõe arquivos operacionais

Na homologação, o container do `front-checkout` monta o repositório em `/var/www/html` e o Apache usa esse mesmo caminho como `DocumentRoot`. A verificação pública no host `pay.lowify.com.br` retornou HTTP 200 para:

- `/docker-compose.yml`;
- `/Dockerfile`;
- `/composer.json`.

Arquivos `.env*` e `.git/config` retornaram HTTP 403 na mesma verificação, mas a proteção não alcançava todos os arquivos operacionais presentes na raiz.

Impacto: scanners de segurança podem interpretar exposição de arquivos de projeto como sinal de comprometimento; o conteúdo dos arquivos também amplia a superfície de reconhecimento do ambiente.

Correção iniciada: `front-checkout/docker/apache/front-checkout.conf` recebeu regra de negação para `.git`, `.env*`, Dockerfiles, arquivos Compose, arquivos Composer e extensões operacionais comuns. A correção estrutural continua sendo mover o `DocumentRoot` para uma pasta pública dedicada, após mapear entrypoints e assets.

### 2. O Checkout Styler permite embed arbitrário

O Styler oferece a opção `Código Embed (iFrame/Script)`. Ao salvar, o backend remove tags `<script>`, mas aceita qualquer HTML restante que contenha uma tag `<iframe>`. O `front-checkout` renderiza esse valor como HTML na página pública.

Não há validação confirmada de:

- origem permitida do iframe;
- uso obrigatório de HTTPS;
- atributos de evento no elemento iframe;
- `srcdoc` ou outras formas de conteúdo arbitrário;
- atributos de sandbox ou política de permissões do frame.

Impacto: um produto pode fazer o domínio de pagamento apresentar conteúdo controlado por terceiro. Além do risco de segurança, esse padrão pode associar a reputação do domínio da Lowify a domínios abusivos ou a conteúdo de phishing.

### 3. URLs de imagens e vídeos não são validadas de forma centralizada

A interface normal do Styler apresenta upload para imagens de depoimento, e o modal de banner também apresenta apenas upload. Entretanto, o backend recebe do navegador a lista `checkout_images` e a persiste sem validar cada URL existente na lista. Uma requisição manipulada pode introduzir URL externa ou `http://`.

Para vídeos MP4/MOV, o salvamento aceita qualquer URL válida, incluindo `http://`. Para YouTube e Vimeo, a validação também permite esquema HTTP. A persistência de banners recebe a lista enviada pelo cliente e requer validação server-side equivalente de origem e esquema.

Impacto: recursos HTTP podem gerar mixed content; recursos de domínios externos e não confiáveis podem prejudicar a reputação e disponibilizar conteúdo que a plataforma não controla.

### 4. Redirecionamentos externos são funcionalidade existente

O produto possui URL de saída do checkout e URL de redirecionamento pós-pagamento. Há também URLs de próxima etapa e destino final no fluxo de upsell. O frontend aceita URLs externas para esses fluxos.

Esse comportamento não deve ser removido de forma global: ele é funcionalidade de funil usada por sellers. O risco deve ser tratado com inventário, auditoria e política de domínios, sem bloquear abruptamente checkouts vigentes.

#### Modelo seguro para redirecionamentos legítimos

O checkout não deve receber uma URL de destino diretamente por query string, pelo navegador ou como resposta não validada de uma API. O seller configura o destino uma vez no produto; a plataforma normaliza a URL, exige HTTPS, remove credenciais e fragmentos, e armazena somente uma origem previamente aprovada para aquele seller.

A aprovação deve verificar que o seller controla o domínio, por DNS ou arquivo HTTPS. Após a verificação, a plataforma mantém uma allowlist de domínios por seller e por produto. Alterar a origem, o subdomínio ou o protocolo exige nova verificação. Domínios de encurtador, IP literal, `localhost`, rede privada e esquemas diferentes de HTTPS devem ser recusados.

Depois da confirmação do pagamento, o backend resolve o destino pelo pedido já autenticado e persistido, não por um parâmetro enviado pelo cliente. O frontend recebe apenas um identificador ou uma rota interna, como `/redirect/after-payment/<token-de-uso-unico>`. Essa rota consulta a venda, confirma que ela está paga, registra o evento e redireciona para o destino aprovado. O mesmo padrão pode ser usado para saída do checkout e etapas de upsell.

Isso mantém o redirecionamento transparente para o comprador e preserva o funil do seller, mas remove o padrão de open redirect: nenhuma URL arbitrária fornecida pelo visitante passa a ser destino do domínio de pagamento. A reputação ainda depende do domínio externo aprovado e do conteúdo hospedado nele; não há garantia de que um motor jamais classifique uma página, mas a plataforma deixa de oferecer um redirecionador explorável por terceiros.

### 5. Cabeçalhos de proteção não estavam presentes na resposta analisada

Na resposta pública de amostra não foram encontrados `Content-Security-Policy`, `Strict-Transport-Security`, `X-Frame-Options`, `X-Content-Type-Options` nem `Referrer-Policy`.

Uma CSP restritiva não deve ser aplicada sem levantamento prévio: os checkouts podem usar reCAPTCHA, pixels, players de vídeo e mídia externa legítima.

#### Risco e rollout dos cabeçalhos

A CSP é o cabeçalho com risco direto de interromper recursos do checkout se for aplicada em modo efetivo antes de inventariar as origens utilizadas. Pixels, reCAPTCHA, players, fontes, imagens, vídeos, chamadas de API e conteúdo externo legítimo podem deixar de carregar se não estiverem em uma allowlist apropriada.

O primeiro passo deve ser uma CSP em `Report-Only`, com endpoint de coleta de relatórios. Nesse modo, o navegador registra o que teria sido bloqueado, mas não bloqueia nenhum recurso. Os relatórios devem formar uma amostra representativa de checkouts simples e customizados antes de qualquer imposição.

Após o inventário, a política deve declarar origens por finalidade:

- `script-src`: scripts próprios, pixels e reCAPTCHA aprovados;
- `img-src`: storage/CDN da Lowify, pixels e imagens aprovadas;
- `frame-src`: YouTube, Vimeo e provedores de embed aprovados;
- `media-src`: storage/CDN e mídia aprovada;
- `connect-src`: APIs e integrações necessárias.

`X-Content-Type-Options: nosniff` e `Referrer-Policy: strict-origin-when-cross-origin` são mudanças de baixo risco, embora a primeira possa revelar assets servidos com MIME incorreto e a segunda possa reduzir detalhes enviados a ferramentas de tracking. HSTS deve começar somente em `pay.lowify.com.br`, após confirmar HTTPS consistente; `includeSubDomains` não deve ser aplicado inicialmente.

`X-Frame-Options: DENY` ou `frame-ancestors 'none'` podem quebrar usos legítimos se algum checkout for incorporado por iframe. Da mesma forma, `form-action 'self'` exige confirmar que nenhum formulário de checkout faz POST diretamente para um domínio externo. Esses controles devem entrar após a verificação funcional em homologação e com exceções temporárias, documentadas e com prazo, para integrações legítimas ainda não migradas.

## Levantamento necessário antes do planejamento

Ainda não há base suficiente para definir um plano de remediação fechado. Antes de escolher controles, allowlists, migrações ou prazos, a equipe deve levantar o uso real dos recursos e os registros já existentes. O planejamento será traçado a partir desse inventário, priorizando os achados confirmados e o impacto em checkouts ativos.

| Etapa | Levantamento ou ação preparatória | Impacto esperado em checkouts existentes |
| --- | --- | --- |
| Imediata | Validar a negação de arquivos operacionais expostos. | Sem alteração de conteúdo de seller. |
| Imediata | Inventariar produtos com `video_type=iframe`, URLs HTTP, imagens externas, banners externos e redirecionamentos externos. | Somente leitura. |
| Imediata | Habilitar CSP em modo `Report-Only`, com endpoint de coleta, para levantar domínios usados sem bloquear recursos. | Sem bloqueio de recursos. |
| Após o inventário | Definir quais URLs, domínios, players, pixels e fluxos externos são legítimos, legados ou indevidos. | Nenhum até a aprovação do planejamento. |
| Após o inventário | Traçar plano de remediação, migração de registros legados, testes de compatibilidade e aplicação gradual de controles. | A ser definido com base na evidência. |

## Critérios de aceite

1. Arquivos `.env`, `.git`, Dockerfile, Compose, Composer e backups retornam 403 ou 404 em `pay.lowify.com.br`.
2. Novas imagens e banners só podem ser persistidos a partir do storage autorizado; URLs HTTP ou externas fora da política são rejeitadas pelo servidor.
3. Novos vídeos e iframes só aceitam HTTPS e fontes permitidas; HTML arbitrário não é persistido nem renderizado.
4. Registros existentes fora da nova política foram identificados e possuem plano de migração ou exceção explícita.
5. A CSP em `Report-Only` produz inventário de origens sem erros funcionais em uma amostra representativa de checkouts.
6. A aplicação efetiva da CSP e dos cabeçalhos foi testada em homologação antes de produção.
7. A contestação de reputação é enviada à McAfee somente após a confirmação técnica das correções; o reporte já enviado à Avast deve ser acompanhado com as evidências atualizadas.
