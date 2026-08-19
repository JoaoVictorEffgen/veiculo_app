# Controle de Veículos — App Interno

App mobile (Flutter) para controle interno de veículos e motoristas: status
EM MOVIMENTO / PARADO, local de parada, histórico de movimentações.

## Status do projeto

- [x] **Etapa 1** — Setup do projeto (estrutura, dependências, tema, navegação base)
- [ ] Etapa 2 — Autenticação (Firebase Auth + identificação automática do motorista)
- [ ] Etapa 3 — Modelo de dados e repositórios (Firestore + Drift local)
- [ ] Etapa 4 — Dashboard (cards de veículos, separação por status)
- [ ] Etapa 5 — Ações ON/OFF (com transaction para evitar conflito entre motoristas)
- [ ] Etapa 6 — Histórico de movimentações
- [ ] Etapa 7 — Painel admin (CRUD motoristas/veículos)
- [ ] Etapa 8 — Offline: fila local + sincronização

## Como rodar

```bash
flutter pub get
flutter run
```

> Nesta etapa o app já roda e navega (Splash → Login → Dashboard), mas as
> telas de Login e Dashboard ainda são placeholders — serão implementadas
> nas próximas etapas. O Firebase ainda não está conectado (ver `main.dart`).

## Próximo passo (Etapa 2)

Antes de implementar a Etapa 2, será necessário:

1. Criar um projeto no [Firebase Console](https://console.firebase.google.com)
2. Rodar `flutterfire configure` nesse projeto Flutter para gerar
   `lib/config/firebase_options.dart`
3. Cadastrar os 4 motoristas + 1 admin no Firebase Auth (ou via tela de
   cadastro que implementaremos no painel admin)

## Estrutura de pastas

Arquitetura em camadas por feature (`data` / `domain` / `presentation`),
detalhada na proposta de arquitetura discutida antes da implementação.
Veja `lib/features/*` para cada módulo (auth, vehicles, history, admin).
