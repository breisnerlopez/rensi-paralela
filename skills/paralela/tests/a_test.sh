#!/bin/bash
# a_test.sh — unit test autocontenido de WS-A (PRP layer).
# Ejercita prp_lint.sh: rechaza sin '## Criterio de aceptación', sin '## Contexto necesario',
# y un PRP gigante; ACEPTA el PRP-ejemplo.md LEAN. Imprime PASS/FAIL por caso.
# exit 0 solo si TODOS los casos pasan. Sin deps externas (bash + grep + python3 stdlib).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRP_DIR="$SCRIPT_DIR/.."
LINT="$PRP_DIR/prp_lint.sh"
EJEMPLO="$PRP_DIR/PRP-ejemplo.md"

TMP="${TMPDIR:-/tmp}"
mkdir -p "$TMP"
WORK="$(mktemp -d "$TMP/a_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

failures=0

# assert_exit <esperado> <caso> -- corre el linter y compara exit code
assert_exit() {
  local expected="$1" name="$2" file="$3"
  local out rc
  out="$(bash "$LINT" "$file" 2>&1)"; rc=$?
  if [[ "$rc" == "$expected" ]]; then
    echo "PASS: $name (exit $rc)"
  else
    echo "FAIL: $name (esperado exit $expected, obtuvo $rc)"
    echo "----- salida linter -----"
    echo "$out" | sed 's/^/    /'
    echo "-------------------------"
    failures=$((failures + 1))
  fi
}

# Base LEAN válido reutilizable para construir casos negativos quitando una sección.
write_base() {
  cat > "$1" <<'EOF'
# PRP-base: caso de prueba

## Objetivo
Hacer X observable.

## Archivos
- `src/x.py` [editar]

## Símbolos
- `x() -> None` en `src/x.py:1`

## Contexto necesario
- Contrato: `src/base.py:Base`.

## Criterio de aceptación
acceptance: acceptance.sh
EOF
}

# Caso 1: rechaza PRP sin '## Criterio de aceptación'
C1="$WORK/no-criterio.md"
write_base "$C1"
python3 - "$C1" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().splitlines(keepends=True)
out = []
skip = False
for ln in lines:
    if ln.startswith("## Criterio de aceptación"):
        skip = True
        continue
    if skip and ln.startswith("## "):
        skip = False
    if not skip:
        out.append(ln)
open(p, "w", encoding="utf-8").writelines(out)
PY
assert_exit 1 "rechaza PRP sin '## Criterio de aceptación'" "$C1"

# Caso 2: rechaza PRP sin '## Contexto necesario'
C2="$WORK/no-contexto.md"
write_base "$C2"
python3 - "$C2" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().splitlines(keepends=True)
out = []
skip = False
for ln in lines:
    if ln.startswith("## Contexto necesario"):
        skip = True
        continue
    if skip and ln.startswith("## "):
        skip = False
    if not skip:
        out.append(ln)
open(p, "w", encoding="utf-8").writelines(out)
PY
assert_exit 1 "rechaza PRP sin '## Contexto necesario'" "$C2"

# Caso 3: rechaza PRP gigante (> 400 líneas). Incluye TODAS las secciones a propósito:
# así el rechazo se debe SOLO a la penalización de tamaño (anti-dump), no a secciones faltantes.
C3="$WORK/gigante.md"
python3 - "$C3" <<'PY'
import sys
p = sys.argv[1]
parts = [
    "# PRP-gigante: dump que debe ser rechazado\n\n",
    "## Objetivo\nDump.\n\n",
    "## Archivos\n- `src/x.py`\n\n",
    "## Símbolos\n- `x()`\n\n",
    "## Contexto necesario\n",
]
# > 400 líneas de relleno bajo una sección válida
parts += ["- linea de contexto volcado numero %d\n" % i for i in range(1, 501)]
parts += ["\n## Criterio de aceptación\nacceptance: acceptance.sh\n"]
open(p, "w", encoding="utf-8").write("".join(parts))
PY
assert_exit 1 "rechaza PRP gigante (>400 líneas, anti-dump)" "$C3"

# Caso 4: ACEPTA el PRP-ejemplo.md LEAN válido
assert_exit 0 "ACEPTA PRP-ejemplo.md LEAN válido" "$EJEMPLO"

echo "----------------------------------------"
if (( failures == 0 )); then
  echo "TODOS PASS (4/4)"
  exit 0
else
  echo "$failures caso(s) en FAIL"
  exit 1
fi
