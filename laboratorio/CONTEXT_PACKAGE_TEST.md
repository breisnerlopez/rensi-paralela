# Test empírico: handoff ESTRUCTURADO vs TEXTO LIBRE (¿respeta decisiones no-obvias?)

Contenido idéntico (mkRgx, bail, prefijo gw4). Solo cambia el formato. Score = decisiones respetadas /3. 'REGRESO-a-default' = usó Core.id/throw ignorando el handoff.

| rep | estructurado /3 | texto-libre /3 |
|---|---|---|
| 1 | 2 mkRgx✓ bail✓ gw4✗ REGRESO-a-default | 3 mkRgx✓ bail✓ gw4✓ REGRESO-a-default |
| 2 | 3 mkRgx✓ bail✓ gw4✓ REGRESO-a-default | 3 mkRgx✓ bail✓ gw4✓ |
| 3 | 3 mkRgx✓ bail✓ gw4✓ REGRESO-a-default | 3 mkRgx✓ bail✓ gw4✓ |
| 4 | 3 mkRgx✓ bail✓ gw4✓ REGRESO-a-default | 3 mkRgx✓ bail✓ gw4✓ |

**Promedio decisiones respetadas:** estructurado=2.75/3 | texto-libre=3.00/3

_Si son ~iguales => el formato estructurado NO mejora la continuidad sobre texto libre (el valor del schema es auditoría/máquina, no que el LLM 'entienda mejor'). Si estructurado > libre => el schema sí ayuda a preservar decisiones._
