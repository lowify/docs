# Documento substituído

O roteiro canônico de produção é
[2026-11-06_CHECKOUT_APPLE_GOOGLE_PAY_DEPLOY.md](../2026-11-06-checkout-apple-google-pay/2026-11-06_CHECKOUT_APPLE_GOOGLE_PAY_DEPLOY.md).
Ele contém os diretórios produtivos confirmados, os comandos operacionais e
os SQLs manuais no padrão adotado para produção.

---

# Deploy — Apple Pay e Google Pay no Checkout (produção)

## Objetivo

Publicar Apple Pay e Google Pay para compras avulsas (`ONE_TIME`) feitas com
cartão no Checkout. A disponibilidade final de cada carteira depende de quatro
camadas: flag global, autorização explícita do seller, configuração explícita
do produto e compatibilidade/configuração do gateway e do dispositivo do
comprador.

Não inclui assinaturas, Checkout Transparente ou compra recorrente. A compra
recorrente por cartão continua no fluxo já existente. Este documento prepara a
execução em produção; a operação ainda não foi executada em produção.

## Componentes e referências

| Repositório | Branch de deploy | Commit de referência | Papel |
| --- | --- | --- | --- |
| `dashboard-seller` | `feat/checkout-apple-google-pay` | `b415022c` | Controles de produto e autorização por seller. |
| `front-checkout` | `feat/checkout-apple-google-pay` | `9c1af9e` | Renderização e coleta dos tokens das carteiras. |
| `edge-gateway` | `feat/checkout-apple-google-pay` | `acf8481` | Rotas internas entre front e serviços. |
| `edge-public-api` | `feat/checkout-apple-google-pay` | `b88d9fe` | Extração/propagação de JWT e roteamento público. |
| `services-commerce-v2` | `feat/checkout-apple-google-pay` | `a4e56bd` | Elegibilidade, sessão Apple e processamento do checkout. |
| `services-banking-v2` | `feat/checkout-apple-google-pay` | `36913f0` | Persistência e tratamento de token de carteira. |

Não incluir outros repositórios nesta entrega. Em especial, não alterar
`services-account`, Checkout Transparente, serviços legados, `data_layer` ou
infraestrutura sem uma mudança de escopo aprovada.

## Alterações incluídas

- Dashboard Seller: controles Apple Pay e Google Pay por produto; valores não
  informados são tratados como desabilitados.
- Checkout: Apple Pay somente em navegador/dispositivo compatível; Google Pay
  no ambiente definido pelo Commerce; ambos exigem dados válidos do comprador
  antes de ficarem utilizáveis. Ao selecionar uma carteira, campos exclusivos
  de cartão deixam de ser obrigatórios.
- Edges: rotas para consulta de elegibilidade, criação de sessão Apple e
  processamento do pagamento são encaminhadas preservando a autenticação.
- Commerce V2: combina as flags global, de seller e de produto; rejeita wallet
  para assinatura ou parcelamento diferente de uma vez; realiza a validação de
  merchant session Apple e encaminha o token ao Banking V2.
- Banking V2: associa a cobrança de cartão ao cartão/token de wallet quando
  aplicável.

Não há novo produtor, consumidor ou contrato de fila nesta entrega. A
identidade JWT continua sendo extraída e validada no `edge-public-api`.

## Pré-requisitos

1. As seis branches da tabela devem existir no remoto e conter, no mínimo, os
   commits indicados. Antes da operação, incorporar a `main` atual em cada
   branch usando o processo de preparação de deploy; não fazer rebase.
2. Ter certificado de processamento Apple Pay, chave privada correspondente,
   Merchant ID Apple e domínio do checkout produtivo previamente registrados e
   validados no Apple Developer. O certificado de homologação não pode ser
   reutilizado.
3. Configurar no ambiente do Commerce V2, sem registrar valores no Git:
   `APPLE_PAY_MERCHANT_IDENTIFIER`, `APPLE_PAY_IDENTITY_CERTIFICATE_PATH`,
   `APPLE_PAY_IDENTITY_PRIVATE_KEY_PATH`, `GOOGLE_PAY_MERCHANT_ID`,
   `CIELO_GOOGLE_PAY_GATEWAY_MERCHANT_ID`,
   `PAGARME_GOOGLE_PAY_GATEWAY_MERCHANT_ID` e `GOOGLE_PAY_TEST_MODE=false`.
   Os caminhos Apple devem apontar para um volume externo, somente leitura,
   acessível pelo container do Commerce V2.
4. Confirmar com o adquirente/gateway quais identificadores de Google Pay são
   válidos em produção. Não usar os valores fictícios de homologação.
5. Confirmar que o domínio produtivo do checkout está em HTTPS e associado ao
   Merchant ID Apple. O navegador não cria sessão Apple Pay em página insegura.
6. Definir um produto avulso piloto, um seller autorizado e um comprador de
   teste. Iniciar com as flags globais desligadas; os dados reais de clientes
   não devem ser usados para teste.

## Banco de dados

Executar os SQLs manuais que acompanham este documento, uma única vez e antes
de ativar flags. Não executar migrations automáticas nesta entrega.

| Banco | Pré-check | Executar somente se o pré-check indicar ausência total | Validar depois |
| --- | --- | --- | --- |
| Commerce V2 | [PRECHECK.sql](sql/commerce-v2/PRECHECK.sql) | [DEPLOY.sql](sql/commerce-v2/DEPLOY.sql) | [VALIDATE.sql](sql/commerce-v2/VALIDATE.sql) |
| Banking V2 | [PRECHECK.sql](sql/banking-v2/PRECHECK.sql) | [DEPLOY.sql](sql/banking-v2/DEPLOY.sql) | [VALIDATE.sql](sql/banking-v2/VALIDATE.sql) |

No Commerce V2, executar o `DEPLOY.sql` somente se o pré-check retornar zero
linhas para as duas colunas e zero linhas para as duas `system_vars`. No
Banking V2, executar somente se coluna e índice estiverem ambos ausentes.

Se qualquer pré-check retornar estado parcial, tipo/default divergente ou uma
única chave global, parar: não adaptar o DDL, não criar coluna/índice isolado e
não fazer backfill. Após cada `DEPLOY.sql`, executar imediatamente o respectivo
`VALIDATE.sql`. Não remover essas estruturas em rollback.

## Sequência de deploy

Os comandos abaixo são executados no diretório de cada repositório no ambiente
produtivo. O operador deve usar os caminhos oficiais da produção; eles não são
inferidos a partir da VPS de homologação.

1. Para cada um dos seis repositórios, confirmar árvore limpa e referências:

   ```bash
   git status --porcelain=v1
   git fetch origin --prune
   git show-ref --verify --quiet refs/remotes/origin/main
   git show-ref --verify --quiet refs/remotes/origin/feat/checkout-apple-google-pay
   ```

   Parar integralmente se houver alteração local, remoto diferente ou branch
   ausente.

2. Em cada repositório, nesta ordem, selecionar e atualizar a branch:
   `services-banking-v2`, `services-commerce-v2`, `edge-gateway`,
   `edge-public-api`, `front-checkout`, `dashboard-seller`.

   ```bash
   git switch feat/checkout-apple-google-pay
   git pull --ff-only origin feat/checkout-apple-google-pay
   ```

3. Executar os SQLs manuais de **Banco de dados**: pré-check, DDL somente se
   aplicável e validação. Confirmar o resultado antes de seguir.

4. Instalar o certificado e a chave Apple reais em volume externo, montar o
   volume como somente leitura no Commerce V2 e configurar as variáveis reais
   no ambiente do serviço. Confirmar apenas que os arquivos podem ser lidos no
   container; nunca imprimir conteúdo, caminho público, chave ou variáveis.

5. Reconstruir e iniciar, com o mecanismo operacional de produção, nesta
   ordem: Banking V2, Commerce V2, Edge Gateway, Edge Public API, Front
   Checkout e Dashboard Seller. Usar o comando de Compose/orquestração adotado
   na produção para cada componente; não copiar comandos ou caminhos da VPS de
   homologação.

6. Confirmar health checks e logs sem erro fatal nos seis componentes. Somente
   então liberar gradualmente:

   - habilitar ambas as flags globais;
   - habilitar Apple Pay e/ou Google Pay para o seller piloto;
   - habilitar cada wallet no produto piloto escolhido.

   A ausência de uma flag de seller ou produto equivale a `false`.

## Validação pós-deploy

1. Faça login no Dashboard como o seller piloto, abra o produto avulso e
   confirme que cartão está ativo. Ative Apple Pay e/ou Google Pay e salve.
   Os controles devem ficar disponíveis apenas para produto avulso e cartão.
2. Abra o checkout do produto em Chrome/Android ou Chrome para testar Google
   Pay. Preencha os dados obrigatórios do comprador; o botão deve ficar
   clicável e abrir a carteira com uma forma de pagamento de teste aprovada.
3. Abra o mesmo checkout no Safari de iPhone/iPad/macOS com Apple Wallet
   configurada. O botão Apple Pay deve aparecer somente no dispositivo
   compatível e a validação de merchant deve abrir a folha de pagamento.
4. Conclua uma transação de teste autorizada para cada carteira, se o gateway
   disponibilizar ambiente/teste produtivo aprovado. Confirme a página de
   confirmação e a venda no Dashboard. Não repetir cobranças reais sem uma
   janela de teste aprovada.
5. Como conferência técnica opcional, confirme que os logs não contêm segredo,
   token de carteira ou chave privada, e que Banking V2 registrou a associação
   de wallet para a cobrança.
6. Confirme também que produto sem flag, seller sem flag, assinatura e checkout
   transparente não exibem as carteiras.

Se Apple Pay não aparecer, testar primeiro Safari compatível com uma carteira
Apple configurada; em outros navegadores o botão deve permanecer oculto. Se
Google Pay estiver cinza, preencher os dados obrigatórios do comprador antes
de tratar como falha de configuração.

## Rollback

1. Desligar primeiro as duas flags globais. Isso remove a oferta das carteiras
   sem apagar vendas, cobranças ou dados de cartão.
2. Desligar as flags de seller e produto que tenham sido habilitadas para o
   piloto.
3. Se for necessário reverter código, restaurar as referências anteriores
   registradas pelo operador antes do passo 2, em ordem inversa: Dashboard,
   Checkout, Public API, Gateway, Commerce e Banking.
4. Não apagar colunas, índice, chaves de sistema, logs, certificados ou
   registros de cobrança como parte do rollback. Revogar/substituir material
   Apple somente pelo processo de gestão de credenciais.

## Referências

- `plans/checkout-apple-google-pay/README.md`
- `plans/checkout-apple-google-pay/04_CONTRATO_TECNICO_DE_TESTE.md`
- `deploys/2026-11-16-checkout-apple-google-pay-homologation/2026-11-16_CHECKOUT_APPLE_GOOGLE_PAY_HOMOLOGATION.md`
