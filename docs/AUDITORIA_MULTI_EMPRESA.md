# Auditoria multi-empresa (v0.3.36+)

Como motoristas, checklists, tarefas e GPS ficam ligados por empresa.

## Motoristas

| Acao | Ligacao |
|------|---------|
| Listagem admin | Firestore `users` com `companyId` = empresa do admin |
| Cadastro | `addDriver` grava `companyId` do admin |
| Editar / excluir | Bloqueado se o motorista for de outra empresa |
| Login | Perfil carrega `companyId` do documento `users/{uid}` |

## Veiculos e GPS

| Acao | Ligacao |
|------|---------|
| Frota | Query `vehicles` filtrada por `companyId` |
| Iniciar / parar | Transacao valida veiculo da mesma empresa |
| Rastreamento | `tracking/{driverId}` grava `companyId` do motorista + veiculo em uso |
| Mapa admin | Stream `tracking` filtrada por `companyId` |

## Checklist

| Acao | Ligacao |
|------|---------|
| Salvar | `companyId` do motorista + veiculo validado na mesma empresa |
| ID do doc | `{driverId}_{vehicleId}_{data}` — unico por motorista/veiculo/dia |
| Admin ve historico | Query por `companyId` |

## Tarefas (announcements)

| Acao | Ligacao |
|------|---------|
| Publicar | `companyId` do admin; motorista alvo deve ser da mesma empresa |
| Motorista ve | Query por `companyId` + `isVisibleTo` (grupo ou `targetDriverId`) |
| Iniciar / concluir | Regra Firestore + checagem de `companyId` no app |

## Dados legados

Na abertura do app, `ensureSeedData` preenche `companyId` ausente (principal = `default`) e cria empresa demo.
