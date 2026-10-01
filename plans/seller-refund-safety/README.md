# Plano: segurança de reembolso por seller

## Contexto

Houve um incidente no qual um seller podia realizar uma compra, sacar o saldo e, depois, solicitar o reembolso. O objetivo desta análise é estabelecer o que precisa estar protegido antes de habilitar novamente o reembolso solicitado pelo seller.

Este documento registra a revisão feita em 2026-10-01. Nenhuma mudança deste plano foi implementada ainda.

## Estado atual confirmado

### Autorização de refund

- O Commerce V2 bloqueia refund com `actor_type=seller`; atualmente somente `admin` e `support` são aceitos.
- O endpoint de refund do seller no Public API é separado do endpoint administrativo:
  - permissões administrativas `1` e `2` seguem como `admin`;
  - permissão `4` segue como `support`;
  - seller usa a rota própria, com validação de propriedade da venda.
- A tela do Dashboard exige PIN financeiro para refund de usuário não privilegiado, mas a rota seller do Public API ainda não consome nem exige o challenge. Enquanto seller estiver bloqueado no Commerce, isso está contido; não será suficiente ao reabilitá-lo.

### Colaboradores

- Os fluxos novo e legado de saque no Dashboard barram explicitamente `$_SESSION['colaborador_id']`.
- A mesma regra deve ser aplicada no Public API: a tela não pode ser a única fronteira de segurança.

### PIN financeiro

- O Account já suporta consumo de challenge vinculado a usuário, expiração, uso único e `context_type` esperado.
- O Public API possui o endpoint de consumo, mas hoje não encaminha `context_type` ao Account.
- O Dashboard envia `context_type`, porém essa informação é descartada no Public API.

Ao habilitar seller, a rota seller de refund deve exigir `finance_password_challenge_id` e consumi-lo com `context_type=refund_sale`. O fluxo de saque deve usar `context_type=withdraw`.

### Saldo disponível

O Wallet calcula disponibilidade a partir de:

```text
saldo total
- saques com status pendente
- disputas bloqueantes pendentes
- sales_refunds com status pending (valor + taxa)
- seller_balance_holds com status held
```

Portanto, tanto `tbl_saques` pendentes quanto `sales_refunds` pendentes já bloqueiam saldo na fórmula atual.

O problema identificado não é a fórmula: no fluxo atual do refund, Commerce verifica disponibilidade, chama o Banking e apenas então cria `sales_refunds` como `pending`. Entre a verificação e a persistência, um saque pode ser criado concorrente e consumir o mesmo saldo.

## Premissas confirmadas

- Pix é reembolsado integralmente; não há cenário de refund parcial no fluxo em discussão.
- O Banking possui unicidade/idempotência e não efetua dois reembolsos bancários para a mesma operação.
- O extrato possui unicidade por usuário, tipo e referência, impedindo lançamento duplicado para a mesma operação.
- A venda sempre possui um único item para este fluxo.
- Testes automatizados não fazem parte deste pacote; a validação será manual quando houver implementação.

## `seller_balance_holds`: avaliação

A tabela existe em produção e é usada ativamente. Sua estrutura relevante é:

```text
UNIQUE (source_type, source_id)
INDEX (owner_user_id, status, expires_at, id)
source_type ENUM('sale_delivery', 'sale_recovery_dispatch')
status ENUM('held', 'consumed', 'released')
```

Hoje ela reserva saldo para `sale_delivery` e `sale_recovery_dispatch`, e seus registros `held` já reduzem a disponibilidade do seller. Há também uma rotina que libera reservas vencidas.

Ela não aceita `sale_refund` nem `withdrawal` sem migration do `ENUM`. Além disso, o consumo atual da reserva é específico para custo de comunicação; não deve ser reutilizado para gerar o débito financeiro de refund.

Conclusão: a tabela é uma possível infraestrutura de reserva, mas migrar apenas refund para ela não resolve a concorrência se os demais criadores de saque continuarem fora do mesmo lock. Não deve ser alterada isoladamente neste momento.

## Direção recomendada

Não é necessário centralizar todo o processamento de saque e refund, nem manter lock durante chamadas ao Banking. É necessário centralizar somente a decisão atômica de reservar saldo.

O alvo é uma operação única no Wallet, executada em transação curta e com lock por seller:

```text
lock seller
-> calcula disponibilidade
-> cria a pendência/reserva de saque ou refund
-> commit e libera lock
```

As chamadas ao Banking ocorrem depois do `commit`.

Há duas opções técnicas viáveis:

1. Manter `tbl_saques` e `sales_refunds` como reservas de domínio e centralizar no Wallet a criação atômica de ambos.
2. Migrar saque e refund para `seller_balance_holds`, adicionando tipos e casos de uso próprios para consumir/liberar cada origem.

A opção preferida é a primeira. Ela preserva as tabelas de domínio que o cálculo de disponibilidade já conhece e limita a centralização à decisão financeira. A opção com `seller_balance_holds` só é adequada se os dois fluxos forem migrados juntos.

## Fluxo alvo de refund

```text
Dashboard
-> Gateway
-> Public API: JWT, bloqueio de colaborador e consumo do PIN refund_sale
-> Commerce: valida venda e valor integral
-> Wallet: reserva atômica do saldo
-> Banking: solicita refund após a reserva
-> Commerce/Wallet: confirma ou libera a pendência conforme resultado/evento
```

Para resultado definitivamente recusado pelo Banking, a reserva deve ser cancelada/liberada. Para timeout ou resultado desconhecido, ela não pode ser liberada automaticamente: é necessário reconciliar com o Banking para não liberar saldo de um refund que tenha sido efetivado externamente.

## Próximo recorte de trabalho

Antes de implementar, mapear todos os caminhos que criam `tbl_saques`, incluindo rotas administrativas, fluxos legados, workers e integrações. Para cada entrada, definir como ela passará pela mesma operação de reserva atômica.

Depois do inventário:

1. Definir o contrato interno do Wallet para reservar/cancelar/confirmar saque e refund.
2. Ajustar todos os criadores de saque para usar esse contrato.
3. Alterar o refund para criar sua pendência antes de chamar o Banking, através do mesmo contrato.
4. Exigir e consumir PIN no Public API com contexto correto; negar colaboradores nessa rota.
5. Manter refund por seller desabilitado até a conclusão dos itens anteriores.

## Fora de escopo desta etapa

- Habilitar refund por seller.
- Alterar o processamento posterior de pagamento de saque.
- Alterar o comportamento de refund administrativo e de suporte.
- Alterar `seller_balance_holds` ou sua migration.
