# Criar empresa (multi-tenant)

## Fluxo

1. Login → **Criar empresa (teste gratuito)**
2. Informe nome da empresa, seu nome, e-mail e senha
3. Voce entra como **administrador** com `companyId` unico (`co-...`)
4. Em **Administracao**, cadastre **motoristas** e **veiculos**
5. Motoristas entram com o e-mail/senha que voce definiu

Cada empresa ve apenas seus dados (`companyId` em Firestore + regras).

## Empresa antiga (`admin@empresa.com`)

Contas criadas antes do fluxo "Criar empresa" usam `companyId: default`.
Ao entrar, o app ainda mescla dados legados sem `companyId` e pode reparar o campo.

## Pagamento

Campo `plan: trial` na empresa — integracao de pagamento fica para uma etapa futura.

## Firebase

Apos atualizar regras:

```bash
firebase deploy --only firestore:rules --project device-streaming-53bb0fb6
```
