# Reputação do Login Lowify

## Contexto

A tela de autenticação está classificada como phishing por múltiplos motores de segurança. A contestação foi aceita e o bloqueio voltou — porque o gatilho nunca foi removido.

| Motor | Veredito sobre `dashboard.lowify.com.br/login` |
| --- | --- |
| Avast | URL:Phishing |
| Bitdefender | Bloqueado |
| BrightCloud | Phishing and Other Frauds |
| Google Safe Browsing | Sem contestação |
| Microsoft SmartScreen | Sem contestação |

## Por que o bloqueio reincide

A contestação de falso positivo foi aceita, o veredito foi limpo, e o bloqueio voltou. Isso não significa que a contestação falhou — significa que **o sinal que dispara a heurística continua no ar**.

Reenviar contestação sem remover o gatilho reinicia o mesmo ciclo, e cada reincidência torna a contestação seguinte mais difícil: o histórico do domínio passa a pesar contra. A ordem que funciona é **remover os gatilhos → validar → só então contestar**, citando as correções na própria contestação.

## São dois problemas, não um

O aviso do navegador e a classificação de phishing têm causas diferentes e exigem tratamentos diferentes. Tratá-los como um só é parte do motivo de o caso não fechar.

### Problema A — técnico: mixed content

“Invasores conseguem ver as imagens que você está olhando e modificá-las.” É um defeito reproduzível e corrigível no código: a página carrega sub-recursos por HTTP.

### Problema B — reputação: classificação de phishing

É um veredito heurístico dos motores de reputação. É consequência, não causa — e o problema técnico é um dos sinais que o alimentam.

Uma página de entrada de credenciais que carrega recursos por HTTP é um dos sinais clássicos de phishing nas heurísticas de reputação. Corrigir o mixed content é pré-requisito para resolver a classificação.

## Remediação

As duas primeiras medidas são defeitos confirmados e corrigíveis imediatamente.

### P0 — Eliminar o mixed content

Localizar recursos servidos por HTTP no código e, sobretudo, nos dados — o caso mais comum é imagem cadastrada por seller com URL `http://`, que não aparece numa busca apenas no código.

```bash
grep -rEn "http://" --include=*.php --include=*.js --include=*.css \
  views/ includes/ assets/ api/ | grep -vE "http://www\\.w3\\.org"
```

```sql
SELECT id_produto, imagem FROM tbl_produtos WHERE imagem LIKE 'http://%';
```

Como rede de segurança para dados legados, aplicar:

```text
Content-Security-Policy: upgrade-insecure-requests
```

Isso não substitui a limpeza dos dados. Critério de aceite: console sem aviso de mixed content em `/login`, numa aba anônima e sem extensões.

### P0 — Fechar arquivos sensíveis na raiz web

O `dashboard-seller` monta o repositório inteiro em `/var/www/html`. Todo arquivo do repositório é candidato a ser servido — e foi confirmado que existe `.env.bak` dentro do diretório servido. Motores de reputação varrem exatamente esses caminhos e podem pontuar o site como comprometido.

```bash
for f in .env .env.bak .env.old .env~ .git/config docker-compose.yml; do
  printf '%-20s %s\n' "$f" \
    "$(curl -sS -o /dev/null -w '%{http_code}' https://dashboard.lowify.com.br/$f)"
done
```

Qualquer resposta diferente de `403` ou `404` é achado crítico. A correção estrutural é servir somente `public/`, em vez da raiz do repositório. Como paliativo:

```nginx
location ~ /\. { deny all; return 404; }
location ~* \.(bak|old|save|swp|orig|sql|log|env)$ { deny all; return 404; }
```

### P0 — Registrar no Google Search Console

As contestações cobriram Avast e BrightCloud. Não há contestação no Google Safe Browsing, que alimenta Chrome, Android, Firefox e Safari. Sem domínio verificado no Search Console não há visibilidade do motivo da classificação nem canal formal de revisão.

### P1 — Remover open redirect e parâmetros refletidos

Um redirecionador aberto em domínio legítimo é um sinal de alto peso numa página de login. Localizar usos de destino fornecido pelo cliente:

```bash
grep -rEn "header\(\s*['\"]Location:" --include=*.php . \
  | grep -Ei '\$_(GET|POST|REQUEST|SERVER)'
```

Aceitar somente caminho relativo, nunca destino vindo diretamente do cliente:

```php
$dest = (string) ($_GET['redirect'] ?? '/dashboard');
if (!preg_match('#^/(?!/|\\\\)[A-Za-z0-9/_\\-.?=&%]*$#', $dest)) {
    $dest = '/dashboard';
}
```

O mesmo vale para texto livre de URL renderizado na tela (`?msg=`, `?erro=`): usar códigos fixos mapeados no servidor.

### P1 — Aplicar cabeçalhos de segurança

Aplicar no Traefik ou nginx do container, não somente no PHP, para cobrir respostas de erro e arquivos estáticos:

```text
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
Content-Security-Policy: default-src 'self'; form-action 'self';
  frame-ancestors 'none'; base-uri 'self'; upgrade-insecure-requests
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
```

`form-action 'self'` impede que script injetado altere o destino do POST de login. `frame-ancestors 'none'` impede que a tela legítima seja embutida em página de phishing.

### P2 — Separar conteúdo de usuário do domínio de autenticação

Se upload de seller — imagem de produto, ebook, anexo ou avatar — for servido por `dashboard.lowify.com.br`, um único arquivo abusivo pode contaminar a reputação de todo o domínio, incluindo o login. Isso é a explicação mais provável para a reincidência.

A migração de ebooks para R2 já iniciou esse caminho. Concluí-la para todos os tipos de arquivo, em domínio separado e sem relação de cookie com o principal. Recusar no upload extensões marcáveis (`.html`, `.svg`, `.xhtml`) validando o conteúdo, não só a extensão.

Enquanto upload e autenticação dividirem domínio, nenhuma contestação será definitiva.

### P2 — Caçar clones que imitam a marca

Clones hospedados em outros domínios podem referenciar assets originais ou redirecionar para o login real, agrupando o domínio legítimo ao cluster de phishing do motor de reputação.

```text
https://crt.sh/?q=%25lowify%25
urlscan.io → page.domain:lowify | busca por hash do favicon
```

Abrir takedown com registrador e host de cada clone e citar os takedowns na contestação. Bloquear hotlink de assets por `Referer` reduz o vínculo técnico usado para agrupamento.

### P3 — Monitorar antes do usuário

Adicionar verificação diária com Google Safe Browsing Lookup API, rescan semanal no VirusTotal, alertas do Search Console em caixa monitorada e vigilância de CT logs para domínios parecidos.

O runbook deve determinar: quando o bloqueio reaparecer, investigar o gatilho antes de contestar.

## Cobertura das contestações

| Motor | Canal | Situação |
| --- | --- | --- |
| Google Safe Browsing | Search Console → Segurança e ações manuais | Pendente |
| Microsoft SmartScreen | `feedback.smartscreen.microsoft.com` | Pendente |
| Bitdefender | `bitdefender.com/consumer/support` | Pendente |
| Avast / AVG | `avast.com/report-false-positive` | Enviada |
| BrightCloud / Webroot | `support.threatintel.opentext.com` | Enviada |

A próxima contestação deve ser factual sobre o que mudou — correções com datas, migração do conteúdo de usuário e clones derrubados — e não argumentativa sobre legitimidade. Só deve ser enviada após validação técnica.

## Verificação

- [ ] `/login` sem aviso de mixed content em aba anônima.
- [ ] Nenhuma URL `http://` renderizada, no código e no banco de dados.
- [ ] `upgrade-insecure-requests` ativo.
- [ ] `.env`, `.env.bak`, `.env.old` e `.git/` retornam 403 ou 404.
- [ ] Raiz web aponta para `public/`, não para a raiz do repositório.
- [ ] Nenhum parâmetro de redirecionamento aceita destino externo.
- [ ] Nenhum texto livre da URL é refletido na tela de login.
- [ ] CSP com `form-action 'self'` e `frame-ancestors 'none'`.
- [ ] HSTS, `nosniff`, `X-Frame-Options` e `Referrer-Policy` presentes.
- [ ] Conteúdo de usuário servido por domínio separado.
- [ ] Upload recusa `.html`, `.svg` e executáveis, validando por conteúdo.
- [ ] Busca por clones executada em crt.sh e urlscan.io; takedowns abertos.
- [ ] Domínio verificado no Google Search Console.
- [ ] Contestações enviadas aos cinco motores, descrevendo as correções.
- [ ] Rescan no VirusTotal registrado como evidência.
- [ ] Monitoramento automatizado em operação.

O gatilho ativo ainda não foi confirmado empiricamente. É necessário executar as verificações de mixed content, open redirect e arquivos expostos no host de produção. As recomendações cobrem o conjunto de sinais que pode produzir a classificação observada.
