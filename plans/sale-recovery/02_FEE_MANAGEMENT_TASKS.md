# Fase 2 — Gestão da taxa de recuperação de venda

## Regra de taxa

Há uma única taxa fixa por recuperação, igual para e-mail e WhatsApp.

```text
Chave: sale_recovery_unit_price
```

A resolução do valor efetivo é:

```text
user_system_vars[user_id, sale_recovery_unit_price]
  → quando existir, é o override do usuário
  → quando não existir, usar system_vars[sale_recovery_unit_price]
```

O usuário é quem será responsável pela recuperação: produtor em venda própria e
afiliado em venda afiliada. A taxa deve ser exibida como informação na gestão
do produto, mas não pode ser alterada por produtor ou afiliado.

Somente administradores de permissão **1 ou 2** podem alterar o valor padrão e
criar, atualizar ou remover um override.

## Reaproveitamento existente

| Elemento | Reuso |
| --- | --- |
| `system_vars` | Armazena a taxa padrão global. |
| `user_system_vars` | Armazena o override por usuário. |
| `getCustomVar($pdo, $userId, $key)` em `dashboard-seller/includes/helpers.php` | Já resolve override do usuário com fallback para o valor padrão. |
| `SystemVarsModel` / `SystemVarsService` | Leitura e escrita da variável global. |
| Tela de overview administrativo do seller e modal de taxas | Base visual para exibir e editar o override do seller. |
| `actions/admin/user/fees.php` | Referência de autorização e ação administrativa; não deve gravar a nova taxa em `tbl_usuarios`. |

## Responsabilidades por arquivo

### `services-account`

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `plans/sale-recovery/deploy/001_sale_recovery.sql` | Novo | Inserir o valor padrão em `system_vars`; o SQL é aplicado manualmente. |
| `app/Model/UserSystemVar.php` | Novo, se ainda não houver modelo | Mapear `user_system_vars`. |
| `app/Domain/SystemVar/Repository/UserSystemVarRepository.php` | Novo | Buscar override e aplicar upsert/delete do override. |
| `app/Application/Service/SaleRecoveryFeeResolver.php` | Novo | Resolver taxa efetiva: override do usuário, depois valor padrão global. Account é a fonte de verdade; não decidir cobrança nesta fase. |
| API/serviço de variáveis de usuário | Alterar | Expor leitura/escrita do override para o Commerce e administração. |

### `services-commerce-v2`

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| Casos de uso de `form-data` e recovery de afiliado | Alterar | Consultar o resolvedor de Account e retornar a taxa efetiva apenas como campo informativo no payload de configuração; não manter dados de usuário localmente. |

### `dashboard-seller` — administração

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| Tela/página de configurações administrativas globais | Alterar ou criar | Exibir e editar a taxa padrão `sale_recovery_unit_price`. Deve aceitar somente admin 1 e 2. |
| `views/dashboard/admin/seller_overview/_components/fees_modal.php` | Alterar | Exibir a taxa efetiva de recuperação do seller e ação “Personalizar” ou “Remover override”. |
| `views/dashboard/admin/seller_overview/index.php` | Alterar, se necessário | Passar valor padrão, override e valor efetivo ao modal. |
| `actions/admin/user/sale_recovery_fee.php` | Novo | Validar admin 1/2, usuário alvo, valor monetário não negativo e fazer upsert/delete em `user_system_vars`. |
| Ação/página administrativa de taxa padrão | Novo ou alterar | Validar admin 1/2 e gravar em `system_vars`. |
| `includes/helpers.php` | Sem mudança funcional esperada | Reutilizar `getCustomVar`; só alterar se for necessário centralizar validação/formatação. |

### `edge-gateway` e `edge-public-api`

| Serviço | Responsabilidade |
| --- | --- |
| `edge-gateway` | Expor ao Dashboard as operações administrativas de taxa e a consulta da taxa efetiva. |
| `edge-public-api` | Autenticar/autorizar o usuário externo e encaminhar ao Account; não acessar `system_vars` ou `user_system_vars` diretamente. |

### `dashboard-seller` — gestão de produto

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `product_form.php` | Alterar | Mostrar a taxa efetiva do produtor como valor somente leitura, perto da configuração de recovery. |
| `affiliate_product_detail.php` | Alterar | Mostrar a taxa efetiva do afiliado como valor somente leitura. |
| Cliente dos endpoints de configuração | Alterar | Consumir, via Gateway/Public API, o valor efetivo retornado pelo Commerce; não calcular valor no browser. |

## Contratos sugeridos

As telas de gestão de produto recebem a taxa junto da configuração:

```json
{
  "sale_recovery": {
    "enabled": true,
    "steps": [],
    "effective_unit_price": "2.50"
  }
}
```

Para a tela administrativa, os dados necessários são:

```json
{
  "default_unit_price": "2.50",
  "user_override_unit_price": "1.99",
  "effective_unit_price": "1.99"
}
```

`user_override_unit_price` é `null` quando não existe override. “Remover
override” apaga somente a linha de `user_system_vars`; o usuário volta
imediatamente ao valor padrão.

## Validações e segurança

- [ ] Permitir gestão apenas para `permissao IN (1, 2)` no backend; esconder controles no frontend não é suficiente.
- [ ] Rejeitar valores vazios, negativos, não numéricos ou fora do limite monetário definido.
- [ ] Guardar valores monetários como decimal/string normalizada; nunca depender de `float` para o valor persistido.
- [ ] Não permitir que produtor ou afiliado envie `effective_unit_price` ao salvar a regra de produto.
- [ ] Garantir que a consulta de produto afiliado use o ID do afiliado, e não o usuário do produtor, ao resolver a taxa.

## Critérios de aceite

- [ ] Admin 1 ou 2 altera a taxa padrão e sellers sem override passam a visualizar o novo valor.
- [ ] Admin 1 ou 2 cria um override e o seller passa a visualizar esse valor, sem mudar a taxa dos demais.
- [ ] Ao remover o override, o seller volta ao valor padrão.
- [ ] Produtor vê sua taxa efetiva na edição do produto; afiliado vê sua própria taxa na edição afiliada.
- [ ] Nenhum usuário não administrador consegue criar, alterar ou remover taxas.
- [ ] Esta fase ainda não gera cobrança: ela apenas administra e expõe o valor que será usado no futuro.
