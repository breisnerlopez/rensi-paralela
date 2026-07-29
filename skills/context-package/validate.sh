#!/bin/bash
# validate.sh <paquete.md> -> OK o lista de faltantes
f="$1"; [ -f "$f" ] || { echo "FAIL: no existe $f"; exit 1; }
miss=""
head -1 "$f" | grep -q '^---' || miss+="frontmatter "
grep -q 'type: context-package' "$f" || miss+="type:context-package "
for sec in Resumen Decisiones Hallazgos Riesgos Pendientes "Para el siguiente agente" Referencias; do
  grep -qi "^## $sec" "$f" || miss+="[$sec] "
done
if [ -z "$miss" ]; then echo "OK: paquete válido ($f)"; else echo "FALTA: $miss"; exit 2; fi
