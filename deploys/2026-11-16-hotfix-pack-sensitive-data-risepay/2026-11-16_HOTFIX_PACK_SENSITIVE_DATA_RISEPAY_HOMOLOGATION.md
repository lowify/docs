# Integração em homologação — pacote de hotfixes: privacidade, Vendas, WhatsApp e RisePay

**Data da integração:** 16/11/2026  
**Resultado técnico:** concluído

## Escopo executado

Foram atualizados somente os três participantes abaixo. Nenhum outro repositório, container de infraestrutura, banco, Redis, fila, Worker ou Edge recebeu comando nesta integração.

| Repositório | Caminho em homologação | Branch | Commit final | Ação executada |
| --- | --- | --- | --- | --- |
| `dashboard-seller` | `/root/opt/lowify/front/dashboard-seller` | `fix/hotfix-pack-2026-11-16` | `e862bb48` | `git switch` e `git pull --ff-only`; sem build ou restart |
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

## Validação ainda necessária na interface

1. No Dashboard, ativar o ícone de olho e confirmar a ocultação de valores, clientes, pedidos, produtos e progresso; os gráficos devem preservar quantidades e mostrar estrelas nos nomes dos produtos.
2. Em Vendas, testar o filtro Cartão e uma URL antiga com `gateway=cartao`.
3. Em uma venda Pagar.me de teste elegível, abrir e submeter o modal de estorno conforme o fluxo de teste reversível aprovado.
4. Em Configurações do sistema > WhatsApp Meta, salvar um template de recuperação e confirmar a persistência após recarregar a página.
5. Em Checkout Transparente, confirmar que RisePay não aparece em Nova integração e que os demais gateways permanecem disponíveis.

## Referências

- [Guia de deploy do pacote](2026-11-16_HOTFIX_PACK_SENSITIVE_DATA_RISEPAY_DEPLOY.md)
