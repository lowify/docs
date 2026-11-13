# Validação de homologação — override de checkout durante revisão

Data: 2026-11-13  
Ambiente: VPS de homologação  
Escopo publicado: `services-account` em `4e30375` e `services-commerce-v2` em `1588873`.

## Infraestrutura e schema

- A coluna `tbl_usuarios.checkout_review_approved_override` foi criada e conferida como `TINYINT(1) NOT NULL DEFAULT 0`.
- Os containers de Account e Commerce V2 foram reconstruídos e ficaram em execução.
- Por solicitação explícita durante a operação, os outros repositórios da VPS foram mantidos como estavam.

## Contas de teste

Foram usadas exclusivamente contas sintéticas de homologação. Nomes, e-mails e documentos não são registrados neste documento.

| Caso | Conta sintética | Preparação | Fluxo executado |
| --- | ---: | --- | --- |
| Documentos aprovados | `900011` | Fixture técnica reversível com selfie e CNH aprovadas em sessão local de homologação. | PF → PJ → PF |
| Sem documentos | `900026` | Sem documentos pessoais cadastrados. | PF → PJ → PF |

Ambas começaram como PF, fase 3, review aprovada e override desativado. O tipo de conta foi restaurado a PF ao final de cada round-trip.

## Resultados

| Caso | Review final | Override final | Estado de identidade | Documentos pessoais finais | Checkout pelo Commerce V2 |
| --- | --- | ---: | --- | --- | --- |
| Documentos aprovados (`900011`) | `pending` | `1` | `VERIFIED` | selfie e CNH aprovadas preservadas | elegível |
| Sem documentos (`900026`) | `pending` | `1` | `not_sent` | nenhum | elegível |

Os dois casos confirmam que a conversão não deixa a review como `NULL`; ela passa a `pending`. Para a conta com documentação completa, o KYC/IDV foi preservado. Para a conta sem documentação, o fluxo voltou a exigir IDV, sem impedir a continuidade de checkout garantida pelo override.

## Defeito encontrado e correção

Na primeira execução do round-trip com documentos aprovados, a ida PF → PJ gravou override `1`, mas a volta PJ → PF o reduziu para `0` porque a review intermediária já estava `pending`.

Isso violava a regra de negócio de que o override só é removido após aprovação real da nova review. A correção em `services-account` (`4e30375`) preserva o override já ativo em conversões posteriores. O round-trip foi repetido após o deploy da correção e terminou com override `1`, conforme a tabela acima.

## Limites da validação

- A elegibilidade foi exercitada pelo `CheckoutSellerEligibilityService` publicado, que consulta o Account real e retornou elegível para ambos os casos.
- Não foram criadas vendas, saques, contas bancárias, integrações de cartão ou alterações de fila manualmente.
- As contas de teste permanecem em review `pending`, como resultado esperado da conversão; nenhuma review foi aprovada, reprovada ou colocada em reenvio apenas para teste.
