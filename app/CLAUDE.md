# Remote Pi — App (Flutter)

Cliente do Remote Pi (iOS, Android, Windows, Linux). Pareia via QR no mobile
ou colando o URI `/remote-pi pair` no desktop, lista sessões do Pi, chat com
streaming, approval cards para tool calls.

## Stack

- Flutter 3.41+ / Dart 3.11+
- Plataformas: iOS, Android, Windows, Linux
- State management: `ChangeNotifier` + `provider` (ViewModels reativos)
- DI: `auto_injector` (registry em `lib/config/`)
- Roteamento: `go_router`
- Resultado tipado: `Result<T, E>` (sucesso/falha explícitos)
- Crypto: bindings para libsodium (pacote a confirmar — ver `plan/00-decisions.md`)
- WebSocket: `web_socket_channel` ou similar

> Decisões ainda abertas (state mgmt definitivo, pacote libsodium) vivem em
> `../plan/00-decisions.md`. A stack acima é a direção atual baseada na
> arquitetura herdada; mudanças estruturais exigem plano novo.

## Comandos

- `flutter pub get` — instala deps
- `flutter analyze` — lint estático (deve passar zero issues)
- `flutter test` — testes
- `flutter run` — abre em simulador/device conectado
- `dart format .` — formata
- `flutter build ios --no-codesign` / `flutter build apk --debug` — build verificável
- `flutter build linux` / `flutter build windows` — desktop
  (Linux needs `clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libjsoncpp-dev`)

## Arquitetura por camadas

O `lib/` é organizado em camadas com responsabilidades estritas. Cada pasta
tem seu próprio `CLAUDE.md` descrevendo a persona daquela camada — **leia o
CLAUDE.md da camada antes de editar qualquer arquivo dentro dela**.

```
lib/
├── main.dart
├── config/          # Bootstrap, DI, env, setup global  → config/CLAUDE.md
│   └── utils/       # Helpers horizontais
├── domain/          # Entidades, use cases, validators  → domain/CLAUDE.md
├── data/            # Repositórios, adapters, APIs      → data/CLAUDE.md
├── routing/         # GoRouter, paths, guards           → routing/CLAUDE.md
└── ui/              # Páginas + ViewModels por feature  → ui/CLAUDE.md
    └── <feature>/
        ├── states/
        ├── viewmodels/
        ├── widgets/
        └── <feature>_page.dart
```

Regra de ouro do fluxo de dependência:

```
ui ──► domain ◄── data
        ▲
        │
     config (injeta tudo)
     routing (compõe rotas + ViewModels)
```

- `domain/` **não** importa nada de `data/`, `ui/`, `routing/`, `config/`.
- `data/` importa contratos de `domain/`, nunca de `ui/`.
- `ui/` consome `domain/` (use cases) via ViewModels — nunca chama `data/` direto.
- `config/` é o único lugar que conhece todas as camadas (para registrar bindings).

## Convenções

- **Naming**: arquivos `snake_case.dart`, classes `PascalCase`, widgets `PascalCase`
- **Imports**: relativos dentro do mesmo feature; absolutos via `package:app/...`
  quando cruzando features ou camadas
- **Barrel files**: cada feature/módulo pode expor um `<nome>.dart` agregando
  os símbolos públicos; consumidores externos importam só o barrel
- **Async**: prefira `Future`/`Stream` tipados, evite `dynamic`
- **Erros**: `Result<T, E>` ou exceptions tipadas; nunca `catch (e)` genérico em produção
- **ViewModels**: registrados em `config/` e injetados em `routing/` via Provider;
  páginas nunca instanciam ViewModel diretamente — sempre `context.watch/read/select`

## Regra crítica: `BuildContext` em código assíncrono

Acessar `context` após um `await` (ou dentro de `.then/.onSuccess/.flatMap/.whenComplete`)
pode crashar com `Null check operator used on a null value` se o widget já tiver sido
desmontado. O lint `use_build_context_synchronously` **não detecta** callbacks
encadeados — a prevenção é manual.

**Padrão obrigatório**:

```dart
// CORRETO — await + guard
final result = await viewModel.doSomething();
if (!mounted) return;          // em StatefulWidget
// if (!context.mounted) return; // em StatelessWidget
context.useContextSomehow();
```

```dart
// ERRADO — context dentro de callback assíncrono
await viewModel.doSomething().onSuccess((_) {
  context.useContextSomehow(); // CRASH se desmontado
});
```

> Nunca use `context` dentro de `.onSuccess()`, `.onFailure()`, `.flatMap()`,
> `.then()` ou `.whenComplete()`. Sempre transforme para `await` + guard.

## NÃO fazer

- Editar arquivos fora de `app/`
- Implementar crypto manual — usar bindings libsodium
- Comitar `build/`, `.dart_tool/`, `ios/Pods/` (já no `.gitignore` raiz)
- Adicionar dependência sem registrar no plano correspondente
- Misturar responsabilidades entre camadas — quando bater dúvida, leia o
  CLAUDE.md da camada alvo

## Modo orquestrado

Se receber um prompt começando com `[ORCH:<task-id>]`, leia
`../.orchestration/INSTRUCTIONS.md` antes de qualquer outra ação. Esse marker
indica que outro agente está coordenando o trabalho e tem regras específicas
(onde escrever resultado, não comitar, etc).
