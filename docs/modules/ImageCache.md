# ImageCache

Remote image loading with memory + disk caching, prefetching, and off-main decoding.

- **Package:** `GenericArch-ImageCache` — **extracted repo**, semver-tagged (CLAUDE.md §4.2)
- **Used by:** any feature displaying a remote image, through a protocol in `Core` that the app
  conforms this package to.
- **Depends on: nothing** — not `Core`, and deliberately not `NetworkKit` either, so it stays
  reusable in a product with a different transport. Same standalone constraint as
  [NetworkKit](NetworkKit.md).
- **When to read this:** showing a remote image, sizing a cache, prefetching a list, or debugging
  scroll stutter in an image-heavy view.

---

## Why this exists instead of `AsyncImage`

`AsyncImage` has no cache. It refetches on every appearance, which in a scrolling list means the
same image is downloaded and decoded repeatedly. It also decodes at full source resolution on the
main actor — a 4000px JPEG in a 60pt avatar is ~64 MB resident and a guaranteed hitch.

Use `AsyncImage` only for a one-off, non-scrolling, known-small image.

---

## The protocol

```swift
public protocol ImageCaching: Sendable {
    /// Decoded and downsampled to `size`. Cancels on task cancellation.
    func image(for url: URL, size: CGSize, priority: ImagePriority) async throws -> ImageData
    func prefetch(_ urls: [URL], size: CGSize) async
    func cancelPrefetch(_ urls: [URL]) async
    func evict(_ url: URL) async
    func evictAll() async
}
```

`ImageData` is **this package's** type, not `UIImage`/`NSImage` — CLAUDE.md §2.2. The SwiftUI view
in DesignSystem converts at the edge.

Because this package is standalone, the protocol above is declared **here**, and the mirrored
`ImageCaching` capability lives in `Core`. One small conformance in the app bridges them, the same
way a vendor wrapper does (§7). Features import `Core` and never see this package.

---

## Two tiers

| Tier | Holds | Bounded by | Cleared |
|---|---|---|---|
| Memory | decoded, downsampled images | `NSCache` cost limit, **and** a hard byte cap | memory warning, backgrounding |
| Disk | original encoded bytes | size cap + LRU eviction | age-based sweep on launch |

- Memory caches the **decoded, display-sized** image; disk caches the **original bytes**. Caching
  decoded data on disk wastes space and pins one display size.
- Disk lives in `Caches/`, never `Documents/` — `Documents/` is backed up and counts against iCloud
  quota ([StorageKit.md](StorageKit.md)).
- **Both caps are mandatory at construction.** An unbounded image cache is a crash on an older
  device, and it will be the top crash.

```swift
ImageCache(memoryLimit: .megabytes(50),
           diskLimit: .megabytes(200),
           maxAge: .days(7))
```

---

## Downsample, don't resize

Decode at the size you will display. Resizing after a full decode has already paid the memory cost.

```swift
// The whole point: never materialize the full-resolution bitmap
let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * scale,
    kCGImageSourceShouldCacheImmediately: true,   // decode here, off-main — not at draw time
]
```

`kCGImageSourceShouldCacheImmediately` is the one that matters for scrolling: without it, decode is
deferred to the render pass, on the main thread, exactly when you can't afford it.

Cache keyed by **URL + target size**. The same URL at avatar size and hero size are two entries.

---

## Concurrency

- The cache is an `actor`. Never `@MainActor`.
- **Single-flight per key:** two rows requesting the same URL join one in-flight task, they don't
  start two. Same shape as NetworkKit's token refresh.
- Every request honors cancellation — a row scrolled off-screen must stop its work, or a fast
  scroll queues hundreds of dead decodes.
- Decode runs off the main actor. Always.

---

## In views

Features never call the protocol directly — they use the DesignSystem component, which handles
placeholder, failure, and transition consistently:

```swift
RemoteImage(url: item.imageURL, size: .avatar)      // DesignSystem
```

The component renders `ContentState`'s shape: skeleton while loading, a localized failure
placeholder on error, no layout shift when the image arrives (reserve the frame up front).

### Prefetching

For a list, prefetch a window ahead of the visible range and cancel behind it:

```swift
.onAppear { Task { await cache.prefetch(upcomingURLs, size: .thumbnail) } }
.onDisappear { Task { await cache.cancelPrefetch(passedURLs) } }
```

Prefetching without cancelling is worse than not prefetching — it saturates the connection with
work for rows the user already scrolled past.

---

## Transport

This package does its own fetching through a small injected `ImageFetching` protocol it declares
itself, defaulting to a plain `URLSession`. It does **not** depend on NetworkKit — that keeps both
independently reusable, at the cost of not sharing NetworkKit's middleware. If a product needs
authenticated image URLs, inject an `ImageFetching` implementation backed by NetworkKit from the
composition root.

Disk caching is likewise self-contained — its own scoped directory under `Caches/`, no
`StorageKit`.

---

## Testing

`MockImageCache` ships in the package, returning fixture images synchronously — so feature tests
and previews never touch the network or the disk.

Contract tests (CLAUDE.md §9) assert on the real implementation:

- Two concurrent requests for one key produce **one** fetch.
- A cancelled request leaves no partial entry.
- Exceeding the byte cap evicts least-recently-used, and stays under the cap.
- A cache hit returns without touching `ImageFetching` at all.

That last one is the regression that silently destroys performance while every test still passes.
