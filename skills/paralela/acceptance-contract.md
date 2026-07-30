# Convención de aceptación (WS-B · F2 — Validación-como-autoridad)

**Tesis F2:** en paralela un worker puede reportar "hecho" sin que sea verdad. La VERDAD no es el
auto-reporte del worker: es un `acceptance` **de autoría del ORQUESTADOR** (redactado como parte del PRP,
F1) **re-corrido por el ORQUESTADOR** contra la rama de esa subtarea. El worker **no controla los bytes
de la lógica de validación** — solo aporta el CÓDIGO bajo prueba. Autoridad > auto-reporte.

## Quién autora el acceptance (núcleo de la autoridad)

El `acceptance.sh` lo **redacta el orquestador como parte del PRP** (subagente scout barato), **no el
worker que hace el trabajo ni el humano**. Vive **fuera del alcance de escritura del worker**: en una ruta
orquestador-EXCLUSIVA `$ORCH/acceptance/<id>.sh`, **NO** en el buzón del worker `$ORCH/<id>/` ni en su
worktree (ambos escribibles por el worker → podría sobreescribir el "test canónico" con un `echo PASS` +
payload). El orquestador lo re-materializa fresco desde su copia del PRP justo antes de correrlo. Así el
criterio de verdad es **independiente de quien lo cumple**: si el worker deja el trabajo mal, el
acceptance —que él no escribió ni puede tocar— lo delata.

> **Por qué no vive en el worktree:** si el `acceptance.sh` fuera un archivo del worktree escrito/commiteado
> por el worker, el mismo agente que hace el trabajo escribiría el test que lo aprueba = auto-reporte, justo
> lo que F2 desconfía (un worker podría shipear un `echo PASS; exit 0` que finge validar). Por eso el
> orquestador corre **su propia copia canónica** (del PRP), no la del worktree.

## Contrato del `acceptance` (lo autora el orquestador; se corre contra el worktree)

- Ser bash: `#!/bin/bash`.
- Imprimir en la **1ª línea** exactamente `PASS` o `FAIL` (sin prefijos ni adornos).
- Imprimir hasta **5 líneas** de detalle después (qué verificó, qué falló).
- Propagar exit code: **`exit 0` = PASS**, **`exit 2` = FAIL**.
- Ser determinista y autocontenido en su lógica: `accept_run.sh` lo corre desde `cwd = raíz del worktree`,
  así ejercita el **código del worker** (p.ej. `source ./sumar.sh`) con un test que el worker no manipuló.
  Sin red ni deps externas más allá de lo que la subtarea ya usa.

Regla de coherencia (fail-closed): 1ª línea y exit deben concordar (`PASS`↔0, `FAIL`↔2). Si el
`acceptance` sale con un exit anómalo (crash, `exit 1`), **excede el timeout**, o su 1ª línea no concuerda
con su exit, el orquestador lo trata como **FAIL** — un acceptance que no puede afirmar PASS limpiamente
no pasa.

## Cómo lo invoca el orquestador

`accept_run.sh <ruta-worktree> <acceptance-script | --no-acceptance>`:

- `<acceptance-script>` = la RUTA (orquestador-side) del acceptance autorado en el PRP. `accept_run` lo
  corre bajo `timeout` (`ACCEPT_TIMEOUT`, def. 120s) con `cwd=worktree`, relaya `PASS`/`FAIL` + detalle,
  propaga exit `0`/`2` (anómalo/timeout/incoherente → FAIL).
- `--no-acceptance` = la subtarea es exploratoria/diseño sin PASS/FAIL (ver fallback). → `SKIP` exit 0.

Tanto la RUTA del acceptance como la señal `--no-acceptance` las provee el orquestador **leyendo el PRP**
(fuente que controla), NUNCA un archivo dentro del worktree (sería escribible por el worker).

## Seguridad (precondición: repos confiables)

Correr el acceptance **ejecuta el código del worktree bajo prueba** — igual que el gate CERRAR central
corre la suite del repo sobre el merge. `accept_run` **no es un sandbox**. Mitigaciones: (a) la **lógica
de test es autoría-orquestador**, no worker → no hay bypass "PASS falso + payload" vía el propio script;
(b) `timeout` acota cuelgues/DoS; (c) la precondición dura de paralela (**repos confiables**, worker sin
aislamiento fuerte, aceptada de forma informada) ya cubre "se ejecuta código del repo". **No** corras
`accept_run` sobre worktrees de código no confiable.

## Fallback: `no-acceptance` (tareas sin PASS/FAIL claro)

Tareas **exploratorias / de diseño / de investigación** sin un criterio PASS/FAIL ejecutable NO llevan
acceptance. En ese caso el **PRP declara** `acceptance: no-acceptance`; el orquestador pasa
`--no-acceptance` a `accept_run` y F2 **no aplica** a esa subtarea: cae al **gate CERRAR central** como
hoy y **no bloquea** la integración.

Matriz de decisión que aplica el orquestador vía `accept_run.sh`:

| 2º argumento             | Significado (del PRP)            | Resultado                | exit |
|--------------------------|---------------------------------|--------------------------|------|
| `<acceptance-script>`    | criterio ejecutable autorado    | Re-corre → `PASS`/`FAIL` | 0/2  |
| `--no-acceptance`        | subtarea exploratoria           | `SKIP (no-acceptance)`   | 0    |
| (ninguno)                | —                               | `FAIL` (validación omitida) | 2 |

La última fila es el núcleo de la autoridad: no se puede **omitir** la validación y que eso cuente como
aprobado — el orquestador debe declarar explícitamente el criterio o el `no-acceptance`.
