# Feature — migração de contas da fase 1

> Status: ativo
> Última atualização: 2026-11-17
> Confiança: confirmada no código

## Objetivo

Migra uma conta da fase 1 para a fase 2 pelo endpoint administrativo, preservando as regras distintas para PF e PJ e forçando nova verificação de identidade quando a documentação pessoal PF estiver incompleta.

## Fluxo principal

```text
Admin -> POST /admin/users/{user_id}/phase-one-migration -> services-account -> users/documents/user_verification_sessions -> fila de atualização de conclusão
```

Para uma PF, a migração exige `account_phase = 1` e ausência de revisão de conta. Documento pessoal completo é selfie mais CNH, frente e verso da CNH, ou frente e verso do RG, em status pendente ou aprovado. Se estiver incompleto, a migração invalida as sessões Didit persistidas para o usuário, preserva os documentos como histórico, deixa a verificação de identidade pendente e permite uma nova solicitação Didit.

## Componentes e responsabilidades

| Componente | Responsabilidade |
| --- | --- |
| `AdminAccountPhaseMigrationController` | Expõe preview ou aplicação da migração administrativa. |
| `MigratePhaseOneAccountUseCase` | Valida a elegibilidade, altera a fase e decide a reinicialização Didit da PF. |
| `VerificationSessionRepository` | Invalida sessões Didit locais do titular quando é necessária nova submissão. |
| `EnqueueAccountCompletionRefreshUseCase` | Enfileira a atualização da conclusão do cadastro após a migração. |

## Contratos e autorização

`POST /admin/users/{user_id}/phase-one-migration` aplica a mudança; `preview=true` retorna o plano sem persistir. A rota está no grupo administrativo do `services-account`; a autenticação/autorização é responsabilidade do chamador/edge que a expõe.

## Dados e processamento assíncrono

A alteração de `users`, a cópia de documentos de conversão PJ quando aplicável e a invalidação de sessões Didit da PF incompleta ocorrem na transação de migração. A invalidação preenche `invalidated_at` apenas nas sessões locais com provider `didit`; consultas que reutilizam sessão ou detectam documentos Didit ignoram essas sessões, enquanto os documentos vinculados permanecem preservados. Após a transação, a atualização de conclusão é enfileirada.

## Operação e validação

Validar em homologação uma PF fase 1 com selfie/documento incompleto e uma sessão Didit existente: após a migração, a sessão deve ter `invalidated_at` preenchido, os documentos devem continuar registrados e uma nova solicitação deve criar uma sessão nova. Confirmar também que uma PF com documentos completos não tem sua sessão Didit invalidada.

## Referências

- `services-account/app/Application/UseCase/AccountMigration/MigratePhaseOneAccountUseCase.php`
- `services-account/app/Domain/VerificationSession/Repository/VerificationSessionRepository.php`
- `services-account/config/routes.php`
