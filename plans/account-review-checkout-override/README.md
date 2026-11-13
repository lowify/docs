# Plano — override de checkout durante revisão após conversão de conta

> Status: planejado
> Última atualização: 2026-11-13

## Objetivo

Permitir que um seller que já havia sido aprovado continue apto a receber vendas quando converter o tipo de conta entre PF e PJ, sem mascarar a nova revisão cadastral exigida pela conversão.

A conversão deve abrir uma nova revisão e manter conta, saque e integrações dependentes de cadastro como pendentes. Somente a elegibilidade de checkout poderá permanecer ativa por uma autorização explícita e temporária.

## Problema confirmado

`ConvertAccountTypeUseCase` aceita contas nas fases 2 e 3 e, nas duas direções de conversão, limpa `tbl_usuarios.account_review_status` para `NULL`.

Para uma conta na fase 3 (full), isso gera um estado sem fluxo de recuperação automática:

```text
account_phase = 3
account_review_status = NULL
```

O consumer de refresh e o handler de `complete_register` promovem `NULL` para `pending` apenas quando a conta está na fase 2. Já o Commerce V2 considera uma conta de fase 3 elegível ao checkout somente se `account_review_status = approved`.

Assim, uma conversão de uma conta previamente aprovada pode deixar o seller sem review nova e sem checkout disponível. O caso do seller investigado mostrou documentos/KYC do sócio aprovados, completion elegível e eventos `complete_register` bem-sucedidos, mas `account_review_status = NULL`.

## Resultado esperado

Ao converter uma conta:

```text
antes
  phase=2 ou 3
  review=approved (ou outro estado)

depois
  review=pending
  nova review criada quando o cadastro estiver elegível
  saque/cadastro/integrações continuam sujeitos à aprovação real
  checkout permanece ativo somente se a conta era aprovada antes da conversão
```

Para a última regra, será introduzido o booleano:

```text
tbl_usuarios.checkout_review_approved_override
```

Valor `1` significa: para a decisão de elegibilidade de checkout, tratar a conta como aprovada apesar do `account_review_status` real estar em revisão. O campo não altera nem substitui o status real de review.

## Regra de negócio proposta

### Conversão PF ↔ PJ

1. Capturar se a conta estava aprovada imediatamente antes da conversão:

   ```text
   was_review_approved = account_review_status == approved
   ```

2. Executar a cópia/limpeza de dados já existente.
3. Gravar `account_review_status = pending`; nunca gravar `NULL` neste fluxo.
4. Gravar `checkout_review_approved_override = 1` somente quando `was_review_approved` for verdadeiro; caso contrário, gravar `0`.
5. Preservar o refresh de completion já enfileirado. Ele cria ou reutiliza a nova `user_review` quando a conta estiver elegível ou tiver somente pendências revisáveis.

### Elegibilidade de checkout

Para contas fora da fase 3, manter a regra atual. Para fase 3, o seller será elegível quando:

```text
account_review_status = approved
OR checkout_review_approved_override = 1
```

O override vale apenas no domínio de checkout. Ele não deve ser interpretado como aprovação cadastral por outras regras.

### Estados finais da nova revisão

- `approved`: limpar o override (`0`), pois a aprovação real passa a sustentar a elegibilidade.
- `rejected`: limpar o override (`0`), bloqueando checkout conforme a regra atual.
- `resubmission_requested`: requer decisão de produto antes da implementação. Há duas políticas possíveis:
  - limpar o override e bloquear checkout até novo envio/aprovação; ou
  - manter o override enquanto a pendência for somente de reenvio, preservando checkout até uma reprovação definitiva.

A decisão deve ser explícita: o significado do override é manter checkout durante a análise iniciada pela conversão, não conceder uma aprovação cadastral geral.

## Escopo técnico

| Componente | Alteração prevista |
| --- | --- |
| `services-account` | Migration para a nova coluna; model/serialização; conversão PF↔PJ passa a iniciar review em `pending`; finalização de review limpa o override nos estados definidos. |
| `services-commerce-v2` | `SellerEligibilityService` aceita a nova condição exclusivamente ao resolver checkout padrão e transparente. |
| `edge-public-api` | Confirmar que o payload interno de seller repassa o novo campo para o Commerce V2 quando necessário. |
| `dashboard-seller` | Exibir a condição de forma administrativa e garantir que conversão use o novo contrato. Não oferecer edição manual genérica do override sem regra operacional aprovada. |

Não fazem parte do override:

- `withdrawal_active` e autorização de saque;
- cache de profile completion;
- validação de conta bancária e integração de cartão;
- `identity_verification_status`, KYC de sócio ou documentos;
- o status real em `user_reviews` e `tbl_usuarios.account_review_status`.

## Dados e migração

Criar migration nova em `services-account` para adicionar:

```sql
checkout_review_approved_override TINYINT(1) NOT NULL DEFAULT 0
```

Requisitos da migration:

- não alterar migrations existentes;
- default `0`, sem efeito retroativo para sellers atuais;
- rollback remove apenas a coluna, conforme o padrão suportado pelo repositório;
- atualizar `App\Model\User` com cast booleano e `fillable` caso aplicável;
- expor o campo somente aos consumidores internos que precisam decidir elegibilidade.

O rollout não deve executar backfill para sellers já existentes sem uma regra aprovada. O valor padrão preserva o comportamento atual.

## Fluxo alvo

```text
Admin solicita conversão PF ↔ PJ
  -> services-account valida fase 2/3 e documento de destino
  -> transaction copia/remove dados do tipo anterior
  -> account_review_status = pending
  -> override = 1 somente se review anterior era approved
  -> refresh accounts:complete:refresh
  -> consumer avalia completion e cria/reutiliza user_review

Checkout padrão/transparente
  -> Commerce V2 consulta seller
  -> fase 3: approved OR override=1
  -> demais requisitos atuais: seller ativo, cash-in e flags de checkout

Saque, cadastro e cartão
  -> continuam lendo o review real pending/resubmission/rejected
  -> não usam o override
```

## Implementação proposta

1. Adicionar migration e mapear o novo atributo no Account.
2. Alterar `ConvertAccountTypeUseCase` para derivar `was_review_approved` antes da mutação e persistir `pending` + valor correto de override em ambas as direções.
3. Confirmar que `ProfileCompletionRefreshQueueProcess` e `AccountCompleteRegisterHandler` criam a review para o novo estado `pending`, sem depender de `NULL`.
4. Ajustar `FinalizeAccountReviewUseCase` para limpar o override em aprovação e rejeição; aplicar a política decidida para resubmissão.
5. Propagar o atributo pelo contrato interno Account → Commerce V2.
6. Ajustar `SellerEligibilityService::isApprovedForCheckout()` para considerar o override apenas quando `account_phase = 3`.
7. Revisar qualquer filtro SQL que replique a regra de elegibilidade, especialmente `applyToQuery()`, para usar a mesma condição.
8. Atualizar o Dashboard para mostrar que o checkout está em continuidade excepcional durante uma review, sem apresentar a conta como aprovada.

## Testes de aceite

1. PF aprovada → PJ: após conversão, `review=pending`, `override=1`, review nova é criada quando elegível e checkout padrão/transparente continua disponível.
2. PJ aprovada → PF: mesma regra do cenário anterior.
3. PF/PJ não aprovada → conversão: `review=pending`, `override=0`, checkout segue indisponível até aprovação real.
4. Conta convertida com dados incompletos: saque, conta bancária e integração de cartão permanecem bloqueados; checkout só fica disponível no caso de override ativo.
5. Aprovação da nova review: `review=approved`, `override=0`, checkout continua disponível pela aprovação real.
6. Reprovação da nova review: `review=rejected`, `override=0`, checkout fica indisponível.
7. Resubmissão: validar a política de produto escolhida para o override e o comportamento correspondente de checkout.
8. Requisições concorrentes de refresh não criam mais de uma review ativa.
9. Sellers existentes sem conversão conservam comportamento idêntico, pois o novo campo inicia em `0`.

## Riscos e decisões pendentes

- Definir se `resubmission_requested` preserva ou remove o override.
- Validar todos os pontos de elegibilidade de checkout para não haver divergência entre checkout padrão, transparente, criação de produto e integrações de cartão.
- Confirmar a semântica de `cash_in_active`: o override não deve contornar bloqueios explícitos de cash-in ou seller inativo.
- Definir visibilidade/auditoria administrativa do override antes de expor qualquer ação manual para ativá-lo.

## Referências confirmadas

- `services-account/app/Application/UseCase/AccountMigration/ConvertAccountTypeUseCase.php`
- `services-account/app/Process/ProfileCompletionRefreshQueueProcess.php`
- `services-account/app/Domain/Account/AccountCompleteRegisterHandler.php`
- `services-account/app/Application/UseCase/AccountReview/FinalizeAccountReviewUseCase.php`
- `services-account/app/Model/User.php`
- `services-commerce-v2/app/Domain/Seller/Services/SellerEligibilityService.php`
- `services-commerce-v2/app/Application/Service/CheckoutSellerEligibilityService.php`
