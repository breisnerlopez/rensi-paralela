#!/bin/bash
set -uo pipefail
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$LAB/repo-sintetico"
OUT="$LAB/UMBRAL.md"
cd "$R" || exit 1
export CLAUDE_CODE_FORK_SUBAGENT=1

sum_tokens() {
python3 -c "
import json,glob,os
mark=$1; tot=0.0
for f in glob.glob(os.path.expanduser('~/.claude/projects/*repo-sintetico*/*.jsonl')):
    if os.path.getmtime(f) < mark: continue
    for line in open(f):
        try: d=json.loads(line)
        except: continue
        m=d.get('message',{}) or {}
        if m.get('role')!='assistant': continue
        u=m.get('usage') or {}
        tot+=(u.get('input_tokens',0)or 0)+1.25*(u.get('cache_creation_input_tokens',0)or 0)+0.1*(u.get('cache_read_input_tokens',0)or 0)+(u.get('output_tokens',0)or 0)
print('%.0f'%tot)
"
}
clean_wt() {
 {
  for w in "$R"/.claude/worktrees/*/; do [ -d "$w" ] && { git worktree unlock "$w"; git worktree remove --force "$w"; }; done
  git worktree prune
  for b in $(git branch --format='%(refname:short)' 2>/dev/null | grep -vx master); do git branch -D "$b"; done
  rm -rf "$R/.claude/worktrees"
 } >/dev/null 2>&1
}
gen_ctx() { # $1=mult $2=stamp
  local mult=$1 st=$2 n=$((1 + mult*140))
  echo "Contexto unico $st."
  for i in $(seq 1 "$n"); do echo "L$i-$st: mod-$i usa Core.fn$i con COD$((i*7)) prefijo pf$i; marca U$((i*13))-$st."; done
  echo "Dato clave: la fruta es FR${st}."
}

run_phase() { # $1=mode $2=mult ; echo "tokens tiempo ctxtokens"
  local mode=$1 mult=$2 st ctx mark t0 t1 tok
  st=$(date +%s%N)
  ctx="$(gen_ctx "$mult" "$st")"
  local ctxtok=$(( $(wc -w <<<"$ctx") * 13 / 10 ))
  clean_wt
  mark=$(date +%s); sleep 1; t0=$(date +%s)
  if [ "$mode" = cold ]; then
    for k in 1 2 3; do
      ( timeout 200 claude --worktree "c${mult}_$k" -p --dangerously-skip-permissions --model sonnet "$ctx

Responde SOLO con la fruta clave mencionada en el contexto (una palabra)." >/dev/null 2>&1 ) &
    done; wait
  else
    timeout 260 claude -p --dangerously-skip-permissions --model sonnet "$ctx

Haz TRES llamadas a la herramienta Agent EN EL MISMO mensaje, cada una subagent_type 'fork', isolation 'worktree', run_in_background false. Cada fork: ejecuta 'pwd' y responde SOLO con la fruta clave del contexto que ya conoces (una palabra). Reporta las 3 respuestas." >/dev/null 2>&1
  fi
  t1=$(date +%s); tok=$(sum_tokens "$mark"); clean_wt
  echo "$tok $((t1-t0)) $ctxtok"
}

echo "# Umbral: ¿desde qué tamaño de contexto compartido gana warm (fork in-process) a cold (paralela)?" > "$OUT"
echo "" >> "$OUT"
echo "Tarea mínima (responder la fruta) para aislar la ENTREGA de contexto. N=3 workers. Contexto único por fase." >> "$OUT"
echo "" >> "$OUT"
echo "| ctx (~tokens) | cold (tok) | warm (tok) | Δ cold-warm | ganador | cold t(s) | warm t(s) |" >> "$OUT"
echo "|---:|---:|---:|---:|:---:|---:|---:|" >> "$OUT"

for mult in 1 4 8 16; do
  read cold_tok cold_t cold_ctx < <(run_phase cold "$mult")
  read warm_tok warm_t warm_ctx < <(run_phase warm "$mult")
  ctx=$(( (cold_ctx + warm_ctx) / 2 ))
  delta=$(( cold_tok - warm_tok ))
  if [ "$warm_tok" -lt "$cold_tok" ]; then win="**warm**"; else win="cold"; fi
  echo "| ~$ctx | $cold_tok | $warm_tok | $delta | $win | $cold_t | $warm_t |" >> "$OUT"
done

echo "" >> "$OUT"
echo "_Δ>0 => cold gasta más (warm gana). El umbral es el ctx donde Δ pasa de negativo a positivo._" >> "$OUT"
echo "_Una corrida por punto (caché ruidoso). Tokens = suma ponderada (in+1.25·creation+0.1·read+out) de todos los transcripts del repo por fase (warm incluye el orquestador)._" >> "$OUT"
echo "=== hecho ===" ; cat "$OUT"
