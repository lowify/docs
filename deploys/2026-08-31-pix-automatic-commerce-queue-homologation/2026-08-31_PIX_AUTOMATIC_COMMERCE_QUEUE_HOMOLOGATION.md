# Teste interno de homologação — PIX Automático para Commerce

## Objetivo

Validar em homologação que uma cobrança PIX Automático paga, recebida pelo Banking v1, é publicada para o Commerce v1 e cria a parcela, aprova a venda e executa o fluxo financeiro correspondente.

O teste usa somente dados sintéticos ligados ao comprador `pradodolucas3@gmail.com`. Nenhum identificador de webhook, pagamento, seller ou venda reais pode ser utilizado.

## Componentes e referências

| Chave do mapa | Branch | Commit inicial |
|---|---|---|
| `services-banking` | `main` | `a329536` |
| `services-commerce` | `main` | branch remota `main` |

Componentes explicitamente fora da operação: `edge-webhook`, `dashboard-seller`, `services-commerce-v2` e todos os demais repositórios do mapa de homologação.

## Pré-checagem

1. Em ambos os repositórios da VPS, confirmar árvore limpa, branch atual e URL de `origin`.
2. Confirmar a existência das branches remotas `origin/main` antes de trocar ou atualizar qualquer branch.
3. Após a atualização, confirmar que os containers dos dois componentes estão em execução e sem reinicialização contínua.

## Sequência de atualização

1. `services-banking`: atualizar `main` com `git pull --ff-only origin main` e executar `docker compose up --build -d`.
2. `services-commerce`: atualizar `main` com `git pull --ff-only origin main` e executar `docker compose up --build -d`.

Os caminhos e comandos efetivamente usados devem ser resolvidos pelo mapa oficial de homologação.

## Teste de compatibilidade em homologação

### Dados e pré-condições

- Comprador exclusivo: `pradodolucas3@gmail.com`.
- Criar uma venda/assinatura PIX Automático de teste com identificadores sintéticos e marcadores `internal-homolog-pix-automatic`.
- Não usar seller, produto, cobrança, E2E, correlação ou dados pessoais de produção.
- Registrar os IDs criados para limpeza posterior.

### Caso

1. Criar a venda e a assinatura de teste pelo fluxo suportado pela aplicação.
2. Publicar na fila de entrada do Banking uma mensagem sintética equivalente a `PIX_AUTOMATIC_COBR_COMPLETED`, com E2E e `identifier_id` exclusivos.
3. Confirmar no Banking: cobrança `paid` e registro `ordinary_logs` de `commerce_enqueue` seguido de `commerce_enqueued`.
4. Confirmar no Commerce: parcela criada, venda aprovada e efeito financeiro esperado para a venda de teste.
5. Confirmar que não existe `commerce_enqueue_error` para os identificadores do teste.

### Critério de aprovação

O teste passa somente se a mensagem sintética puder ser rastreada no Banking, a parcela for criada no Commerce e a venda de teste for aprovada sem erro persistido de publicação.

### Limpeza

Remover ou reverter exclusivamente os registros sintéticos anotados no início do teste, incluindo a venda, assinatura, parcela, cobrança, logs de auditoria e mensagens de fila ainda pendentes. Não remover dados que não tenham o marcador do teste.

## Rollback

Se a atualização falhar, interromper a operação e não fazer rollback automático. Registrar o componente e o comando que falhou para decisão manual.
