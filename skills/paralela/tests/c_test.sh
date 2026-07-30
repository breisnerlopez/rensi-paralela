#!/bin/bash
# c_test.sh — unit test autocontenido de WS-C (completitud del handoff, F3).
# Casos (§5.1-C):
#   1. handoff INCOMPLETO -> output contiene WARN  Y  exit == 0 (reporta pero NO bloquea).
#   2. done-ejemplo.md COMPLETO -> output contiene OK  Y  exit == 0.
#   3. archivo AUSENTE -> exit == 0 (no rompe el contrato de cierre).
# Sin deps externas (bash + grep). Imprime PASS/FAIL por caso; exit 0 solo si todos PASS.

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../handoff_complete.sh"
EJEMPLO="$HERE/../done-ejemplo.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/c_test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
report() { # <nombre> <cond 0=ok>
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi
}

# --- Caso 1: handoff incompleto (solo Resumen, sin campos gate ni resto de secciones) ---
INC="$TMP/handoff-incompleto.md"
printf '%s\n' '---' 'type: context-package' '---' '' '## Resumen' 'algo' > "$INC"
out1="$(bash "$SCRIPT" "$INC")"; ec1=$?
echo "$out1" | grep -q 'WARN'; has_warn=$?
[ "$has_warn" -eq 0 ] && [ "$ec1" -eq 0 ]
report "incompleto REPORTA warn (out contiene WARN=$([ $has_warn -eq 0 ] && echo si || echo no)) Y exit 0 (fue $ec1)" $?

# --- Caso 2: done-ejemplo.md completo -> OK y exit 0 ---
out2="$(bash "$SCRIPT" "$EJEMPLO")"; ec2=$?
echo "$out2" | grep -q 'OK'; has_ok=$?
[ "$has_ok" -eq 0 ] && [ "$ec2" -eq 0 ]
report "ejemplo completo -> OK (fue: '$out2') Y exit 0 (fue $ec2)" $?

# --- Caso 3: archivo ausente -> exit 0 igual ---
out3="$(bash "$SCRIPT" "$TMP/no-existe-$$.md")"; ec3=$?
[ "$ec3" -eq 0 ]
report "archivo ausente NO bloquea -> exit 0 (fue $ec3)" $?

echo "----"
if [ "$fails" -eq 0 ]; then echo "TODOS PASS"; exit 0; else echo "$fails FAIL"; exit 1; fi
