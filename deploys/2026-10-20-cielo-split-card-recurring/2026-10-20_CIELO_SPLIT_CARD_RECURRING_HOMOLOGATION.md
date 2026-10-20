# Homologação — Cielo cartão recorrente

## Identificação

- Feature: `feat/cielo-split-card-recurring`
- Ambiente: VPS de homologação
- Modo de rebuild: incremental

## Participantes

| Target | Branch |
| --- | --- |
| `dashboard-seller` | `feat/cielo-split-card-recurring` |
| `services-commerce-v2` | `feat/cielo-split-card-recurring` |

## Targets mantidos como estão

Todos os demais targets operáveis do mapa oficial de homologação devem ser mantidos como estão. Eles não recebem pré-checagem, alteração de branch, `pull` ou Docker nesta operação. Os targets de infraestrutura protegidos pelo mapa também permanecem inalterados.

## Sequência

1. Confirmar que os dois participantes estão limpos e com `origin` correto.
2. Buscar e validar as branches remotas declaradas.
3. Atualizar cada participante com `git pull --ff-only origin feat/cielo-split-card-recurring`.
4. Executar `docker compose up --build -d` apenas no participante cuja branch ou revisão tiver mudado.

## Verificação

Após os builds, confirmar que os containers dos dois participantes estão em execução. O teste funcional da criação de recorrência Cielo não faz parte desta publicação; ele depende de credenciais, seller e fluxo de teste homologados.
