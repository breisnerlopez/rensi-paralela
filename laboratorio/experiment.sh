#!/bin/bash
set -uo pipefail
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$LAB/repo-sintetico"
OUT="$LAB/RESULTADOS.md"
cd "$R" || exit 1
export CLAUDE_CODE_FORK_SUBAGENT=1
CONTEXT="$(cat CONTEXTO.md)"
DOMS=(billing user order)

# suma ponderada de tokens de todos los transcripts del repo-sintetico modificados tras $1
sum_tokens() {
python3 -c "
import json,glob,os
mark=$1; tot=0.0; files=0
for f in glob.glob(os.path.expanduser('~/.claude/projects/*repo-sintetico*/*.jsonl')):
    if os.path.getmtime(f) < mark: continue
    files+=1
    for line in open(f):
        try: d=json.loads(line)
        except: continue
        m=d.get('message',{}) or {}
        if m.get('role')!='assistant': continue
        u=m.get('usage') or {}
        tot += (u.get('input_tokens',0) or 0)+1.25*(u.get('cache_creation_input_tokens',0) or 0)+0.1*(u.get('cache_read_input_tokens',0) or 0)+(u.get('output_tokens',0) or 0)
print('%.0f' % tot)
"
}
clean_wt() {
  for w in "$R"/.claude/worktrees/*/; do [ -d "$w" ] && { git worktree unlock "$w" 2>/dev/null; git worktree remove --force "$w" 2>/dev/null; }; done
  git worktree prune 2>/dev/null
  for b in $(git branch --format='%(refname:short)' | grep -vx master 2>/dev/null); do git branch -D "$b" 2>/dev/null; done
  rm -rf "$R/.claude/worktrees" 2>/dev/null
}

echo "# Laboratorio: paralela (cold) vs fork in-process (warm)" > "$OUT"
echo "" >> "$OUT"

########## COLD (paralela: 3 workers --worktree, contexto en prompt) ##########
clean_wt
MC=$(date +%s); sleep 1
tc0=$(date +%s)
for d in "${DOMS[@]}"; do
  ( timeout 220 claude --worktree "cold_$d" -p --dangerously-skip-permissions --model sonnet "$CONTEXT

Implementa el archivo packages/mod-$d/index.ts segun packages/mod-$d/SPEC.md y la CONVENCION de arriba. Escribe el archivo COMPLETO con Write. NO commitees, NO corras tests." > /dev/null 2>&1 ) &
done
wait
tc1=$(date +%s)
COLD_TOK=$(sum_tokens "$MC")
# score cold
COLD_SCORE=""
COLD_TOTAL=0
for d in "${DOMS[@]}"; do
  f="$R/.claude/worktrees/cold_$d/packages/mod-$d/index.ts"
  line=$(bash "$R/check.sh" "$d" "$f")
  COLD_SCORE+="  - mod-$d: $line\n"
  COLD_TOTAL=$((COLD_TOTAL + ${line%% /*}))
done
clean_wt

########## WARM (fork in-process: orquestador + 3 forks isolation:worktree) ##########
MW=$(date +%s); sleep 1
tw0=$(date +%s)
timeout 300 claude -p --dangerously-skip-permissions --model sonnet "$CONTEXT

Vas a implementar 3 modulos EN PARALELO. Haz TRES llamadas a la herramienta Agent EN EL MISMO mensaje, cada una con subagent_type 'fork', isolation 'worktree', run_in_background false:
- fork billing: implementa packages/mod-billing/index.ts segun su SPEC.md y la CONVENCION de arriba (que ya conoces). Escribe el archivo COMPLETO con Write. NO commitees.
- fork user: idem para packages/mod-user/index.ts
- fork order: idem para packages/mod-order/index.ts
Cuando terminen, reporta la ruta de worktree (pwd) de cada fork." > "$R/warm_report.txt" 2>&1
tw1=$(date +%s)
WARM_TOK=$(sum_tokens "$MW")
# score warm (buscar cada modulo en los worktrees agent-*)
WARM_SCORE=""
WARM_TOTAL=0
for d in "${DOMS[@]}"; do
  f=$(find "$R/.claude/worktrees" -path "*mod-$d/index.ts" 2>/dev/null | head -1)
  line=$(bash "$R/check.sh" "$d" "${f:-/nonexistent}")
  WARM_SCORE+="  - mod-$d: $line\n"
  WARM_TOTAL=$((WARM_TOTAL + ${line%% /*}))
done
clean_wt

########## REPORTE ##########
{
echo "## Resultados (N=3 modulos, modelo sonnet)"
echo ""
echo "| Métrica | paralela (cold) | fork in-process (warm) |"
echo "|---|---:|---:|"
echo "| **Tokens** (costo ponderado: in + 1.25·creation + 0.1·read + out) | $COLD_TOK | $WARM_TOK |"
echo "| **Tiempo** wall-clock (s) | $((tc1-tc0)) | $((tw1-tw0)) |"
echo "| **Precisión** (adherencia, suma /18) | $COLD_TOTAL | $WARM_TOTAL |"
echo ""
echo "### Precisión por módulo (check de adherencia /6)"
echo "**cold:**"; echo -e "$COLD_SCORE"
echo "**warm:**"; echo -e "$WARM_SCORE"
echo ""
echo "_Notas: cold = 3 procesos \`claude --worktree\` con contexto pre-empaquetado en el prompt (proxy de"
echo "paralela, SIN el overhead de orquestación/tmux/remote-control que paralela real añade → generoso con cold)."
echo "warm = 1 orquestador + 3 forks in-process con isolation:worktree (heredan contexto). Tokens = suma"
echo "ponderada de TODOS los transcripts del repo (incluye orquestador en warm). Una sola corrida (el caché es"
echo "ruidoso; para conclusión firme haría falta N reps)._"
} >> "$OUT"

echo "=== hecho. Reporte en $OUT ==="
cat "$OUT"
