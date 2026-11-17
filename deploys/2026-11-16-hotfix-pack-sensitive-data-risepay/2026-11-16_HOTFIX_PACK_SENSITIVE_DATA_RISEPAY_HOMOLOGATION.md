# Integração em homologação — pacote de hotfixes: privacidade, Vendas, WhatsApp e RisePay

**Data da integração:** 16/11/2026  
**Resultado técnico:** concluído

## Escopo executado

Foram atualizados somente os três participantes abaixo. Nenhum outro repositório, container de infraestrutura, banco, Redis, fila, Worker ou Edge recebeu comando nesta integração.

| Repositório | Caminho em homologação | Branch | Commit final | Ação executada |
| --- | --- | --- | --- | --- |
| `dashboard-seller` | `/root/opt/lowify/front/dashboard-seller` | `fix/hotfix-pack-2026-11-16` | `6d4e5b3d` | `git switch` e `git pull --ff-only`; sem build ou restart |
| `services-notifications` | `/root/opt/lowify/services/services-notifications` | `fix/hotfix-pack-2026-11-16` | `0dabab3` | `git switch`, `git pull --ff-only`, rebuild e recreate do serviço |
| `services-checkout-transparent-api` | `/root/opt/lowify-ct/services-checkout-transparent-api` | `fix/hotfix-pack-2026-11-16` | `3fdd9eb` | `git switch`, `git pull --ff-only`, rebuild/recreate somente do `app` e desativação versionada da RisePay |

O host de homologação utilizado foi `root@217.216.87.77`. Os caminhos acima são específicos de homologação e não alteram o guia de deploy do pacote.

## Pré-checagens executadas

Em cada participante foram confirmados, antes de qualquer troca de branch:

1. repositório sem alterações locais;
2. branch atual e `origin` oficiais;
3. existência remota de `fix/hotfix-pack-2026-11-16` após `git fetch origin --prune`.

As três pré-checagens foram aprovadas.

## Ações e resultados

### Dashboard Seller

- A branch anterior era `fix/pagarme-refund-modal-identifier` no commit `863f908f`.
- O repositório foi atualizado para `fix/hotfix-pack-2026-11-16` no commit `e862bb48`.
- Não houve build, restart ou recriação de container, conforme a regra do Dashboard Seller.
- Os containers existentes permaneceram ativos após a atualização.

### Sincronização posterior do Dashboard Seller

- Após um rebase autorizado da branch do pacote, a homologação permaneceu na ponta anterior `e862bb48` e não podia avançar com `git pull --ff-only`.
- Com a confirmação de que o repositório estava limpo e autorização explícita, ele foi sincronizado com `origin/fix/hotfix-pack-2026-11-16` para o commit `91ab0ed5`.
- Não houve build, restart ou recriação de container; todos os containers do Dashboard Seller continuaram ativos.

### Correção posterior em Vendas

- Em 17/11/2026, o Dashboard Seller recebeu o commit `6d4e5b3d` (`fix(sales): complete sensitive data masking on load`) por `git pull --ff-only`.
- A correção encerra o shimmer inicial de Vendas após a aplicação das máscaras, evitando que os dados ocultos permaneçam exibidos como barras.
- Não houve build, restart ou recriação de container.

### Notifications

- A branch anterior era `fix/quick-fixes-2026-11-09` no commit `0dabab3`.
- O repositório foi atualizado para a branch do pacote no mesmo commit funcional `0dabab3`.
- O serviço foi reconstruído e recriado.
- O container `services-notifications` ficou ativo e os logs confirmaram inicialização do servidor HTTP e dos processos de WhatsApp Meta, e-mail, push e notificações internas, sem erro de inicialização observado.

### CT API

- A branch anterior era `fix/quick-fixes-2026-11-09` no commit `bbcf1b1`.
- O repositório foi atualizado para a branch baseada em `main`, `fix/hotfix-pack-2026-11-16`, no commit `3fdd9eb`.
- Somente o serviço `app` foi reconstruído e recriado; ele ficou ativo e passou a escutar na porta interna `9501`.
- Foi executado o comando versionado:

```bash
docker compose exec -T app php bin/hyperf.php integration-gateways:disable-risepay
```

- Resultado observado: havia uma integração RisePay ativa registrada; o gateway já estava inativo e a execução confirmou `inactive -> inactive`. Registros históricos de integrações e cobranças foram preservados.

## Validações concluídas

1. Dashboard e Vendas: o ícone de olho ocultou os dados esperados; em Vendas, a máscara final foi confirmada após a correção `6d4e5b3d`.
2. Filtro Cartão: validado em uma conta com 173 vendas de cartão.
3. WhatsApp Meta: o salvamento e a persistência dos templates de recuperação foram validados.
4. Dashboard Seller: RisePay não é mais exibida em Nova integração.
5. CT API: a execução idempotente de `integration-gateways:disable-risepay` confirmou `inactive -> inactive`, preservando uma integração histórica ativa.

## Referências

- [Guia de deploy do pacote](2026-11-16_HOTFIX_PACK_SENSITIVE_DATA_RISEPAY_DEPLOY.md)
