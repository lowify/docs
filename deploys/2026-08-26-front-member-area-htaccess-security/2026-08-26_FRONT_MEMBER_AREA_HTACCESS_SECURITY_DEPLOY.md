# Deploy — proteção de arquivos sensíveis no front-member-area

## Objetivo

Bloquear o acesso público a arquivos sensíveis, arquivos iniciados por ponto e diretórios internos do `front-member-area`.

A medida corrige a exposição direta de `/.env`. As URLs sem extensão continuam sendo resolvidas para seus respectivos arquivos PHP, enquanto acessos externos diretos a URLs com `.php` são normalizados para URLs sem extensão em requisições `GET`.

## Componente alterado

| Componente | Branch | Commit |
|---|---|---|
| `front-member-area` | `main` | `260d7b7` |

Não há migration, alteração de schema ou nova variável de ambiente.

## Diretório de produção

```text
/opt/lowify/front/front-member-area/
```

## Alterações incluídas

- O `.htaccess` bloqueia acesso direto a arquivos iniciados por ponto, inclusive `/.env`.
- Diretórios internos (`vendor`, `docker`, `includes`, `config`, `scripts`, `tools`, `tests`, `storage` e `logs`) retornam acesso proibido quando requisitados externamente.
- Arquivos de projeto e configuração, como `composer.json`, `Dockerfile`, arquivos Compose, PHPStan e `phinx.php`, também são bloqueados.
- As regras existentes de URL sem extensão e de redirecionamento de requisições `GET` com `.php` foram preservadas.

O conteúdo atualizado do `.htaccess` é obtido diretamente da branch `main` do repositório; este documento não replica o arquivo.

## Pré-requisitos

1. Confirmar que o clone de produção não possui alterações locais que possam impedir a atualização da branch `main`.
2. Confirmar que `mod_rewrite` está habilitado no Apache:

   ```bash
   docker compose exec -T front-members-area apachectl -M | grep rewrite_module
   ```

## Ações concluídas

1. Os segredos que poderiam ter sido expostos antes da correção foram rotacionados. O bloqueio de acesso não invalida credenciais já divulgadas, portanto esta rotação fez parte da resposta ao incidente.
2. As regras descritas neste documento foram publicadas na branch `main` do repositório `front-member-area` no commit `260d7b7`. A reconstrução do container e a validação em produção continuam pendentes.

## Sequência de deploy

1. No diretório de produção, atualizar o código publicado na `main`:

   ```bash
   cd /opt/lowify/front/front-member-area
   git status --short
   git switch main
   git pull --ff-only origin main
   git log -1 --oneline
   ```

   O último commit deve ser `260d7b7 fix: protect member area sensitive files`.

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
