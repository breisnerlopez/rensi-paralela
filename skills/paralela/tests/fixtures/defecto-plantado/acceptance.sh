#!/bin/bash
# acceptance.sh (caso DEFECTO PLANTADO) — verifica el trabajo real entregado (sumar.sh).
# El worker reportó la subtarea como "hecho"; este acceptance, re-corrido por el orquestador,
# ejercita el código REAL y DEBE terminar en FAIL (exit 2) porque sumar.sh tiene un bug.
# Demuestra la tesis F2: la verdad es la validación, no el auto-reporte.
#
# Contrato: 1ª línea PASS|FAIL, hasta 5 líneas detalle, exit 0=PASS/2=FAIL. cwd = raíz del worktree.
set -uo pipefail

# shellcheck source=/dev/null
source "./sumar.sh" || { echo "FAIL"; echo "no se pudo cargar sumar.sh"; exit 2; }

got="$(sumar 2 3)"
want=5

if [ "$got" = "$want" ]; then
  echo "PASS"
  echo "sumar(2,3) = $got (esperado $want)"
  exit 0
else
  echo "FAIL"
  echo "sumar(2,3) = $got (esperado $want) — defecto atrapado por la validación, no por el auto-reporte"
  exit 2
fi
