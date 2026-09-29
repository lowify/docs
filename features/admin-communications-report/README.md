# Feature — administração e relatório de comunicações

> Status: em evolução
> Última atualização: 2026-09-29
> Confiança: confirmada no código; homologação pendente

## Objetivo

Permitir que administradores configurem o provider de envio de cada template de e-mail e acompanhem volumes agregados de e-mails e WhatsApp. O relatório não expõe destinatários, conteúdo de mensagens ou erros brutos de provider.

Ficam fora do escopo a alteração do conteúdo dos templates, o reenvio manual e métricas financeiras de créditos de comunicação.

## Fluxo principal

```text
Administrador (perfil 1 ou 2)
  -> Dashboard Seller
  -> Edge Gateway
  -> Edge Public API
  -> Services Notification
  -> email_template, email_single, whatsapp_meta e Redis
```

O Dashboard Seller usa uma aba **Sistema** para consultar o overview e alterar o provider de um template. A página de relatório recebe o período, busca os dados agregados e renderiza cards, gráficos diários e listas por template, provider e categoria de falha.

## Componentes e responsabilidades

| Componente | Responsabilidade |
| --- | --- |
| `dashboard-seller` | Tela de configuração, página do relatório e endpoints AJAX autenticados pelo Gateway. |
| `edge-gateway` | Encaminha as três rotas administrativas ao Public API. |
| `edge-public-api` | Exige JWT de administrador e agrega o overview de notifications com as configurações globais de WhatsApp de account. |
| `services-notification` | Fonte dos providers e templates, persistência do provider e cálculo dos volumes diários. |
| Redis principal | Cache por dia completo para consultas de relatório. |

## Contratos e autorização

As rotas externas são protegidas pelo JWT do Public API. São permitidos somente usuários com permissões `1` ou `2`; colaboradores são rejeitados mesmo que tragam uma permissão administrativa no payload.

| Método | Rota | Finalidade |
| --- | --- | --- |
| `GET` | `/admin/system/overview` | Retorna providers de e-mail, templates e configurações globais de WhatsApp. Não recebe período. |
| `PUT` | `/admin/email-templates/{id}/provider` | Define o provider de um template. O provider deve existir na configuração de `services-notification`. |
| `GET` | `/admin/communications-report?start=YYYY-MM-DD&end=YYYY-MM-DD` | Retorna totais diários e agrupamentos para um período de no máximo 367 dias inclusivos. |

O relatório devolve somente contagens e rótulos técnicos categorizados. Falhas sem `delivery_error` são agrupadas como `send_failed`; a coluna de erro bruto não integra a resposta.

## Dados e cache

O relatório consulta `email_single` e `whatsapp_meta` pelo `created_at` do envio. Os agregados incluem:

- volume, entregue, lido e falho por canal e dia;
- e-mail por template e provider;
- e-mail por provider;
- WhatsApp por template;
- falhas por canal e categoria.

Cada dia até D-2 é armazenado por 60 dias em Redis com a chave `admin:communications-report:v1:YYYY-MM-DD`. Hoje e ontem não são cacheados porque ainda podem receber callbacks e mudanças de status.

## Operação e validação

Antes da homologação, os serviços precisam ter os providers de e-mail configurados por variáveis de ambiente já documentadas em `services-notification/.env.example`.

Em homologação, validar:

1. A aba **Sistema** lista os providers configurados e persiste a troca de um template.
2. Perfis 1 e 2 conseguem consultar o overview e o relatório; perfil não administrativo e colaborador recebem bloqueio.
3. Um período com envios de ambos os canais renderiza os totais, dias e agrupamentos corretos.
4. Hoje e ontem refletem mudanças recentes; D-2 permanece estável durante o TTL de cache.

## Limitações e pendências

- A execução integrada exige ambiente com Swoole, banco e Redis; ela não foi rodada na máquina local.
- O dashboard carrega Chart.js via CDN já utilizado pela página; a disponibilidade desse recurso deve ser conferida no ambiente alvo.
- Não há invalidação de cache porque a regra vigente deliberadamente preserva apenas dias D-2 ou mais antigos.

## Referências

- `services-notification/app/Controller/AdminSystemOverviewController.php`
- `services-notification/app/Controller/AdminCommunicationReportController.php`
- `services-notification/app/Service/Admin/CommunicationReportService.php`
- `edge-public-api/app/Http/Controllers/AdminSystemController.php`
- `edge-gateway/config/routes.php`
- `dashboard-seller/views/dashboard/admin/configs/system_notifications/index.php`
- `dashboard-seller/views/dashboard/admin/communications_report/index.php`
