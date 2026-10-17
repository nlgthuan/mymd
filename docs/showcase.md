# Orbital mechanics, briefly

A body in a **circular orbit** moves at speed $v = \sqrt{GM/r}$, where $G$ is the
gravitational constant. See the [vis-viva equation](https://en.wikipedia.org/wiki/Vis-viva_equation)
for the general case, or run `orbit --plot` to try it.

$$
T = 2\pi \sqrt{\frac{a^3}{GM}}
$$

```python
def period(a: float, mu: float = 3.986e14) -> float:
    """Orbital period in seconds (Earth by default)."""
    return 2 * math.pi * math.sqrt(a ** 3 / mu)
```

| Orbit | Altitude   | Period   |
|-------|-----------:|---------:|
| LEO   | 400 km     | 92 min   |
| GEO   | 35 786 km  | 23.9 h   |

- [x] Kepler's three laws
- [ ] Hohmann transfers
  - Δv budget for $\text{LEO} \to \text{GEO}$

> Everything is relative, except for the speed of light.
