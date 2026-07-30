#!/bin/bash
# prp_lint.sh — valida un PRP (Parallel Requirements Package) LEAN.
# Objetivo: PRECISIÓN, no tokens. Un PRP debe ser LEAN (foco), NO un dump:
# se midió que volcar contexto grande BAJA la precisión → penalizamos PRPs gigantes.
#
# Uso:   prp_lint.sh <PRP.md>
# exit 0 = OK (LEAN + todas las secciones obligatorias)
# exit 1 = RECHAZADO (imprime qué faltó / por qué)
# exit 2 = error de uso (falta argumento / archivo inexistente)
set -euo pipefail

PRP="${1:-}"

if [[ -z "$PRP" ]]; then
  echo "ERROR: uso: $(basename "$0") <PRP.md>" >&2
  exit 2
fi
if [[ ! -f "$PRP" ]]; then
  echo "ERROR: archivo no existe: $PRP" >&2
  exit 2
fi

fail=0

# --- Secciones obligatorias (títulos EXACTOS, nivel '##') ---
# El PRP debe declarar SOLO el contexto que la subtarea usa (## Contexto necesario).
SECTIONS=(
  "## Objetivo"
  "## Archivos"
  "## Símbolos"
  "## Contexto necesario"
  "## Criterio de aceptación"
)

missing=()
for s in "${SECTIONS[@]}"; do
  # Línea que ES exactamente el encabezado (permite espacios finales), no un prefijo.
  if ! grep -qxE "${s}[[:space:]]*" "$PRP"; then
    missing+=("$s")
    fail=1
  fi
done

# --- Penalización de tamaño (anti-dump) ---
# Gigante := > 400 líneas  O  > 15000 chars.
MAX_LINES=400
MAX_CHARS=15000

LINES=$(wc -l < "$PRP" | tr -d '[:space:]')
# wc -m = caracteres (locale UTF-8); si el conteo de chars fallara, cae a bytes (wc -c).
CHARS=$(wc -m < "$PRP" 2>/dev/null | tr -d '[:space:]' || true)
if [[ -z "${CHARS:-}" ]]; then
  CHARS=$(wc -c < "$PRP" | tr -d '[:space:]')
fi

if (( LINES > MAX_LINES )); then
  echo "RECHAZADO: PRP gigante — ${LINES} líneas > ${MAX_LINES} (LEAN, no dump: el contexto grande baja la precisión)."
  fail=1
fi
if (( CHARS > MAX_CHARS )); then
  echo "RECHAZADO: PRP gigante — ${CHARS} chars > ${MAX_CHARS} (LEAN, no dump: declara SOLO el contexto que la subtarea usa)."
  fail=1
fi

# --- Reporte de secciones faltantes ---
if (( ${#missing[@]} > 0 )); then
  echo "RECHAZADO: faltan secciones obligatorias (títulos exactos, nivel '##'):"
  for m in "${missing[@]}"; do
    echo "  - ${m}"
  done
fi

if (( fail != 0 )); then
  exit 1
fi

echo "OK: ${PRP} pasa el linter (LEAN, ${LINES} líneas / ${CHARS} chars, todas las secciones presentes)."
exit 0
