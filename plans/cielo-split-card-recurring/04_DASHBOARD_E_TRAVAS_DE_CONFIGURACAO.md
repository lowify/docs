# Dashboard e travas de configuração

## Decisão de liberação

A recorrência Cielo não é habilitada globalmente nem inferida de a conta já ter cartão. A autorização é por seller, na tabela compartilhada `user_system_vars`:

| Chave | Valores | Efeito |
| --- | --- | --- |
| `cielo_split_card_recurring_enabled` | `1` | Seller pode configurar cartão em produto `SUBSCRIPTION`, desde que os demais requisitos sejam verdadeiros. |
| `cielo_split_card_recurring_enabled` | `0` | Negação explícita; não mostra nem aceita cartão recorrente. |
| sem linha | `null`; estado padrão | Não configurado e negado. A ação administrativa remove a linha para voltar a este estado. |

Não usar `getCustomVar()` para esta chave: ele consulta `system_vars` quando não encontra override do usuário. Para esta feature, ausência não pode herdar valor global.

## Onde a administração aparece

Existem duas interfaces administrativas para a mesma ação e ambas devem permanecer equivalentes:

1. A ação **Editar restrições** da lista de sellers (`admin_usuarios.php`), cujo modal é renderizado em `views/dashboard/admin/users/_components/modal_restrictions.php`.
2. O modal **Restrições operacionais** da visão geral do seller (`admin_seller_overview.php`), em `views/dashboard/admin/seller_overview/_components/restrictions_modal.php`.

As duas submetem para `actions/admin/user/restrictions.php`. A página de lista precisa receber o estado atual junto com seus dados assíncronos; a visão geral pode carregá-lo diretamente para o seller exibido.

O controle precisa ser um seletor explícito de três opções — **Não configurado**, **Liberado** e **Bloqueado** — e não um checkbox. Um checkbox não permite distinguir uma negação deliberada da ausência de configuração.

## Responsabilidades por componente

### Dashboard Seller

- Autorizar a edição com a permission key já aplicada a restrições de sellers, `admin_sellers_restrictions_edit`.
- Validar o valor recebido como `null`, `0` ou `1`; nunca aceitar uma chave/valor arbitrário do POST.
- Para `null`, apagar somente a linha do seller e dessa chave. Para `0`/`1`, atualizar a última linha existente ou inserir uma nova, preservando o padrão já usado por outras `user_system_vars`.
- Na edição de produto, resolver a chave diretamente pelo `id_usuario` dono do produto. Isso é obrigatório quando um administrador edita produto alheio; a identidade da sessão não é a do seller.
- Exibir o card de cartão em assinatura somente quando a chave for `1` **e** o form-data do Commerce V2 disser que o cartão Cielo está disponível.
- Fixar `credit_card_installments=1` em assinatura: esconder seletor, aviso e modal de regras de parcelamento; o campo enviado deve ser hidden com valor `1`.
- Manter a tela de `ONE_TIME` intacta, incluindo seleção e regras existentes de parcelas.

### Commerce V2

O serviço já persiste produtos em `tbl_produtos` e já contém `App\\Model\\UserSystemVar`, usado para `card_mdr`. A nova trava deve consultar a chave diretamente, ordenando por `id` decrescente e tratando ausência como falso.

- `GetProductFormDataUseCase` deve devolver separadamente a elegibilidade de cartão recorrente para o Dashboard, sem expor detalhes de credencial.
- `ValidateProductPaymentMethodsUseCase` deve rejeitar persistência de `SUBSCRIPTION` com `credit_card_enabled=1` se a chave não for `1`, o gateway não for `cielo_ecommerce`, a integração não estiver elegível ou `credit_card_installments !== 1`.
- `CreateProductUseCase`, `UpdateProductUseCase` e a validação de ofertas já chamam esse caso de uso; a regra deve ficar nele, não duplicada em controller.
- `ResolveCheckoutPaymentMethodsUseCase` deve continuar retornando só `pix_automatic` para assinatura sem elegibilidade e retornar `card` apenas na combinação permitida, sempre com máximo de `1` parcela.
- `ProcessProductCheckoutRequest` deve aceitar `card` para `SUBSCRIPTION` somente após consultar a mesma regra de elegibilidade, e rejeitar tentativa de `installments > 1`.
- `GetProductByShortCodeUseCase` e a resposta pública de opções de checkout precisam anunciar `card` somente quando o produto for elegível. Não basta aceitar o POST, pois o checkout precisa saber quais meios renderizar.
- `ProcessProductCheckoutUseCase` deve escolher a criação de recorrência Cielo para assinatura/cartão; não pode cair no atual `createCardPayment`, que representa cobrança avulsa.

### Banking V2, Edge Webhook e Commerce V2 assíncrono

Esses componentes implementam a cobrança recorrente real, conforme os documentos 01–03: criação de série, `RecurrentPaymentId`, webhook `ChangeType: 2`, consulta por `PaymentId`, Split pós-transacional, fila exclusiva e consumo idempotente. A flag do seller controla disponibilidade; não substitui as confirmações do provedor nem a validação financeira.

## Matriz de decisão no produto

| Produto | Chave do seller | Cielo/integração | Interface | Persistência/checkout |
| --- | --- | --- | --- | --- |
| `ONE_TIME` | qualquer | elegível | Cartão e parcelas atuais | comportamento atual |
| `SUBSCRIPTION` | `null` ou `0` | qualquer | cartão não disponível | rejeitar cartão |
| `SUBSCRIPTION` | `1` | não elegível ou gateway diferente | cartão não disponível | rejeitar cartão |
| `SUBSCRIPTION` | `1` | Cielo elegível | toggle de cartão; sem parcelas; `1x` fixo | aceitar somente cartão recorrente Cielo em `1x` |

## Segurança e compatibilidade

- O browser não é fronteira de autorização. Requests adulterados para ativar cartão ou enviar mais parcelas devem falhar no Commerce V2.
- Não retornar PAN, CVV, token, segredo ou estado sensível de Cielo no form-data, logs ou eventos.
- A chave não autoriza `ONE_TIME` novo, Pagar.me, Checkout Transparente nem outros provedores.
- Ao desligar ou remover a chave, bloquear novas adesões; não cancelar automaticamente séries existentes. Cancelamento é uma operação explícita por `RecurrentPaymentId`.
