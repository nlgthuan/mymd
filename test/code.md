# Code

```swift
import AppKit
// Greets someone
@MainActor
struct Greeter: Sendable {
    let name: String
    func greet(times: Int = 3) -> String {
        /* block comment */
        return "Hello, \(name)!" + String(repeating: "!", count: times * 0x2)
    }
}
```

```python
@dataclass
class Point:
    """A point."""
    x: float = 0.5  # inline comment
    def norm(self) -> float:
        return math.sqrt(self.x ** 2)
```

```bash
#!/usr/bin/env bash
for f in "$@"; do
  echo "file: ${f}" | grep -v '^#' > /dev/null
done
```

```diff
--- a/file.txt
+++ b/file.txt
@@ -1,2 +1,2 @@
-old line
+new line
 unchanged
```

```html
<!-- comment -->
<a href="https://x.com" class="btn">Link &amp; more</a>
```

```json
{"name": "mymd", "version": 1.5, "ok": true, "nothing": null}
```
