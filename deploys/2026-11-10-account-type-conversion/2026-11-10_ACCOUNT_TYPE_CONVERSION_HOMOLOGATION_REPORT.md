# Relatório de homologação — conversão administrativa de tipo de conta

## Escopo autorizado

- VPS: `root@217.216.87.77`.
- Participante: somente `services-account` na branch
  `feat/account-type-conversion`.
- Demais targets: mantidos como estão, sem comandos.
- Operação de dados: somente preview; `--apply` é proibido neste teste.
- Amostra: 50 sellers aleatórios com `account_phase` 2 ou 3. Sellers fase 1
  são excluídos.

## Evidências de deploy

| Item | Resultado |
| --- | --- |
| Pré-checagem do repositório | Limpa; branch anterior `feat/account-phase-one-migration`; origin oficial confirmado |
| Branch/commit publicados | `feat/account-type-conversion` / `8c10b3ec9305b2ddbc275b550ae8f10a694fb2e8` |
| Container saudável | Em execução após rebuild incremental |
| Outros targets alterados | Não permitido |

## Resultado da amostra

| Métrica | Resultado |
| --- | --- |
| Sellers selecionados | 50 |
| Fase 1 selecionados | 0 |
| Fase 2 selecionados | 50 |
| Fase 3 selecionados | 0; a amostra aleatória não sorteou os 7 sellers disponíveis nessa fase |
| Prévias PF → PJ | 40 aprovadas |
| Prévias PJ → PF | 10 aprovadas |
| Prévia adicional PJ → PF com sócio de mesmo CPF | Aprovada para seller `814`, fase 2; `source_partner_found: true` |
| Erros de documento já associado | 0 |
| Escritas por `--apply` | 0 |
| Filas/Redis manipulados | 0 |

Cada prévia aprovada retornou `preview: true` e `applied: false`. A seleção e
os resultados foram registrados somente com ID, fase, direção e status; CPF,
CNPJ, e-mails e conteúdo cadastral não foram incluídos neste relatório.

## Critério de aprovação

O teste será aprovado quando as 50 prévias forem concluídas, todas para fases 2
ou 3, com `preview: true` e `applied: false`. O relatório final registrará
apenas IDs, fases, direção da prévia e resultado; não registrará CPF, CNPJ,
documentos, tokens ou conteúdo de dados cadastrais.

## Resultado final

Aprovado para a prévia administrativa no escopo permitido (fases 2 e 3): 50 de
50 prévias da amostra aleatória foram concluídas com sucesso, todas na fase 2.
A amostra não sorteou nenhuma das 7 contas disponíveis na fase 3; esse recorte
fica pendente para uma próxima execução direcionada. A regra adicional de puxar
dados de sócio da própria PJ foi confirmada em uma prévia direcionada. Não houve
aplicação de conversão nem alteração nos demais repositórios da VPS.
