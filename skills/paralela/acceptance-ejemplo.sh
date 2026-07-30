#!/bin/bash
# acceptance-ejemplo.sh — acceptance.sh de MUESTRA que PASA.
# Ejemplo de subtarea: "implementar sumar() correcta". Aquí el 'trabajo' es correcto,
# así que el acceptance verifica el comportamiento y termina en PASS (exit 0, 1ª línea PASS).
#
# Contrato (validation/acceptance-contract.md): 1ª línea PASS|FAIL, hasta 5 líneas detalle, exit 0=PASS/2=FAIL.
# Se corre desde cwd = raíz del worktree. Este ejemplo es autocontenido (define su propio SUT).
set -uo pipefail

# --- SUT (system under test): la implementación que la subtarea "entregó" ---
sumar() { echo $(( $1 + $2 )); }

# --- Verificación ---
got="$(sumar 2 3)"
want=5

if [ "$got" = "$want" ]; then
  echo "PASS"
  echo "sumar(2,3) = $got (esperado $want)"
  exit 0
else
  echo "FAIL"
  echo "sumar(2,3) = $got (esperado $want)"
  exit 2
fi
