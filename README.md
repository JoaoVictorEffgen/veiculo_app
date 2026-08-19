# Controle de Veículos — App Interno

App mobile (Flutter) para controle interno de veículos e motoristas: status
EM MOVIMENTO / PARADO, local de parada, histórico de movimentações.

## Status do projeto

- [x] **Etapa 1** — Setup do projeto (estrutura, dependências, tema, navegação base)
- [x] **Etapa 2** — MVP local consolidado (Drift, auth guard, CRUD admin, histórico com filtro)
- [ ] Etapa 3 — Firebase (Auth + Firestore + sync em tempo real)
- [ ] Etapa 4 — Offline: fila local + sincronização
- [ ] Etapa 5 — Build Android para celulares corporativos

## Como rodar

```bash
flutter pub get
dart run build_runner build
flutter run
```

> Flutter instalado em `C:\src\flutter` — adicione `C:\src\flutter\bin` ao PATH se necessário.

### Credenciais de teste (MVP local)

| Perfil | E-mail | Senha |
|---|---|---|
| Motorista 1 | motorista1@empresa.com | 123456 |
| Motorista 2 | motorista2@empresa.com | 123456 |
| Motorista 3 | motorista3@empresa.com | 123456 |
| Motorista 4 | motorista4@empresa.com | 123456 |
| Admin | admin@empresa.com | 123456 |

## Etapa 2 — o que foi implementado

- Persistência local com **Drift** (usuários, veículos, movimentações, sessão)
- **Auth guard** no router (rotas protegidas, admin isolado)
- Sessão salva — ao reabrir o app, o motorista permanece logado
- Confirmação antes de **INICIAR / ON**
- Dialog de parada com **motorista identificado automaticamente**
- Admin: **cadastrar, editar e excluir** motoristas e veículos
- Histórico com **filtro por veículo**
- Destaque do veículo em uso no dashboard

## Estrutura de pastas

Arquitetura em camadas por feature (`data` / `domain` / `presentation`).
Veja `lib/features/*` para cada módulo (auth, vehicles, history, admin).

```
lib/shared/database/   → Drift (SQLite / Web)
lib/shared/models/       → Entidades unificadas
lib/shared/services/     → Repositório + Riverpod providers
```

## Próximo passo (Etapa 3)

1. Criar projeto no [Firebase Console](https://console.firebase.google.com)
2. Rodar `flutterfire configure`
3. Substituir repositório local por Firestore + Firebase Auth
