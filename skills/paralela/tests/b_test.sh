#!/bin/bash
# b_test.sh — unit test de WS-B (Validación-como-autoridad). Autocontenido: bash + grep + python3 stdlib.
# Ejercita accept_run.sh con la firma <worktree> <acceptance-script|--no-acceptance>. Caso central
# (§5.1-B): atrapa un DEFECTO PLANTADO que el worker reporta como "hecho" — y lo hace con un acceptance
# de AUTORÍA-ORQUESTADOR (fuera del worktree), no uno que el worker pudo escribir. Imprime PASS/FAIL por
# caso; exit 0 solo si TODOS pasan.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAL="$SELF/.."
FIX="$SELF/fixtures"
ACCEPT_RUN="$VAL/accept_run.sh"

SCRATCH="${TMPDIR:-/tmp}/b_test.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

fails=0

# run_case <nombre> <1ª-línea-esperada> <exit-esperado> -- <args de accept_run.sh...>
run_case() {
  local name="$1" exp_first="$2" exp_exit="$3"; shift 3
  [ "${1:-}" = "--" ] && shift
  local out rc first
  out="$(bash "$ACCEPT_RUN" "$@" 2>&1)"; rc=$?
  first="$(printf '%s\n' "$out" | head -n1)"
  if [ "$first" = "$exp_first" ] && [ "$rc" -eq "$exp_exit" ]; then
    echo "PASS: $name (1ª='$first' exit=$rc)"
  else
    echo "FAIL: $name — esperado 1ª='$exp_first' exit=$exp_exit; obtuvo 1ª='$first' exit=$rc"
    printf '      salida: %s\n' "$out" | head -n6
    fails=$((fails+1))
  fi
}

# nuevo worktree falso vacío
mk_wt() { local d; d="$(mktemp -d "$SCRATCH/wt.XXXXXX")"; printf '%s' "$d"; }

# ---------------------------------------------------------------------------
# CASO CENTRAL (§5.1-B): defecto plantado. El worktree solo trae el CÓDIGO del worker (sumar.sh, con bug).
# El acceptance es AUTORÍA-ORQUESTADOR y vive FUERA del worktree ($VAL/defecto-plantado/acceptance.sh):
# el worker no lo controla. accept_run lo corre contra el código del worktree y ATRAPA el defecto.
# ---------------------------------------------------------------------------
WT_BUG="$(mk_wt)"
cp "$FIX/defecto-plantado/sumar.sh" "$WT_BUG/sumar.sh"   # solo el código-worker, NO el acceptance
run_case "defecto-plantado -> FAIL (test autoría-orquestador atrapa el bug)" "FAIL" 2 -- \
  "$WT_BUG" "$FIX/defecto-plantado/acceptance.sh"

# ---------------------------------------------------------------------------
# CASO PASS: acceptance-ejemplo (autocontenido, autoría-orquestador) -> PASS exit 0.
# ---------------------------------------------------------------------------
WT_OK="$(mk_wt)"
run_case "acceptance correcto -> PASS" "PASS" 0 -- "$WT_OK" "$VAL/acceptance-ejemplo.sh"

# ---------------------------------------------------------------------------
# CASO no-acceptance: 2º arg = --no-acceptance -> SKIP exit 0.
# ---------------------------------------------------------------------------
WT_NOACC="$(mk_wt)"
run_case "no-acceptance declarado -> SKIP" "SKIP (no-acceptance)" 0 -- "$WT_NOACC" --no-acceptance

# ---------------------------------------------------------------------------
# CASO falta el 2º arg (ni script ni --no-acceptance) -> FAIL exit 2 (fail-closed: no se omite validación).
# ---------------------------------------------------------------------------
WT_MISS="$(mk_wt)"
run_case "sin 2º argumento -> FAIL (no se omite validación)" "FAIL" 2 -- "$WT_MISS"

# ---------------------------------------------------------------------------
# CASO script inexistente -> FAIL exit 2.
# ---------------------------------------------------------------------------
WT_X="$(mk_wt)"
run_case "acceptance-script inexistente -> FAIL" "FAIL" 2 -- "$WT_X" "$SCRATCH/no-existe.sh"

# ---------------------------------------------------------------------------
# EXTRA (fail-closed): acceptance con exit anómalo (exit 1) -> tratado como FAIL exit 2.
# ---------------------------------------------------------------------------
WT_ANOM="$(mk_wt)"
python3 - "$SCRATCH/anom.sh" <<'PY'
import sys
open(sys.argv[1], "w").write("#!/bin/bash\necho PASS\nexit 1\n")
PY
run_case "exit anómalo (0≠rc≠2) -> FAIL fail-closed" "FAIL" 2 -- "$WT_ANOM" "$SCRATCH/anom.sh"

# ---------------------------------------------------------------------------
# EXTRA (coherencia): acceptance sale 0 pero 1ª línea FAIL -> FAIL exit 2.
# ---------------------------------------------------------------------------
WT_INCO="$(mk_wt)"
python3 - "$SCRATCH/inco.sh" <<'PY'
import sys
open(sys.argv[1], "w").write("#!/bin/bash\necho FAIL\nexit 0\n")
PY
run_case "exit 0 con 1ª línea FAIL -> FAIL fail-closed" "FAIL" 2 -- "$WT_INCO" "$SCRATCH/inco.sh"

# ---------------------------------------------------------------------------
# EXTRA (timeout/DoS): acceptance que cuelga -> FAIL exit 2 bajo ACCEPT_TIMEOUT corto.
# ---------------------------------------------------------------------------
WT_TO="$(mk_wt)"
python3 - "$SCRATCH/hang.sh" <<'PY'
import sys
open(sys.argv[1], "w").write("#!/bin/bash\nsleep 5\necho PASS\n")
PY
if command -v timeout >/dev/null 2>&1; then
  to_out="$(ACCEPT_TIMEOUT=1 bash "$ACCEPT_RUN" "$WT_TO" "$SCRATCH/hang.sh" 2>&1)"; to_rc=$?
  to_first="$(printf '%s\n' "$to_out" | head -n1)"
  if [ "$to_first" = "FAIL" ] && [ "$to_rc" -eq 2 ]; then
    echo "PASS: timeout/DoS -> FAIL fail-closed (1ª='$to_first' exit=$to_rc)"
  else
    echo "FAIL: timeout/DoS — esperado 1ª='FAIL' exit=2; obtuvo 1ª='$to_first' exit=$to_rc"
    fails=$((fails+1))
  fi
else
  echo "SKIP: timeout/DoS (no hay 'timeout' en este entorno)"
fi

# ---------------------------------------------------------------------------
# EXTRA: worktree inexistente -> FAIL exit 2.
# ---------------------------------------------------------------------------
run_case "worktree inexistente -> FAIL" "FAIL" 2 -- "$SCRATCH/no-existe-xyz" "$VAL/acceptance-ejemplo.sh"

# ---------------------------------------------------------------------------
echo "-----------------------------------------"
if [ "$fails" -eq 0 ]; then
  echo "TODOS PASS"
  exit 0
else
  echo "HAY FALLOS: $fails caso(s)"
  exit 1
fi
