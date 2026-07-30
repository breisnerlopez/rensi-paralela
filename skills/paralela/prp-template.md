<!--
Plantilla de PRP (Parallel Requirements Package) — un blueprint LEAN por subtarea.
Copia este archivo a PRP-<id>.md y rellena cada sección. Reglas:
  - LEAN, NO dump: se midió que volcar contexto grande BAJA la precisión.
  - Declara SOLO el contexto que ESTA subtarea usa (no todo el repo).
  - Mantén el PRP corto: prp_lint.sh RECHAZA > 400 líneas o > 15000 chars.
  - Los 5 títulos '##' de abajo son OBLIGATORIOS y EXACTOS (el linter los exige).
Borra estos comentarios al emitir el PRP real.
-->

# PRP-<id>: <título corto de la subtarea>

## Objetivo
<Qué debe lograr esta subtarea, en 1-3 frases. Resultado observable, no el "cómo".>

## Archivos
<Rutas EXACTAS que la subtarea crea o modifica (una por línea). Marca [nuevo] o [editar].>
- `ruta/al/archivo.ext` [editar] — <por qué>
- `ruta/al/nuevo.ext` [nuevo] — <por qué>

## Símbolos
<Funciones/clases/constantes/endpoints concretos a tocar o crear. Con firma si aplica.>
- `nombreFuncion(args) -> retorno` en `ruta/al/archivo.ext:LINEA`
- `CONSTANTE` en `ruta/config.ext`

## Contexto necesario
<SOLO lo que ESTA subtarea usa: contratos, tipos, invariantes, ejemplos mínimos.
NO pegues archivos enteros ni contexto de otras subtareas. Enlaza por ruta:símbolo.>
- Contrato/interfaz: `ruta:símbolo` — <qué garantiza>
- Invariante que respetar: <...>

## Criterio de aceptación
<Cómo se verifica el PASS. Lo AUTORA el orquestador/scout AQUÍ (no el worker), y el orquestador lo corre
con `accept_run.sh <worktree> <acceptance-script>` — su copia canónica orquestador-side, NO una del
worktree (ver validation/acceptance-contract.md). Una de estas formas:
  - un `acceptance.sh` autorado abajo (1ª línea PASS/FAIL, exit 0/2; corre desde cwd=worktree y ejercita
    el código de la subtarea, p.ej. `source ./archivo.sh`)
  - un criterio verificable no-test (comando/observación reproducible)
  - `acceptance: no-acceptance`  (subtarea exploratoria/diseño sin PASS/FAIL → cae al gate CERRAR)>
acceptance: acceptance.sh

```bash
#!/bin/bash
# acceptance.sh (autoría-orquestador) — verifica el resultado observable de ESTA subtarea.
set -uo pipefail
# <ejercita el código del worktree; imprime PASS|FAIL en la 1ª línea; exit 0=PASS / 2=FAIL>
```
