#!/bin/bash
set -uo pipefail
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$LAB/CONTEXT_PACKAGE_TEST.md"
export CLAUDE_CODE_FORK_SUBAGENT=1

# --- handoff ESTRUCTURADO (schema context-package) ---
H_STRUCT="---
type: context-package
task: implementar servicios del monorepo
status: partial
---
## Resumen
Ya implemente create_registry. Falta create_gateway, consistente con lo decidido.
## Decisiones
- Los ids se generan con \`mkRgx(prefix)\` (helper propio) — porque Core.id no soporta el formato requerido.
- Los errores se lanzan con \`bail(code)\` — porque throw rompe el gate de conformidad.
- Prefijos = 3 letras + un digito; registry uso \"reg1\".
## Para el siguiente agente
- Implementa create_gateway respetando lo anterior. El prefijo de gateway es \"gw4\".
## Referencias
- packages/mod-registry/index.ts"

# --- handoff TEXTO LIBRE (mismo contenido, prosa) ---
H_FREE="Ya implemente create_registry. Para lo siguiente hay que implementar create_gateway de forma consistente. En este proyecto los ids se generan con un helper propio llamado mkRgx(prefix) — no uses Core.id, porque no soporta el formato requerido. Los errores se lanzan con bail(code), no con throw, porque throw rompe el gate de conformidad. Los prefijos son de tres letras mas un digito; registry uso reg1 y el de gateway es gw4. Referencia: packages/mod-registry/index.ts."

TASK="Escribe el archivo create_gateway.ts: una funcion \`export async function create_gateway(input: unknown)\` consistente con el handoff de arriba. Devuelve SOLO el codigo TypeScript, sin explicacion."

score() { # stdin=codigo -> "n <detalle>"
python3 -c "
import sys
c=sys.stdin.read()
s=0; d=[]
for kw,lbl in [('mkRgx','mkRgx'),('bail','bail'),('gw4','gw4')]:
    if kw in c: s+=1; d.append(lbl+'✓')
    else: d.append(lbl+'✗')
reg = ('Core.id' in c) or ('throw ' in c)
if reg: d.append('REGRESO-a-default')
print('%d %s' % (s, ' '.join(d)))
"
}

echo "# Test empírico: handoff ESTRUCTURADO vs TEXTO LIBRE (¿respeta decisiones no-obvias?)" > "$OUT"
echo "" >> "$OUT"
echo "Contenido idéntico (mkRgx, bail, prefijo gw4). Solo cambia el formato. Score = decisiones respetadas /3. 'REGRESO-a-default' = usó Core.id/throw ignorando el handoff." >> "$OUT"
echo "" >> "$OUT"
echo "| rep | estructurado /3 | texto-libre /3 |" >> "$OUT"
echo "|---|---|---|" >> "$OUT"

declare -a S_SC F_SC
for rep in 1 2 3 4; do
  rs=$(timeout 150 claude -p --output-format json --dangerously-skip-permissions --model sonnet "Recibiste este handoff del agente anterior; respetalo.

$H_STRUCT

$TASK" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('result',''))" 2>/dev/null)
  rf=$(timeout 150 claude -p --output-format json --dangerously-skip-permissions --model sonnet "Recibiste este handoff del agente anterior; respetalo.

$H_FREE

$TASK" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('result',''))" 2>/dev/null)
  ss=$(printf '%s' "$rs" | score); fs=$(printf '%s' "$rf" | score)
  S_SC+=("${ss%% *}"); F_SC+=("${fs%% *}")
  echo "| $rep | ${ss} | ${fs} |" >> "$OUT"
done

python3 - "$OUT" "${S_SC[*]}" "${F_SC[*]}" <<'PY'
import sys
out=sys.argv[1]; s=[int(x) for x in sys.argv[2].split()]; f=[int(x) for x in sys.argv[3].split()]
a=lambda L: sum(L)/len(L) if L else 0
with open(out,'a') as o:
    o.write("\n**Promedio decisiones respetadas:** estructurado=%.2f/3 | texto-libre=%.2f/3\n"%(a(s),a(f)))
    o.write("\n_Si son ~iguales => el formato estructurado NO mejora la continuidad sobre texto libre (el valor del schema es auditoría/máquina, no que el LLM 'entienda mejor'). Si estructurado > libre => el schema sí ayuda a preservar decisiones._\n")
PY
echo "=== hecho ==="; cat "$OUT"
