#!/bin/bash
# diff-risk.sh — ELEVADOR mecanico de riesgo para /paralela (condicion del auditor).
# Clasifica el diff de una rama por PATRONES DE RUTA para FORZAR el auditor central
# cuando toca security/data/config-prod.
#
# HONESTIDAD (leelo): es CIEGO AL CONTENIDO (denylist de rutas) -> cubre "rutas obvias",
# NUNCA es garantia. Un riesgo de contenido en ruta inocua (auth en session.ts, secreto
# en constants.ts, DELETE sin WHERE en db.ts, dependencia maliciosa) NO lo ve este script:
# lo atrapa el gate CERRAR central de CONTENIDO, que lee el diff integrado completo.
# Por eso este script es un ELEVADOR (ruta->high fuerza auditor), NO un FILTRO
# (RISK=normal NO exime del CERRAR central).
#
# FALLA-CERRADO: ante cualquier error, refs invalidas o diff vacio/sospechoso -> RISK=high.
#
# uso: diff-risk.sh <base_ref> <head_ref>
#   base = merge-base CONFIABLE de integracion, NUNCA un valor provisto por el worker.
set -uo pipefail

base="${1:-}"; head="${2:-}"
fail_high() { echo "RISK=high"; echo "REASON=$1"; exit 0; }

[ -n "$base" ] && [ -n "$head" ] || fail_high "faltan refs base/head (fail-closed)"
git rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || fail_high "base invalida: $base"
git rev-parse --verify "$head^{commit}" >/dev/null 2>&1 || fail_high "head invalida: $head"
files="$(git diff --name-only "$base...$head" 2>/dev/null)" || fail_high "git diff fallo"
[ -n "$files" ] || fail_high "diff vacio (sospechoso / base incorrecta)"

# Rutas de ALTO RIESGO (security U data U config-prod). Cobertura de rutas obvias, NO exhaustiva.
PAT='(^|/)\.env|(^|/)[^/]*secret|credential|authorized_keys|(^|/)migrations/|\.sql$'
PAT="$PAT"'|(^|/)auth|(^|/)config/prod|(^|/)settings\.|(^|/)Dockerfile|docker-compose.*\.ya?ml$'
PAT="$PAT"'|(^|/)\.github/|(^|/)\.gitlab-ci\.yml$|(^|/)Jenkinsfile|(^|/)\.circleci/|(^|/)\.drone\.yml$'
PAT="$PAT"'|\.tf$|(^|/)helm/|(^|/)Chart\.yaml$|(^|/)values\.yaml$|(^|/)ansible/|cloudformation'
PAT="$PAT"'|(^|/)package(-lock)?\.json$|(^|/)yarn\.lock$|(^|/)requirements.*\.txt$|(^|/)Pipfile'
PAT="$PAT"'|(^|/)go\.(mod|sum)$|(^|/)Cargo\.(toml|lock)$|(^|/)pom\.xml$|\.gradle$|(^|/)config\.|\.pem$|\.key$'

hits="$(printf '%s\n' "$files" | grep -iE "$PAT" || true)"
if [ -n "$hits" ]; then
  echo "RISK=high"
  echo "REASON=rutas sensibles en el diff:"
  printf '%s\n' "$hits"
else
  echo "RISK=normal"
fi
exit 0
