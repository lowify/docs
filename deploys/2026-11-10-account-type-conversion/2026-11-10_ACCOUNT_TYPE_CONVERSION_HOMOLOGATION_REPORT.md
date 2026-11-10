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
| Pré-checagem do repositório | Pendente de execução |
| Branch/commit publicados | Pendente de execução |
| Container saudável | Pendente de execução |
| Outros targets alterados | Não permitido |

## Resultado da amostra

| Métrica | Resultado |
| --- | --- |
| Sellers selecionados | Pendente de execução |
| Fase 1 selecionados | Deve ser 0 |
| Prévias PF → PJ | Pendente de execução |
| Prévias PJ → PF | Pendente de execução |
| Prévia com sócio de mesmo CPF | Pendente de execução |
| Erros de documento já associado | Pendente de execução |
| Escritas por `--apply` | Deve ser 0 |
| Filas/Redis manipulados | Deve ser 0 |

## Critério de aprovação

O teste será aprovado quando as 50 prévias forem concluídas, todas para fases 2
ou 3, com `preview: true` e `applied: false`. O relatório final registrará
apenas IDs, fases, direção da prévia e resultado; não registrará CPF, CNPJ,
documentos, tokens ou conteúdo de dados cadastrais.

## Resultado final

Pendente de execução na VPS de homologação.
