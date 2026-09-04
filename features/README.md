# Mapas técnicos de features

Cada pasta deste diretório documenta uma feature ou capacidade de negócio durável. O objetivo é permitir que pessoas e agentes entendam o fluxo sem recomeçar a investigação do zero.

## Organização

```text
features/
  nome-da-feature/
    README.md
    contratos.md          # opcional
    dados-e-filas.md      # opcional
```

Use nomes curtos em minúsculas e com hífens. O `README.md` é sempre a visão principal; arquivos adicionais só devem existir quando o assunto ficar grande o suficiente para prejudicar a leitura.

## Formato do README de uma feature

```md
# Feature — nome

> Status: ativo | em evolução | legado
> Última atualização: YYYY-MM-DD
> Confiança: confirmada no código | parcialmente confirmada

## Objetivo

Qual problema resolve, quem usa e o que fica fora do escopo.

## Fluxo principal

```text
Chamador -> Front -> Edge -> Serviço -> Banco/Redis/Fila -> Resultado
```

## Componentes e responsabilidades

| Componente | Responsabilidade | Entrada/saída relevante |
| --- | --- | --- |

## Contratos e autorização

Rotas, payloads relevantes, JWT/permissões, webhooks e compatibilidade.

## Dados e processamento assíncrono

Banco, cache, filas, produtores, consumidores, idempotência e efeitos persistentes.

## Operação e validação

Health checks, logs seguros, teste de compatibilidade em homologação e links para deploys relacionados.

## Limitações e pendências

Hipóteses, riscos conhecidos e decisões ainda necessárias.

## Referências

Caminhos no código, testes, planos e documentos de deploy que comprovam o mapa.
```

## Regras de escrita

- Registre comportamento confirmado, com referências a arquivos ou testes quando útil.
- Diferencie claramente fatos, hipóteses e pendências.
- Não copie segredos, valores de `.env`, dados pessoais ou procedimentos de produção.
- Atualize o mapa junto de mudanças que alterem fluxo, contrato, dados, filas, autorização ou operação.
- Mantenha instruções de execução detalhadas em `docs/deploys/`; o mapa deve explicar o funcionamento técnico, não duplicar runbooks.
