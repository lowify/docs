# Diagnóstico de homologação — abertura manual de contas BaaS

Data da execução: 30/10/2026.

## Estado publicado

| Componente | Resultado |
| --- | --- |
| `services-account` | Container recriado e saudável; worker de `account:user:events` ativo. |
| `edge-public-api` | Container recriado e saudável; rota manual disponível. |
| `edge-gateway` | Gateway e worker recriados e saudáveis. |
| `dashboard-seller` | Atualizado somente por Git, sem reconstrução de container. |

Nenhum outro repositório foi alterado na VPS. O `services-banking` foi
consultado somente em modo leitura para acompanhar o resultado das filas.

## Verificações realizadas

1. `WOOVI_BAAS_AUTO_REGISTER_ENABLED` estava ausente no container do Account;
   o código publicado aplica `false` como default.
2. O Public API listou `POST /api/baas/accounts/open` apontando para
   `BaasAccountsController@open`.
3. Duas contas sintéticas de homologação foram usadas para disparar a abertura
   manual Woovi. Os eventos `register_baas` foram aceitos e consumidos com
   sucesso pelo `services-account`.
4. O Banking criou as contas BaaS de teste `407` e `408` e publicou os eventos
   de registro correspondentes.

## Resultado do envio Woovi

A chamada externa à Woovi não ocorreu. O worker do Banking bloqueou as
solicitações na validação local obrigatória de KYC antes de usar credenciais:

| Conta BaaS de teste | Resultado |
| --- | --- |
| `407` | `corporateName inválido.` |
| `408` | `Erro de validação do registro de conta: Parâmetro obrigatório ausente: representatives` |

Assim, a homologação confirmou o fluxo manual Dashboard → Gateway → Public API
→ Account → Banking, inclusive o consumo da fila. Ela não confirma uma resposta
de autenticação da Woovi: para isso, é necessário uma conta sintética PJ com
representante e documentos de KYC válidos no formato aceito pelo Banking.

## Dados e limpeza

Os IDs internos das contas sintéticas são `900040` e `900041`. Eles permanecem
no ambiente para auditoria e devem ser tratados pelo procedimento normal de
encerramento de contas de teste. Não apagar eventos, contas BaaS ou mensagens de
fila para ocultar este diagnóstico.
