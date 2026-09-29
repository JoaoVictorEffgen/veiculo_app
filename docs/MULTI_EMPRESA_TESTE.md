# Teste multi-empresa (isolamento)

Duas empresas de demonstracao no mesmo Firebase. Cada login so enxerga veiculos, motoristas, tarefas e GPS da **sua** empresa.

## Contas

| Empresa | Perfil | E-mail | Senha |
|---------|--------|--------|-------|
| **Principal** (`default`) | Admin | admin@empresa.com | 123456 |
| Principal | Motorista | motorista1@empresa.com | 123456 |
| **Demo** (`empresa-demo`) | Admin | admin@demo.com | 123456 |
| Demo | Motorista | motorista1@demo.com | 123456 |

Veiculos principal: Strada, Toro, Hilux, Fiorino.  
Veiculos demo: Saveiro Demo, Ranger Demo (placas DEM-*).

## Preparar o banco (uma vez)

1. Publique regras e indices:
   ```bash
   firebase deploy --only firestore:rules,firestore:indexes
   ```
2. Abra o app **online** (Wi‑Fi/dados) na v0.3.35+ — na abertura o app roda `ensureSeedData`: cria contas demo, empresas e preenche `companyId` nos dados antigos (principal = `default`). A primeira abertura pode demorar alguns segundos.
3. Alternativa manual no PC: `dart run tool/seed_firebase.dart`

Aguarde alguns minutos se o Firebase pedir indice composto (link no erro do console).

## Roteiro de teste

### 1. Empresa principal

1. Login: **admin@empresa.com**
2. Veja **4 veiculos** (Strada, Toro, Hilux, Fiorino).
3. Publique uma tarefa teste (ex.: "Tarefa Empresa A").
4. Logout.

### 2. Empresa demo

1. Login: **admin@demo.com**
2. Deve ver **2 veiculos** (Saveiro Demo, Ranger Demo) — **nao** deve aparecer Strada/Toro.
3. Publique tarefa "Tarefa Empresa B".
4. Logout.

### 3. Motorista isolado

1. Login: **motorista1@demo.com**
2. So ve frota demo; tarefas da empresa A nao aparecem.
3. Inicie um veiculo demo (checklist se pedir).

### 4. Mapa admin (GPS)

1. **admin@demo.com** → aba Mapa GPS: so rastros da demo.
2. **admin@empresa.com** → so rastros da principal.

### Resultado esperado

- Nenhum admin lista motoristas ou veiculos da outra empresa.
- Tarefas e relatos ficam separados por `companyId`.
- Dados antigos sem `companyId` sao tratados como empresa **default** (principal).

## Campo tecnico

- Documentos carregam `companyId`: `default` ou `empresa-demo`.
- Usuario carrega `companyId` no login (Firestore ou seed).
- Regras Firestore bloqueiam leitura/escrita entre empresas.
