#!/bin/bash
# FASE 0 - Spike de costo: cold-fiel vs warm, N in {1,2,4}. Mide tokens por worker (usage del jsonl),
# aisla el delta de herencia, calcula break-even. Controles: cold worktree-aislado (como paralela real),
# warm con base checkpoint contabilizada, timestamps para TTL/latencia.
set -uo pipefail
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$LAB" rev-parse --show-toplevel)"   # repo host de los worktrees (portable)
SB="$LAB/json"; mkdir -p "$SB"
CTX="$LAB/contexto_compartido.md"
OUT="$LAB/spike_result.txt"
: > "$OUT"
cd "$REPO" || exit 1
export CLAUDE_CODE_FORK_SUBAGENT=1
CTXTEXT="$(cat "$CTX")"
DOMAINS=(billing user order notify data audit metrics search)

subtask() { # $1=domain
  printf 'SUBTAREA: para el dominio "%s", responde SOLO en UNA linea con formato exacto: <NombreClase segun convencion> | <prefijo de Core.id para ese dominio segun el contexto> | <async-Result: si/no>' "$1"
}

CM=(-p --output-format json --dangerously-skip-permissions --model sonnet)

for N in 1 2 4; do
  echo "########## N=$N ##########" >> "$OUT"

  # ---- COLD (worktree-aislado, contexto en el prompt como prefijo identico) ----
  tc0=$(date +%s)
  for i in $(seq 1 "$N"); do
    dom="${DOMAINS[$((i-1))]}"
    ( timeout 160 claude --worktree "c${N}_$i" "${CM[@]}" "$CTXTEXT

$(subtask "$dom")" > "$SB/c${N}_$i.json" 2>&1 ) &
  done
  wait
  tc1=$(date +%s)

  # ---- WARM: base checkpoint fresca + workers que la resumen ----
  BASE=$(cat /proc/sys/kernel/random/uuid)
  tb0=$(date +%s)
  timeout 160 claude --session-id "$BASE" "${CM[@]}" "$CTXTEXT

Guarda este contexto compartido. Cuando te de una SUBTAREA, respondela segun la convencion. Responde solo LISTO." > "$SB/base${N}.json" 2>&1
  tb1=$(date +%s)
  tw0=$(date +%s)
  for i in $(seq 1 "$N"); do
    dom="${DOMAINS[$((i-1))]}"
    ( timeout 160 claude --worktree "w${N}_$i" --resume "$BASE" --fork-session "${CM[@]}" "$(subtask "$dom")" > "$SB/w${N}_$i.json" 2>&1 ) &
  done
  wait
  tw1=$(date +%s)

  echo "tiempos: cold=$((tc1-tc0))s  base_setup=$((tb1-tb0))s  warm_workers=$((tw1-tw0))s  latencia_base->warm=$((tw0-tb1))s" >> "$OUT"
  echo "$N $((tc1-tc0)) $((tb1-tb0)) $((tw1-tw0))" >> "$SB/times.txt"
done

# ---- limpieza worktrees/ramas (workers no escriben; no git reset) ----
for w in "$REPO"/.claude/worktrees/*/; do [ -d "$w" ] && { git worktree unlock "$w" 2>/dev/null; git worktree remove --force "$w" 2>/dev/null; }; done
git worktree prune 2>/dev/null
for b in $(git branch --format='%(refname:short)' | grep -vx master); do git branch -D "$b" 2>/dev/null; done
rm -rf "$REPO/.claude/worktrees" 2>/dev/null

# ---- ANALISIS ----
python3 - "$SB" "$OUT" <<'PY'
import json, os, sys
SB, OUT = sys.argv[1], sys.argv[2]
def usage(f):
    p=os.path.join(SB,f)
    try:
        u=json.load(open(p)).get('usage',{})
        return dict(read=u.get('cache_read_input_tokens',0) or 0,
                    creation=u.get('cache_creation_input_tokens',0) or 0,
                    inp=u.get('input_tokens',0) or 0,
                    out=u.get('output_tokens',0) or 0,
                    result=(json.load(open(p)).get('result') or '')[:60])
    except Exception as e:
        return None
# costo ponderado en "input-equivalente": creation 1.25x, read 0.1x, input 1x, output 1x (out es minusculo)
def cost(u): return u['inp'] + 1.25*u['creation'] + 0.1*u['read'] + u['out']
lines=["", "="*90, "ANALISIS (costo ponderado = input + 1.25*creation + 0.1*read + output)", "="*90]
rows=[]
for N in (1,2,4):
    cold=[usage(f"c{N}_{i}.json") for i in range(1,N+1)]; cold=[u for u in cold if u]
    warm=[usage(f"w{N}_{i}.json") for i in range(1,N+1)]; warm=[u for u in warm if u]
    base=usage(f"base{N}.json")
    if len(cold)<N or len(warm)<N or not base:
        lines.append(f"N={N}: FALTAN datos (cold={len(cold)}/{N} warm={len(warm)}/{N} base={'ok' if base else 'NO'})")
        continue
    cold_cost=sum(cost(u) for u in cold)
    warm_cost=cost(base)+sum(cost(u) for u in warm)
    lines.append(f"\n--- N={N} ---")
    lines.append(f"  COLD workers read/creation/in/out: " + "; ".join(f"[{u['read']}/{u['creation']}/{u['inp']}/{u['out']}]" for u in cold))
    lines.append(f"  WARM base    read/creation/in/out: [{base['read']}/{base['creation']}/{base['inp']}/{base['out']}]")
    lines.append(f"  WARM workers read/creation/in/out: " + "; ".join(f"[{u['read']}/{u['creation']}/{u['inp']}/{u['out']}]" for u in warm))
    # clave: cold worker 2..N, ¿pegan cache en el contexto (read alto) o lo pagan fresco (creation alto)?
    if N>1:
        lines.append(f"  >> cold worker#2 read={cold[1]['read']} creation={cold[1]['creation']}  (¿el contexto pega cache entre workers cold worktree-aislados?)")
    lines.append(f"  >> warm worker#1 read={warm[0]['read']} creation={warm[0]['creation']}  (¿hereda la base?)")
    lines.append(f"  COSTO COLD (N={N}) = {cold_cost:,.0f}   COSTO WARM (N={N}, +base) = {warm_cost:,.0f}   delta(cold-warm) = {cold_cost-warm_cost:,.0f}  ({'WARM gana' if warm_cost<cold_cost else 'COLD gana'})")
    rows.append((N,cold_cost,warm_cost))
lines.append("\n--- BREAK-EVEN ---")
be=[N for N,c,w in rows if w<c]
lines.append(f"  warm gana a partir de N = {min(be) if be else 'NUNCA en {1,2,4}'}")
lines.append(f"  sanity (una respuesta cold y una warm): cold={usage('c1_1.json')['result'] if usage('c1_1.json') else '?'} | warm={usage('w1_1.json')['result'] if usage('w1_1.json') else '?'}")
open(OUT,'a').write("\n".join(lines)+"\n")
PY
echo "=== estado final ===" >> "$OUT"; git worktree list >> "$OUT" 2>&1; git status --short >> "$OUT" 2>&1
