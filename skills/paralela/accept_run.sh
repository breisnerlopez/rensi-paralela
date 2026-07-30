#!/bin/bash
# accept_run.sh <ruta-worktree> <acceptance-script | --no-acceptance>
#
# WS-B · F2 — Validación-como-autoridad. Lo corre el ORQUESTADOR para validar la rama de una subtarea.
# La AUTORIDAD viene de que el <acceptance-script> lo AUTORA el ORQUESTADOR (como parte del PRP, F1) y
# vive FUERA del alcance del worker: el worker NO controla los bytes de la lógica de validación. Este
# script re-ejecuta esa lógica orquestador-autora con cwd=worktree, así prueba el CÓDIGO del worker
# (autoría-worker, ejecutado igual que en el gate CERRAR) con un TEST que el worker no pudo manipular.
#
# SEGURIDAD (precondición: repos confiables). Correr la validación EJECUTA el código del worktree bajo
# prueba (igual que el gate CERRAR corre la suite del repo sobre el merge). Mitigaciones: (a) la lógica
# de test es orquestador-autora, no worker → sin el bypass "PASS falso + payload"; (b) `timeout` acota
# cuelgues/DoS; (c) precondición repos-confiables. NO es un sandbox: no corras esto sobre worktrees de
# código NO confiable.
#
# Comportamiento (ver validation/acceptance-contract.md):
#   accept_run.sh <wt> <script>        -> corre <script> (autoría-orquestador) desde cwd=<wt> bajo
#                                          timeout; relaya PASS/FAIL+detalle; exit 0=PASS / 2=FAIL.
#                                          Exit anómalo, timeout, o 1ª línea incoherente => FAIL (fail-closed).
#   accept_run.sh <wt> --no-acceptance -> SKIP exit 0 (el PRP declaró no-acceptance; cae al CERRAR central).
#
# La RUTA del acceptance y la señal --no-acceptance las provee el ORQUESTADOR leyendo el PRP (fuente que
# controla), NUNCA un archivo dentro del worktree (sería escribible por el worker => auto-reporte).
set -uo pipefail

ACCEPT_TIMEOUT="${ACCEPT_TIMEOUT:-120}"   # segundos; acota cuelgue/DoS del acceptance

wt="${1:-}"
arg="${2:-}"

fail() { echo "FAIL"; [ -n "${1:-}" ] && echo "$1"; exit 2; }

# --- Validación de argumentos (fail-closed) ---
[ -n "$wt" ]  || fail "uso: accept_run.sh <ruta-worktree> <acceptance-script | --no-acceptance>"
[ -d "$wt" ]  || fail "worktree inexistente o no es directorio: $wt"
[ -n "$arg" ] || fail "falta 2º argumento: <acceptance-script> (autoría-orquestador) o --no-acceptance"

# --- Caso no-acceptance (subtarea exploratoria; el PRP lo declara) ---
if [ "$arg" = "--no-acceptance" ]; then
  echo "SKIP (no-acceptance)"
  echo "subtarea declarada no-acceptance en el PRP; F2 no aplica, cae al gate CERRAR central"
  exit 0
fi

# --- Caso acceptance orquestador-autora ---
acc="$arg"
[ -f "$acc" ] || fail "acceptance-script inexistente: $acc (lo autora el orquestador vía el PRP)"
# Absolutiza la ruta ANTES de cambiar cwd a $wt.
case "$acc" in /*) : ;; *) acc="$(cd "$(dirname "$acc")" && pwd)/$(basename "$acc")" ;; esac

# Se corre con bash explícito, cwd=worktree (rutas relativas resuelven contra la rama), bajo timeout.
if command -v timeout >/dev/null 2>&1; then
  out="$(cd "$wt" && timeout "$ACCEPT_TIMEOUT" bash "$acc" 2>&1)"; rc=$?
else
  out="$(cd "$wt" && bash "$acc" 2>&1)"; rc=$?
fi
first="$(printf '%s\n' "$out" | head -n1)"

# timeout(1) devuelve 124 al vencer -> FAIL fail-closed.
if [ "$rc" -eq 124 ]; then
  echo "FAIL"
  echo "acceptance excedió ACCEPT_TIMEOUT=${ACCEPT_TIMEOUT}s (tratado como FAIL fail-closed)"
  exit 2
fi

case "$rc" in
  0)
    # PASS reclamado: exigir coherencia de la 1ª línea (fail-closed).
    if [ "$first" = "PASS" ]; then
      printf '%s\n' "$out"
      exit 0
    fi
    echo "FAIL"
    echo "acceptance salió 0 pero su 1ª línea no fue PASS (incoherente, tratado como FAIL):"
    printf '%s\n' "$out" | head -n5
    exit 2
    ;;
  2)
    # FAIL declarado: relayar tal cual.
    printf '%s\n' "$out"
    exit 2
    ;;
  *)
    echo "FAIL"
    echo "acceptance terminó con exit anómalo=$rc (crash/exit≠0,2 => FAIL fail-closed):"
    printf '%s\n' "$out" | head -n5
    exit 2
    ;;
esac
