# Homologação — Acesso isolado de QA para afiliados

## Objetivo

Liberar temporariamente as telas de afiliados no Dashboard Seller para a massa isolada de QA identificada por e-mail `qa-affiliate-20261002-*@example.test`.

Esta operação existe somente para viabilizar a rodada de QA do programa de afiliados em homologação. Não habilita contas reais, não altera regra de comissão e não publica em produção.

## Participante

| Chave do mapa | Repositório | Branch |
| --- | --- | --- |
| `dashboard-seller` | `dashboard-seller` | `chore/qa-affiliate-access-homologation` |

Todos os demais targets operáveis da VPS são **mantidos como estão** por escopo explícito desta operação. `data_layer` e `checkout-transparent-infra` continuam protegidos por sua regra de `hold`.

## Alteração incluída

Além dos IDs já existentes no allowlist, o Dashboard permite a sessão de afiliados somente quando todos os critérios abaixo forem verdadeiros:

1. conta ativa;
2. permissão de seller (`3`);
3. e-mail iniciado por `qa-affiliate-20261002-`;
4. domínio exato `@example.test`.

## Banco, filas e infraestrutura

Não há migration, alteração de banco, Redis, fila, segredo ou rebuild de infraestrutura. A criação da massa de usuários é uma operação posterior, feita com dados exclusivos de homologação.

## Procedimento

1. Pré-checar exclusivamente `/root/opt/lowify/front/dashboard-seller`: árvore Git limpa, branch atual e `origin` esperado.
2. Fazer `git fetch origin --prune` e confirmar a branch remota declarada.
3. Trocar para a branch e atualizar com `git pull --ff-only`.
4. Registrar commit antes/depois. Como o Dashboard usa código montado, não fazer build ou restart nesta entrega.
5. Criar as contas de teste e autenticar uma conta elegível e uma inelegível.

## Validação

- Seller ativo com e-mail `qa-affiliate-20261002-...@example.test` acessa as páginas de afiliados.
- Conta com mesmo domínio, mas prefixo diferente, não recebe acesso.
- Conta de teste com permissão diferente de seller não recebe acesso.
- Nenhuma conta fora do padrão recebe acesso em decorrência desta mudança.

## Rollback

Após a rodada de QA, retornar somente o Dashboard Seller para `main` usando a referência aprovada, `git pull --ff-only origin main`. Não é necessário ajuste de banco, fila, Redis ou dados de venda. As contas de teste devem ser desativadas ou removidas em operação separada e rastreável.
