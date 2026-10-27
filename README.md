# skip-umbrella-viewbuilder-repro

A minimal reproduction for a Skip Lite (transpiled mode) bug. If a Skip module's views reach the
consumer only through a **non-Skip umbrella target** (a plain SwiftPM target whose only content is
`@_exported import Inner`), those views are **silently dropped inside `@ViewBuilder`** in the
generated Kotlin.

- A bare `Badge()` is emitted as a constructor statement with no `.Compose(composectx)`. The view
  is built and then thrown away.
- `Card { Text("a"); Text("b") }` is not recognized as taking a `@ViewBuilder` closure. Its closure
  becomes a plain Kotlin lambda (`{ -> Text("a"); Text("b") }`), which only yields its last
  expression, and `Card` itself is not composed either.

The Swift compiles, the transpile succeeds, and (with the package layout used here) the Kotlin
compiles too. The only signal is a skipstone warning per dropped call: *"Skip is unable to match
this API call to determine whether it results in a View"*.

## Layout

| Target | Skip module? | Contents |
|---|---|---|
| `Inner` | yes (`Sources/Inner/Skip/skip.yml`, `mode: 'transpiled'`) | `public struct Badge: View`, `public struct Card<Content: View>: View` with `init(@ViewBuilder content:)` |
| `InnerUmbrella` | **no** (no `skip.yml`, no plugin) | one file: `@_exported import Inner` |
| `UsesUmbrella` | yes | `DemoView` that does `import InnerUmbrella`. **Broken.** |
| `UsesDirect` | yes | the same `DemoView`, but `import Inner`. Control, **works**. |

Both `DemoView.swift` files are identical apart from the import:

```swift
import InnerUmbrella   // UsesDirect: `import Inner`
import SwiftUI

public struct DemoView: View {
    public init() {
    }

    public var body: some View {
        VStack {
            Text("Header")
            Badge()
            Card {
                Text("a")
                Text("b")
            }
        }
    }
}
```

`Inner`'s `skip.yml` sets `package: 'inner.umbrella'`. That mirrors the real project this was
found in: the Kotlin package is named after the umbrella, so a consumer's `import InnerUmbrella`
(which skipstone turns into `import inner.umbrella.*`) resolves on the Android side. Without the
override, we expect the Gradle build to fail with unresolved references instead of dropping the views silently.
(That last point is our expectation; the Gradle/Android build itself has not been run for this
repro.) The root cause is the same either way.

Pinned versions: skip 1.9.19, skip-foundation 1.4.8, skip-ui 1.64.0.

## Steps

### macOS (Xcode 26 / Swift 6.x) (not verified yet: the repro has so far only been run on Linux)

```sh
git clone https://github.com/daniboybye/skip-umbrella-viewbuilder-repro   # or: git clone skip-umbrella-viewbuilder-repro.bundle
cd skip-umbrella-viewbuilder-repro

# Transpile only (no Android toolchain needed):
swift package --allow-writing-to-package-directory skip-transpile

# Or a normal build, which runs the skipstone build plugin for each Skip target:
swift build
```

Then compare:

```sh
OUT=.build/plugins/outputs/skip-umbrella-viewbuilder-repro
diff -u $OUT/UsesDirect/destination/skipstone/UsesDirect/src/main/kotlin/uses/direct/DemoView.kt \
        $OUT/UsesUmbrella/destination/skipstone/UsesUmbrella/src/main/kotlin/uses/umbrella/DemoView.kt
```

(For an Xcode build the outputs are under DerivedData:
`…/skip-umbrella-viewbuilder-repro.output/<Target>/skipstone/xcode-<config>-<platform>/`.)

### Linux (verified on Ubuntu 24.04, Swift 6.3.3)

```sh
swift package --allow-writing-to-package-directory skip-transpile   # works, ~20 s
```

The prebuilt `skip-linux.zip` 1.9.19 transpiled every module, including SkipUI, without crashing.
`swift build` on Linux runs the skipstone plugin but then fails compiling SkipUI's Swift sources
(`no such module 'CoreGraphics'`), so use the `skip-transpile` command plugin on Linux.

## Expected vs actual

Expected: `UsesUmbrella` produces the same body as `UsesDirect`. Actual output from the Linux run
above:

**`UsesDirect` (`import Inner`): correct**

```kotlin
override fun body(): View {
    return ComposeBuilder { composectx: ComposeContext ->
        VStack { ->
            ComposeBuilder { composectx: ComposeContext ->
                Text(LocalizedStringKey(stringLiteral = "Header")).Compose(composectx)
                Badge().Compose(composectx)
                Card { ->
                    ComposeBuilder { composectx: ComposeContext ->
                        Text(LocalizedStringKey(stringLiteral = "a")).Compose(composectx)
                        Text(LocalizedStringKey(stringLiteral = "b")).Compose(composectx)
                        ComposeResult.ok
                    }
                }.Compose(composectx)
                ComposeResult.ok
            }
        }.Compose(composectx)
    }
}
```

**`UsesUmbrella` (`import InnerUmbrella`): `Badge` and `Card` are never composed**

```kotlin
override fun body(): View {
    return ComposeBuilder { composectx: ComposeContext ->
        VStack { ->
            ComposeBuilder { composectx: ComposeContext ->
                Text(LocalizedStringKey(stringLiteral = "Header")).Compose(composectx)
                Badge()
                Card { ->
                    Text(LocalizedStringKey(stringLiteral = "a"))
                    Text(LocalizedStringKey(stringLiteral = "b"))
                }
                ComposeResult.ok
            }
        }.Compose(composectx)
    }
}
```

The transpile log contains only these two warnings for it, in between about 20 warnings from
SkipFoundation and SkipUI:

```
Sources/UsesUmbrella/DemoView.swift:11:13: warning: Skip is unable to match this API call to determine whether it results in a View. Consider adding additional type information
Sources/UsesUmbrella/DemoView.swift:12:13: warning: Skip is unable to match this API call to determine whether it results in a View. Consider adding additional type information
```

On an incremental `swift build`, where the module's sources are unchanged, the plugin does not
re-transpile, so the warning does not appear again.

## Why

The SkipPlugin walks *through* `InnerUmbrella` (it has no `skip.yml`, so it is skipped) and passes
`--link Inner` to skipstone, so `Inner`'s symbols are loaded. But skipstone never sees the
umbrella's source. `InnerUmbrella` is an unknown module name to it, and the edge
`InnerUmbrella re-exports Inner` is missing. When a file imports only `InnerUmbrella`,
`CodebaseInfo` treats `Inner`'s symbols as not visible, so the API calls are unmatched and the
SwiftUI transformer cannot tell they produce views. See the issue for details and a proposed fix.

## Workarounds

1. **Let only skipstone see the real module.** The iOS build is unaffected, because `#if SKIP` is
   false in Swift:
   ```swift
   import InnerUmbrella
   #if SKIP
   import Inner
   #endif
   ```
   Verified with this package: `Badge().Compose(composectx)` and `Card { … }.Compose(composectx)`
   are back. The only side effect is a duplicated `import inner.umbrella.*` line.
2. **Reach the view through a function in the consuming module** instead of a bare initializer:
   ```swift
   private func badge() -> some View { Badge() }
   // …in body:  badge()
   ```
   Verified with this package: it emits `badge().Compose(composectx)`. This is the workaround the
   real project uses. It does not help with `Card { … }` content: that closure is still a plain lambda.
3. Import the Skip module directly (`import Inner`) in Skip-transpiled code. This defeats the point
   of the umbrella.
