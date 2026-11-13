# Revisão de reputação do checkout

| Campo | Valor |
| --- | --- |
| Data | 12/11/2026 |
| Escopo | `pay.lowify.com.br`, `front-checkout` e Checkout Styler do `dashboard-seller` |
| Origem | Anexo de relatório de pentest encaminhado pela equipe e inspeção técnica do código/ambiente de homologação. |
| Estado | Diagnóstico inicial; não representa confirmação de classificação por um fornecedor específico. |

## Objetivo

Avaliar os sinais técnicos que podem contribuir para classificações de spam ou phishing em checkouts da Lowify, priorizando correções sob controle da plataforma e sem alterar conteúdo legítimo já configurado por sellers.

## Limites da evidência

- O relato de bloqueio em máquinas específicas não identificou ainda o motor responsável. Avast, SmartScreen, Google Safe Browsing e Bitdefender podem manter classificações independentes.
- A URL pública de amostra `https://pay.lowify.com.br/checkout?product_id=5Iykz3` não continha URL efetivamente carregada por `http://` no HTML inicial analisado. Os namespaces XML de SVG não são requisições de rede.
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

### 5. Cabeçalhos de proteção não estavam presentes na resposta analisada

Na resposta pública de amostra não foram encontrados `Content-Security-Policy`, `Strict-Transport-Security`, `X-Frame-Options`, `X-Content-Type-Options` nem `Referrer-Policy`.

Uma CSP restritiva não deve ser aplicada sem levantamento prévio: os checkouts podem usar reCAPTCHA, pixels, players de vídeo e mídia externa legítima.

## Plano de remediação gradual

| Prioridade | Ação | Preserva checkouts existentes? |
| --- | --- | --- |
| P0 | Publicar e validar a negação de arquivos operacionais expostos. | Sim. |
| P0 | Inventariar produtos com `video_type=iframe`, URLs HTTP, imagens externas, banners externos e redirecionamentos externos. | Sim; somente leitura. |
| P0 | Validar no backend de salvamento: imagens e banners devem ser caminhos internos ou URLs HTTPS emitidas pelo storage/CDN da Lowify; vídeos devem usar HTTPS. | Sim para fluxo normal de upload; requer tratamento dos registros legados fora da política. |
| P0 | Substituir HTML bruto de embed por renderer controlado: extrair `src`, exigir HTTPS, limitar origens e gerar iframe com atributos permitidos. | Requer migração ou exceção temporária para embeds legados. |
| P1 | Habilitar CSP em modo `Report-Only`, com endpoint de coleta, para levantar domínios usados sem bloquear recursos. | Sim. |
| P1 | Criar política gradual de allowlist para `frame-src`, `img-src`, `media-src` e destinos de redirecionamento. | Sim durante a fase somente de relatório. |
| P1 | Aplicar cabeçalhos efetivos após a análise dos relatórios e testes de checkout. | Depende da allowlist consolidada. |
| P2 | Migrar o `DocumentRoot` para `public/`. | Requer teste de rotas, assets e entrypoints. |
| P2 | Solicitar revisão aos fornecedores de reputação que efetivamente classificam o domínio, citando correções verificadas. | Sim. |

## Critérios de aceite

1. Arquivos `.env`, `.git`, Dockerfile, Compose, Composer e backups retornam 403 ou 404 em `pay.lowify.com.br`.
2. Novas imagens e banners só podem ser persistidos a partir do storage autorizado; URLs HTTP ou externas fora da política são rejeitadas pelo servidor.
3. Novos vídeos e iframes só aceitam HTTPS e fontes permitidas; HTML arbitrário não é persistido nem renderizado.
4. Registros existentes fora da nova política foram identificados e possuem plano de migração ou exceção explícita.
5. A CSP em `Report-Only` produz inventário de origens sem erros funcionais em uma amostra representativa de checkouts.
6. A aplicação efetiva da CSP e dos cabeçalhos foi testada em homologação antes de produção.
7. A contestação de reputação é enviada somente após a confirmação técnica das correções e a identificação do motor que bloqueia cada caso.
