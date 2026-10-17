Vendored [SwiftMath](https://github.com/mgriebling/SwiftMath) 1.7.3 (commit fa8244e), MIT.

- `Sources/` — upstream `Sources/SwiftMath/**/*.swift`, flattened, unmodified,
  plus two files of ours: `Bundle+module.swift` (replaces SwiftPM's generated
  resource accessor) and `MathAttachment.swift` (renders TeX to a bitmap and
  reports its descent for baseline alignment).
- Built as a static library by the top-level Makefile with plain `swiftc`.
- `mathFonts.bundle/` — only Latin Modern Math (GUST font license); the other
  upstream fonts are dropped to keep the app small.
