# Schema del handoff completo (WS-C · F3 Completitud — LINT/WARN, NO gate)

Cuando un worker cierra, emite un **handoff**: un único archivo markdown que combina el
paquete de contexto estructurado (para trazabilidad/continuidad) con los campos de cierre
del `done.json` del worker (para auditar el gate adversarial). F3 **reporta** (warn) lo que
falte; **nunca rechaza ni reabre** al worker (`handoff_complete.sh` sale **exit 0 siempre**).

## 1. Base reusada (NO se duplica aquí)
El handoff **reusa el schema de `context-package`** ya presente en el repo. La fuente de
verdad de la plantilla y del validador es:

- Plantilla: `skills/context-package/TEMPLATE.md`
- Validador de las 7 secciones + frontmatter: `skills/context-package/validate.sh`

De ahí salen los requisitos de:
- **Frontmatter** YAML delimitado por `---` en la 1ª línea, con `type: context-package`.
- Las **7 secciones** obligatorias (títulos `##`):
  `Resumen`, `Decisiones`, `Hallazgos`, `Riesgos`, `Pendientes`,
  `Para el siguiente agente`, `Referencias`.

## 2. Campos de cierre del worker (del `done.json`)
Además de lo anterior, el handoff incorpora los campos del contrato de cierre del worker
definido en `skills/worker-protocol/SKILL.md` (paso "Cierre"). El `done.json` original tiene:
`branch`, `summary`, `files`, `gate_veredicto`, `gate_refutacion`, `gate_resuelto`.

En el handoff estos campos viven en el **frontmatter** del propio archivo markdown (así un
solo archivo es autocontenido y validable). Campos que F3 chequea:

| Campo             | Significado                                                        |
|-------------------|-------------------------------------------------------------------|
| `branch`          | Rama/worktree donde quedó commiteado el trabajo.                  |
| `summary`         | Resumen de una línea (equivale al `summary` del done.json).       |
| `gate_veredicto`  | `aprobado` \| `refutado` — veredicto del retador.                 |
| `gate_refutacion` | Qué refutó el retador y cómo se resolvió (`sin hallazgos` si nada).|
| `gate_resuelto`   | `si` \| `no` — si la refutación quedó resuelta.                   |

> `files` ya está cubierto por el campo `files:` estándar del frontmatter de context-package,
> por eso `handoff_complete.sh` no lo exige por separado.

## 3. Qué acepta `handoff_complete.sh`
`handoff_complete.sh <archivo>` valida un **único** archivo markdown de handoff y comprueba:

1. Frontmatter presente (1ª línea `---`) y `type: context-package`.
2. Las **7 secciones** `##` de context-package.
3. Los **5 campos de cierre** en frontmatter: `branch`, `summary`, `gate_veredicto`,
   `gate_refutacion`, `gate_resuelto` (match por clave `^clave:`).

Salida y contrato de exit (**innegociable**):
- Si algo falta: imprime `WARN: falta <items...>` — **exit 0** igual (lint/warn, no bloquea).
- Si está completo: imprime `OK: completo` — **exit 0**.
- Si el archivo no existe: imprime `WARN: no existe <archivo>` — **exit 0** igual (no rompe
  el contrato de cierre del worker; solo el orquestador lo ve al supervisar).

## 4. Ejemplo válido
`handoff/done-ejemplo.md` es un handoff **completo** (pasa sin ningún `WARN`). Sirve de
plantilla concreta y de caso positivo para `tests/c_test.sh`.

## 5. Racional (por qué warn y no gate)
Un `done.json` delgado ≠ trabajo delgado. Rechazar/reabrir forzaría al worker a re-describir
trabajo ya commiteado = tokens sin mejora del resultado. Por eso F3 es **trazabilidad/monitoreo**:
el orquestador VE el `WARN` al supervisar y decide, pero el pipeline nunca se bloquea aquí.
