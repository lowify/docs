# Resultado — homologação da migração de contas fase 1 para fase 2

## Escopo executado

VPS de homologação: `root@217.216.87.77`.

Foram alterados exclusivamente os participantes abaixo para a branch
`feat/account-phase-one-migration`:

| Repositório | Commit publicado |
| --- | --- |
| `services-account` | `96f393764478e983c5fda87d4f446de49c0136e6` |
| `edge-public-api` | `293bc896266f2c5eb535bec606e1f687b15c17c7` |
| `edge-gateway` | `2c12e2336e59f55f7fbac2607a08182ef3fe2258` |
| `dashboard-seller` | `a3f2327d228cc0a985ba1fa3896edf0f6bccc7fc` |

Todos os demais repositórios da VPS foram mantidos como estavam, sem comandos
Git ou Docker.

## Rebuilds

- `services-account`: imagem reconstruída e container iniciado.
- `edge-public-api`: imagem reconstruída e container iniciado.
- `edge-gateway`: API e worker reconstruídos e iniciados.
- `dashboard-seller`: branch atualizada apenas via Git. O rebuild foi
  interrompido antes de recriar containers, por orientação explícita; os
  containers anteriores permaneceram ativos.

Durante o rebuild do Account, havia dois containers sem execução, um `Dead` e
outro criado pela primeira tentativa. Eles foram removidos sem volumes antes
de iniciar novamente o serviço. Banco, Redis e filas não foram apagados nem
alterados manualmente.

## Lotes executados

O comando foi executado dentro do container do Account:

```bash
php bin/hyperf.php account-phase:migrate-phase-one --user-ids=<lote-de-10> --apply
```

Foram selecionados aleatoriamente 50 sellers que estavam na fase 1 no momento
da seleção. Resultado consolidado após a execução:

| Estado final | Quantidade |
| --- | ---: |
| Fase 2 | 50 |
| PF com `pj_migrate=127` | 38 |
| PJ-CPF com `pj_migrate=10` | 12 |
| Permaneceram na fase 1 | 0 |

## Validações realizadas

1. O comando foi invocado em modo de prévia contra um usuário fora da fase 1 e
   retornou `account_not_in_phase_one`, sem gravar dados.
2. O primeiro lote de 10 foi aplicado e conferido diretamente no banco:
   todos ficaram na fase 2; PF recebeu marcador `127`, PJ-CPF recebeu `10` e
   `account_review_status` permaneceu nulo.
3. Houve pelo menos um PJ-CPF com documentos completos: sócio criado com KYC
   aprovado e documentos pessoais copiados para o contexto do sócio.
4. Houve PFs e PJ-CPFs com documentos incompletos: o fluxo registrou estado
   pendente para reenvio/revisão conforme a regra do Account.
5. Reexecutar lotes já concluídos retornou `account_not_in_phase_one` para os
   respectivos IDs, confirmando proteção contra promoção duplicada.
6. A consulta consolidada final confirmou 50/50 IDs na fase 2.

## Testes adicionais após os lotes

### Auditoria dos PJ-CPF migrados

Foi feita uma auditoria individual dos 12 sellers PJ-CPF gerados pelos lotes.
Todos possuíam exatamente um sócio ativo. Nos casos com documentos pessoais
enviados antes da migração, a quantidade de documentos válidos no sócio ficou
igual à quantidade registrada no usuário original:

| Seller | Documentos no usuário | Documentos no sócio | KYC do sócio |
| --- | ---: | ---: | --- |
| 760 | 2 | 2 | `approved` |
| 1833 | 2 | 2 | `approved` |
| 2512 | 3 | 3 | `approved` |
| 2686 | 2 | 2 | `approved` |
| 3048 | 3 | 3 | `approved` |

Os sete demais PJ-CPF não tinham documentos pessoais válidos enviados no
usuário de origem. Eles receberam sócio ativo com KYC `pending`, que é o
estado esperado para solicitar envio/reenvio de documentos.

### Teste manual pelo Dashboard

Foi selecionado o seller PF `1417`, que ainda estava na fase 1, e a migração
foi acionada manualmente pela interface administrativa.

Resultado conferido diretamente no Account:

- `account_phase=2` e `pj_migrate=127`;
- documentos completos: selfie e RG frente/verso aprovados;
- revisão de conta criada com status `pending`;
- evento `complete_register` processado com status `success`;
- diagnóstico de completude: cadastro estruturalmente completo, aguardando
  somente a aprovação da identidade/revisão.

Esse teste confirmou o caminho de migração manual, o enfileiramento de
completude e a criação posterior da revisão. Reexecutar o comando nos IDs já
migrados retornou `account_not_in_phase_one`, confirmando que o comando não
repete a promoção nem cria sócios duplicados.

## Pendências de validação manual

Como o `dashboard-seller` não foi reconstruído nesta operação, ainda é
necessário validar a interface após o procedimento operacional normal desse
componente: prévia administrativa, botão “Migrar para fase 2”, acesso do
seller a “Completar cadastro”, bloqueio de saque até revisão aprovada e
checkout do Commerce V2 preservado.

## Referência

- Documento de deploy: `deploys/2026-11-05-account-phase-one-migration/2026-11-05_ACCOUNT_PHASE_ONE_MIGRATION_DEPLOY.md`.
