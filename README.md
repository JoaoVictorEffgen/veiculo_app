# Controle de Veículos — App Interno

App mobile (Flutter) para controle interno de veículos e motoristas: status
EM MOVIMENTO / PARADO, local de parada, histórico de movimentações.

## Status do projeto

- [x] **Etapa 1** — Setup do projeto (estrutura, dependências, tema, navegação base)
- [x] **Etapa 2** — MVP local consolidado (Drift, auth guard, CRUD admin, histórico com filtro)
- [x] **Etapa 3** — Firebase (Auth + Firestore + sync em tempo real)
- [ ] Etapa 4 — Offline: fila local + sincronização
- [ ] Etapa 5 — Build Android para celulares corporativos

## Firebase

- **Projeto:** `device-streaming-53bb0fb6`
- **Conta:** joaoeffgens@gmail.com

### Ativar no Console (se ainda nao fez)

1. [Authentication](https://console.firebase.google.com/project/device-streaming-53bb0fb6/authentication) → E-mail/senha → Ativar
2. [Firestore](https://console.firebase.google.com/project/device-streaming-53bb0fb6/firestore) → Criar banco → Regiao Sao Paulo
3. Deploy das regras: `firebase deploy --only firestore:rules`

O app cria automaticamente os usuarios e veiculos iniciais na primeira execucao (`ensureSeedData`).

## Como rodar

```bash
flutter pub get
dart run build_runner build
flutterfire configure   # se necessario reconfigurar
flutter run -d chrome   # ou -d android
```

> Flutter: `C:\src\flutter\bin` — adicione ao PATH se necessario.

### Credenciais de teste

| Perfil | E-mail | Senha |
|---|---|---|
| Motorista 1 | motorista1@empresa.com | 123456 |
| Motorista 2 | motorista2@empresa.com | 123456 |
| Motorista 3 | motorista3@empresa.com | 123456 |
| Motorista 4 | motorista4@empresa.com | 123456 |
| Admin | admin@empresa.com | 123456 |

## Etapa 3 — o que foi implementado

- Firebase Auth (login real)
- Firestore como fonte central (veiculos, usuarios, movimentacoes)
- Sync em tempo real no dashboard e historico
- Transacao atomica no INICIAR/ON (impede conflito entre motoristas)
- Seed automatico na primeira execucao
- Plataforma Android adicionada ao projeto

## Estrutura

```
lib/shared/services/firebase_vehicle_repository.dart  → backend Firebase
lib/shared/services/local_vehicle_repository.dart       → cache local (Etapa 4)
lib/firebase_options.dart                               → config gerada pelo FlutterFire
```
