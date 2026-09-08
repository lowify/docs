# Deploy — validação de domínio Gmail no checkout

## Objetivo

Impedir a criação de checkout com domínios Gmail concatenados após `gmail.com`, como `cliente@gmail.com.br`, `cliente@gmail.com.br.zezinho`, `cliente@gmail.com.bua` e `cliente@gmail.com.piada`.

O endereço com o domínio exato `cliente@gmail.com` permanece aceito. A regra é aplicada no navegador e na API para que chamadas diretas também sejam recusadas.

## Componentes alterados

| Componente | Branch de deploy | Commit |
| --- | --- | --- |
| `front-checkout` | `fix/reject-extended-gmail-domains` | `b33507a` |
| `services-commerce-v2` | `fix/reject-extended-gmail-domains` | `a558357` |

Não há migration, alteração de schema, nova variável de ambiente ou alteração de credenciais.

## Pré-requisitos

1. Confirmar que os dois clones de produção não possuem alterações locais.
2. Confirmar que a branch `fix/reject-extended-gmail-domains` está disponível nos dois repositórios.
3. Publicar primeiro `services-commerce-v2`; o front deve ser atualizado somente após a API estar saudável.

## Sequência de deploy

1. Atualizar e recriar o `services-commerce-v2`:

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git status --porcelain=v1
   git fetch origin --prune
   git switch fix/reject-extended-gmail-domains
   git pull --ff-only origin fix/reject-extended-gmail-domains
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   ```

   O commit exibido deve ser `a558357`.

2. Validar a sintaxe PHP dentro do container do Commerce:

   ```bash
   docker compose exec -T service-commerce-v2 php -l app/Http/Request/ProcessProductCheckoutRequest.php
   ```

3. Atualizar e recriar o `front-checkout`:

   ```bash
   cd /opt/lowify/front/front-checkout
   git status --porcelain=v1
   git fetch origin --prune
   git switch fix/reject-extended-gmail-domains
   git pull --ff-only origin fix/reject-extended-gmail-domains
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   ```

   O commit exibido deve ser `b33507a`.

## Validação pós-deploy

1. Abrir um checkout de teste e informar um nome, telefone e os demais dados obrigatórios.
2. Informar `cliente@gmail.com.br` no campo de e-mail e tentar avançar.

   Resultado esperado: o checkout apresenta erro de e-mail inválido e não permite prosseguir.

3. Repetir com `cliente@gmail.com.br.zezinho`, `cliente@gmail.com.bua` e `cliente@gmail.com.piada`.

   Resultado esperado: todos são recusados.

4. Informar `cliente@gmail.com` e concluir uma tentativa de pagamento de teste autorizada para o ambiente.

   Resultado esperado: a validação de e-mail é aprovada e o fluxo segue normalmente.

5. Como validação complementar da API, enviar uma requisição de checkout de teste com `cliente@gmail.com.br`.

   Resultado esperado: a API responde com erro de validação do campo `email`; não deve criar cliente, venda ou cobrança.

6. Verificar os logs de ambos os containers caso haja resposta inesperada:

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   docker compose logs --tail=200 service-commerce-v2

   cd /opt/lowify/front/front-checkout
   docker compose logs --tail=200 front-checkout
   ```

## Rollback

1. Em cada componente, retornar à revisão anterior conhecida e aprovada da branch de origem e recriar o container.
2. Não alterar banco de dados, filas ou credenciais: esta entrega não cria dados persistentes.
3. Repetir a validação do checkout com um endereço `@gmail.com` após o rollback.

> O rollback remove somente a rejeição específica dos sufixos após `gmail.com`.
