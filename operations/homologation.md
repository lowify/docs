# Operação de homologação na VPS

## Objetivo

Este procedimento sincroniza a VPS de homologação `root@217.216.87.77` para testar uma feature sem alterar produção. A fonte de caminhos é o mapa ativo em `.agents/integration/homologation-map.yaml`.

## Pedido mínimo

Um pedido deve indicar:

- identificador ou branch da feature;
- targets participantes e sua branch;
- targets que devem ser **mantidos como estão**, quando houver;
- modo de rebuild, se diferente do padrão incremental.

Exemplo:

```text
Homologar feat/checkout-email-direct-access.
Participantes: services-commerce-v2, dashboard-seller, front-checkout e front-member-area.
Manter como estão: ct-webhook.
Modo: incremental.
```

Os participantes usam a branch declarada. Todo target oficial operável que não participar nem estiver declarado como “manter como está” usa `main`. Os itens ausentes da VPS, os repositórios não mapeados e os targets marcados no mapa com `default_action: hold` continuam fora da operação.

## Regras de execução

1. Antes de alterar qualquer target, verificar somente os targets que receberão comandos: estado Git, branch atual e remoto `origin`.
2. Um target declarado como “manter como está”, ou marcado no mapa com `default_action: hold`, não recebe pré-checagem, `fetch`, troca de branch, `pull` nem Docker. Mudanças locais e branch são preservadas e não bloqueiam os demais.
3. Para cada target operado, executar `git fetch origin --prune`, validar a branch remota, fazer `git switch <branch>` e `git pull --ff-only origin <branch>`.
4. No modo **incremental** (padrão), executar `docker compose up --build -d` somente quando a branch ou o commit mudar. Portanto, voltar uma feature para `main` sempre exige rebuild; um target já no commit desejado não exige rebuild.
5. No modo **completo**, solicitado explicitamente, executar `docker compose up --build -d` para todos os targets operados, mesmo se já estiverem no commit desejado.
6. Se houver mudanças pendentes em um target que receberia comandos e ele não tiver instrução explícita para ser mantido, parar e pedir orientação. Nunca descartar, fazer stash, limpar ou resetar sem autorização.
7. Em falha de atualização ou build, parar e informar o componente, a etapa, o resultado e quais componentes já foram processados. Não fazer rollback automático.

## Infraestrutura protegida

Infraestrutura, banco e Redis não devem receber comandos sem solicitação explícita. No mapa atual, `checkout-transparent-infra` protege a infraestrutura, banco e Redis do checkout transparente, e `data_layer` protege o banco e Redis compartilhados. Esses targets ficam em `default_action: hold`.

## Convivência na VPS compartilhada

- Prefira o modo incremental para reduzir consumo de CPU, memória e indisponibilidade de SSH.
- Use “manter como está” quando outro desenvolvedor estiver usando um target.
- Use rebuild completo somente para correção de ambiente ou quando uma reconstrução integral for necessária.
- Execute builds sequencialmente; não inicie builds concorrentes sem uma decisão explícita.

## Resumo dos agentes configurados

| Fluxo | Responsabilidade |
| --- | --- |
| Arquitetura | Camadas, repositórios, JWT, dados e filas. |
| Conhecimento | Mapas de feature e sugestões pendentes. |
| Backend | Serviços, APIs, edge, dados, filas e integrações. |
| Frontend | Convenções e regras por frontend. |
| Testes de compatibilidade | Validação integrada na homologação. |
| Integração — homologação | Sincronização segura da VPS. |
| Preparação de deploy | Documento operacional em `docs/deploys/`. |
| Deploy — produção | Preparo local de branches; não faz deploy. |
