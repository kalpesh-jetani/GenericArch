# Performance

Launch budget and SwiftUI rendering. The two places these apps actually get slow.

- **When to read this:** before adding work to launch, when a list stutters, when a view rebuilds
  more than it should, or when anything feels slow and you're about to guess.
- **Rule zero:** measure before changing. Every technique below makes some code worse when applied
  without a profile.

---

## Part 1 — Launch

### The budget

| Phase | Budget | Measured by |
|---|---|---|
| Pre-main (dyld, static init) | < 200 ms | Instruments → App Launch |
| `main` → first frame | < 300 ms | `os_signpost` from `@main` to `onAppear` |
| **Total to interactive** | **< 500 ms** cold, on the oldest supported device | Both |

"Oldest supported device" means the oldest iPhone running iOS 17 — not the one on your desk. A
launch that's fine on current hardware and 1.4 s on the floor device is a regression nobody
measured.

### The tension with eager DI — resolve it deliberately

[DIKit.md](modules/DIKit.md) says *prefer eager construction*, and `DIContainerBuilder.build()`
constructs the whole graph before the first frame. That is a real launch cost, chosen on purpose:
it buys an immutable `Sendable` container with no locks and no runtime resolution failure.

**Keep it, with a rule:** a dependency may be constructed eagerly only if its `init` does no I/O,
no disk read, no `URLSession` creation with a background configuration, and no work proportional to
stored data.

Anything failing that test registers a **facade** — a cheap value that builds the real thing on
first `await`:

```swift
// ✅ eager: allocates, touches nothing
builder.register(HTTPClientKey.self, URLSessionHTTPClient(config: .default))

// ❌ eager: opens the store, replays migrations, blocks first frame
builder.register(EntityStoringKey.self, SQLiteStore(path: url))

// ✅ facade: the open happens on first use, off the launch path
builder.register(EntityStoringKey.self, LazyEntityStore { await SQLiteStore.open(url) })
```

Lazy construction is the one place a lock is permitted, with the CLAUDE.md §2.8 justification
comment.

### What else must stay off the launch path

- Font registration is on it by necessity ([FONTS.md](../.claude/notes/FONTS.md)) — keep it to the
  files actually used.
- No network call before first frame. A force-update check runs *after* first frame, gating the UI
  it already drew ([AppShell.md](modules/AppShell.md)).
- No `Bundle` resource enumeration, no JSON fixture loading, no keychain sweep.
- Analytics and crash SDK init are the classic offenders — initialize the wrapper, defer the
  vendor's own start to after first frame.

Add an `os_signpost` interval around launch and watch it in CI on a fixed simulator. A budget
nobody measures is a wish.

---

## Part 2 — SwiftUI rendering

This is where SwiftUI apps fail, and none of it is caught by a compiler or a unit test.

### Body is called constantly — that is normal

A `body` re-evaluation is cheap. The cost is what it *does*: heavy computation, formatter
allocation, sorting, or forcing children to rebuild. Never optimize by trying to make `body` run
less often; optimize what it does when it runs.

```swift
// ❌ allocates a formatter on every body call, of every row
Text(formatter().string(from: item.date))

// ✅ FormatStyle, resolved once, and correct for the locale
Text(item.date, format: .dateTime.day().month())
```

### `@Observable` granularity is the main lever

`@Observable` tracks **per-property**: a view re-renders only for the properties its `body` actually
reads. That's the win — and it's lost by reading a coarse property.

```swift
// ❌ reads the whole array — every row re-renders when any item changes
ForEach(model.items) { ItemRow(item: $0) }

// ✅ row observes only its own item; a single mutation touches one row
ForEach(model.itemIDs, id: \.self) { id in ItemRow(item: model.item(id)) }
```

Keep view models narrow. One `@Observable` holding an entire screen's state means every field edit
re-renders the screen.

### `AnyView` erases identity — avoid it

`AnyView` prevents SwiftUI from diffing structurally, so it rebuilds the subtree instead of updating
it. Use `@ViewBuilder`, a generic parameter, or a `switch` returning concrete branches.

```swift
// ❌
var icon: AnyView { isOn ? AnyView(OnIcon()) : AnyView(OffIcon()) }

// ✅
@ViewBuilder var icon: some View { if isOn { OnIcon() } else { OffIcon() } }
```

The one legitimate use is a heterogeneous collection built at runtime — rare, and worth a comment.

### Lists

- **Stable identity.** `id: \.self` on a mutable value type re-creates rows on every change. Use a
  real identifier.
- `LazyVStack` inside `ScrollView` for custom layouts; plain `List` where a list is what you mean —
  `List` recycles, a non-lazy `VStack` builds every row up front.
- Fixed row heights where possible. Self-sizing rows force a second layout pass on every scroll.
- **Images are the usual culprit**, not the list — decode off-main and size to the display size
  ([ImageCache.md](modules/ImageCache.md)).
- Never do async work in a row's `body`. Kick it off in `.task(id:)`, which cancels on recycle.

### Equatable views

When a view is expensive and its inputs rarely change, `EquatableView` (or `.equatable()`) lets
SwiftUI skip the body entirely. Reach for it **after** profiling — a wrong `==` produces stale UI,
which is worse than a slow one.

### Structural identity

`if`/`else` creates *different* views; a `.opacity` modifier keeps one. Switching between branches
destroys state and restarts animations. When a transition looks like it "resets", this is why.

---

## Diagnosing

| Symptom | Tool | Look for |
|---|---|---|
| Scroll stutter | Instruments → Animation Hitches | hitch time per frame; commit phase vs. render |
| Unexplained rebuilds | `Self._printChanges()` in `body` | which property triggered it |
| Slow launch | Instruments → App Launch | pre-main vs. post-main split |
| Memory growth | Instruments → Allocations, Leaks | retained `Task`s, closure cycles |
| Main-thread block | Instruments → Time Profiler | any I/O or decode on the main actor |

`Self._printChanges()` is the fastest way to answer "why did this redraw" — call it in `body`,
temporarily, and remove it before commit.

### Memory

`@Observable` classes are reference types held by views. Two rules cover most leaks:

- A stored `Task` must be cancelled in `deinit` or on disappear — CLAUDE.md §6 already requires it;
  the leak is what happens when it isn't.
- Closures escaping into a service capture `self` strongly. Prefer passing values; use
  `[weak self]` where a closure genuinely outlives the view model.

---

## Budgets to hold

- Cold launch to interactive: **< 500 ms** on the oldest supported device
- Scroll: **zero** hitches over 250 ms in a 10-second scroll of a 1000-item list
- Memory: no unbounded growth over a 5-minute navigation loop
- Main thread: no I/O, no image decode, no JSON parse

Check these before a release, not after a complaint.
