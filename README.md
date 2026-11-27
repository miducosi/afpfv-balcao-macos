# Balcão Vindimas — macOS

App nativa (SwiftUI, macOS 15+) do **backoffice** do Balcão das Vindimas. Fala com a API mobile do
[afpfv-balcao](../../Web/afpfv-balcao) (`/api/mobile/*`, guia em `docs/mobile-api.md` desse repositório), a
mesma da app `afpfv-balcao-rn`. Sem dependências externas.

## O que tem

| Secção                    | Capacidade (`/auth/me`) | Faz                                                              |
| ------------------------- | ----------------------- | ---------------------------------------------------------------- |
| Painel                    | `staff`                 | mosaicos por área, pedidos urgentes                              |
| Pedidos                   | `queue`                 | fila com filtros e pesquisa, conversa, notas internas, estado, ficar com o pedido |
| Terrados                  | `stalls`                | candidaturas, documentos (aceitar/recusar), decisões e lote      |
| Comprovativos / Cobranças | `treasury`              | validar comprovativos, cobranças, registar pagamentos, faturas   |
| Provas                    | `races`                 | inscrições por prova, check-in                                   |
| Livres-trânsito           | `passes`                | emitir, recusar, revogar, QR                                     |
| Validar livres-trânsito   | `validatePasses`        | leitura por câmara, leitor USB ou código; histórico              |
| Senhas / Mapa             | `canteen`               | aprovar (com ou sem cobrança), recusar, anular; mapa por dia     |
| Validar senhas            | `validateMeals`         | entrada no refeitório (unitária e grupo)                         |
| Equipa / Auditoria        | `admin`                 | perfis e áreas, convites, registo de auditoria                   |

A barra lateral mostra só o que a conta pode usar. Contas sem backoffice (`home: portal`) não entram.
A configuração (tipologias, preços, planta, ementas, regulamentos) continua só na web.

## Configurar

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # e preencher
open BalcaoVindimas.xcodeproj
```

`Secrets.xcconfig` (fora do git) leva o URL da API, o Supabase (URL e *publishable key*) e, se houver, a chave
da firewall da Vercel. Em xcconfig `//` é comentário: escrever `https:/$()/host`.

## Compilar

- Xcode: ⌘R. As pastas são *synchronized groups* — ficheiros novos entram sozinhos no projeto.
- Terminal: `scripts/build-release.sh` (ou `SIGN=adhoc` sem conta Apple).
- Para distribuir fora da App Store: Product › Archive › Developer ID, e notarizar.

## Testar contra o servidor local (e2e)

O afpfv-balcao tem um Supabase Auth falso e uma base descartável (`e2e/README.md`). Com o servidor e2e na
porta 3100:

```bash
xcodebuild -project BalcaoVindimas.xcodeproj -scheme BalcaoVindimas -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  'BALCAO_API_URL=http://localhost:3100/api/mobile' 'SUPABASE_URL=http://127.0.0.1:54321' \
  SUPABASE_PUBLISHABLE_KEY=fake-key build
```

Contas: `admin@test.pt`, `op@test.pt`, `tes@test.pt`, `gnr@test.pt`, `porta@test.pt` (palavra-passe `password123`).

## Estrutura

| Pasta          | Papel                                                                     |
| -------------- | ------------------------------------------------------------------------- |
| `App/`         | entrada, sessão (`AppModel`), secções por capacidade, definições          |
| `Core/`        | API (`APIClient`), Supabase Auth (REST), Keychain, formatação, labels pt-PT |
| `Models/`      | espelho de `src/lib/openapi/mobile/contracts.ts`                          |
| `Shared/`      | `Loader`, avisos, selos, ficheiros (Quick Look), QR (gerar e ler)         |
| `Features/`    | um ecrã por domínio                                                       |

Regras: enums ficam como `String` (um valor novo não parte a app); labels só em `Core/Labels.swift` (cópia de
`src/types/domain.ts`); dinheiro em cêntimos; mutações devolvem a mensagem do servidor e recarregam (⌘R).
Quando o contrato mudar no afpfv-balcao, atualizar `Models/Models.swift`.
