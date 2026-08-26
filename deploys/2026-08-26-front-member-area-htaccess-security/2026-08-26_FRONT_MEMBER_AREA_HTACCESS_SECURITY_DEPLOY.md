# Deploy — proteção de arquivos sensíveis no front-member-area

## Objetivo

Bloquear o acesso público a arquivos sensíveis, arquivos iniciados por ponto e diretórios internos do `front-member-area`.

A medida corrige a exposição direta de `/.env`. As URLs sem extensão continuam sendo resolvidas para seus respectivos arquivos PHP, enquanto acessos externos diretos a URLs com `.php` são normalizados para URLs sem extensão em requisições `GET`.

## Componente alterado

| Componente | Arquivo |
|---|---|
| `front-member-area` | `.htaccess` |

Não há migration, alteração de schema ou nova variável de ambiente.

## Diretório de produção

```text
/opt/lowify/front/front-member-area/
```

## .htaccess final

```apache
RewriteEngine On
DirectoryIndex index.php

# Block sensitive project files and private directories from direct access.

RewriteRule (^|/)\. - [F,L]
RewriteRule ^(vendor|docker|includes|config|scripts|tools|tests|storage|logs)(/|$) - [F,L]
RewriteRule ^(composer\.(json|lock)|Dockerfile|docker-compose\..*\.ya?ml|README\.md|phpstan\.neon.*|phinx\.php)$ - [F,L]

RewriteCond %{REQUEST_METHOD} !POST
RewriteCond %{THE_REQUEST} \s/+(.+?)\.php(?:[?\s]|$) [NC]
RewriteCond %{HTTP:X-Forwarded-Proto} =https [OR]
RewriteCond %{HTTPS} =on
RewriteRule ^(.+?)\.php$ https://%{HTTP_HOST}/$1 [R=301,L]

RewriteCond %{REQUEST_METHOD} !POST
RewriteCond %{THE_REQUEST} \s/+(.+?)\.php(?:[?\s]|$) [NC]
RewriteRule ^(.+?)\.php$ /$1 [R=301,L]

RewriteCond %{REQUEST_FILENAME}.php -f
RewriteRule ^(.+?)/?$ $1.php [L]

RewriteCond %{REQUEST_FILENAME} -f [OR]
RewriteCond %{REQUEST_FILENAME} -d
RewriteRule ^ - [L]
```

## Pré-requisitos

1. Fazer backup do `.htaccess` atual:

   ```bash
   cp --backup=numbered .htaccess .htaccess.before-security
   ```

2. Confirmar que `mod_rewrite` está habilitado no Apache:

   ```bash
   docker compose exec -T front-members-area apachectl -M | grep rewrite_module
   ```

## Ações concluídas

1. Os segredos que poderiam ter sido expostos antes da correção foram rotacionados. O bloqueio de acesso não invalida credenciais já divulgadas, portanto esta rotação fez parte da resposta ao incidente.

## Sequência de deploy

1. Atualizar o `.htaccess` com as regras de bloqueio para:

   - arquivos iniciados por ponto, usando `(^|/)\.`;
   - diretórios `vendor`, `docker`, `includes`, `config`, `scripts`, `tools`, `tests`, `storage` e `logs`;
   - arquivos de projeto como `composer.json`, `composer.lock`, `Dockerfile`, arquivos Compose, `README.md`, arquivos PHPStan e `phinx.php`.

   > O ponto da regra de dotfiles deve ser escapado (`\.`). Um ponto sem escape é curinga e bloquearia URLs válidas.

2. Reconstruir e recriar o container:

   ```bash
   docker compose up -d --build
   ```

3. Validar a configuração do Apache:

   ```bash
   docker compose exec -T front-members-area apachectl -t
   ```

## Validação pós-deploy

Após o deploy, abra os links abaixo em uma janela anônima do navegador. Não é necessário inspecionar código, terminal ou logs.

1. Abra [Área de Membros](https://members.lowify.com.br/).

   Resultado esperado: a tela de login da Área de Membros é exibida, ou você é redirecionado para ela. O site não deve mostrar uma página de erro.

2. Abra [teste de proteção do arquivo de configuração](https://members.lowify.com.br/.env).

   Resultado esperado: uma página de **acesso proibido** ou **erro 403**. Não pode aparecer texto com configurações, senhas, chaves, tokens ou nomes de banco de dados.

3. Faça login com uma conta de teste e abra um produto/aula que essa conta possa acessar.

   Resultado esperado: a página do conteúdo abre normalmente e, se houver vídeo, ele carrega.

4. Se qualquer resultado for diferente do esperado, pare o deploy e informe ao time técnico a mensagem de erro retornada no terminal.

> Sucesso do deploy: a Área de Membros abre normalmente, o login funciona e o link `/.env` não exibe nenhuma configuração.

## Rollback

1. Restaurar a cópia numerada anterior do `.htaccess`.
2. Recriar o container:

   ```bash
   docker compose up -d --build
   ```

3. Revalidar a home e os fluxos críticos.

> O rollback restaura o comportamento anterior, mas não remove a necessidade de rotacionar os segredos expostos.
