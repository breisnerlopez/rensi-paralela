#!/bin/bash
# handoff_complete.sh <archivo> — LINT/WARN de completitud del handoff (F3).
# REPORTA secciones/campos faltantes; NUNCA bloquea: exit SIEMPRE 0.
#   - completo   -> "OK: completo"
#   - faltantes  -> "WARN: falta <items...>"
#   - sin archivo-> "WARN: no existe <archivo>"
# Chequea: frontmatter + type:context-package + 7 secciones context-package
#          + 5 campos de cierre del done.json (branch summary gate_veredicto
#            gate_refutacion gate_resuelto). Ver handoff/done-schema.md.

f="$1"

if [ -z "$f" ]; then
  echo "WARN: no existe (sin argumento)"
  exit 0
fi
if [ ! -f "$f" ]; then
  echo "WARN: no existe $f"
  exit 0
fi

miss=""

# 1. Frontmatter + type (mismo criterio que skills/context-package/validate.sh)
head -1 "$f" | grep -q '^---' || miss+="frontmatter "
grep -q 'type: context-package' "$f" || miss+="type:context-package "

# 2. Las 7 secciones obligatorias de context-package
for sec in Resumen Decisiones Hallazgos Riesgos Pendientes "Para el siguiente agente" Referencias; do
  grep -qi "^## $sec" "$f" || miss+="[$sec] "
done

# 3. Los 5 campos de cierre del worker (done.json), como claves de frontmatter
for campo in branch summary gate_veredicto gate_refutacion gate_resuelto; do
  grep -q "^$campo:" "$f" || miss+="$campo "
done

if [ -z "$miss" ]; then
  echo "OK: completo"
else
  echo "WARN: falta $miss"
fi

# Contrato innegociable: es lint/warn, jamás bloquea.
exit 0
