# E2E paralela+ vs baseline JUSTO — resultados (§5.2)

> **Método (C1 baseline JUSTO):** ambos brazos reciben la MISMA convención (`repo-sintetico/CONTEXTO.md`).
> Lo que se testea es si la **ESTRUCTURA** (PRP LEAN + validación-autoridad) hace el resultado más
> consistente y atrapa defectos — NO si "tener contexto" ayuda. 3 reps × 3 dominios (billing/user/order)
> × 2 brazos = 18 workers `claude -p --model sonnet`, cada uno en su propio git worktree (clon
> **standalone** de `repo-sintetico` en un directorio temporal, aislado del repo padre).
> **Honestidad (§5.3):** se ESPERABA que tokens saliera inconcluso; el éxito se juzga por **precisión** +
> no-regresión de espíritu. Tokens = banda sin conclusión.

## PRIMARIO — Precisión / consistencia de adherencia (DoD #1)

Scorer: `repo-sintetico/check.sh` (adherencia /6 + penalización −2 por anti-convención:
`console.`/`Math.random`/`Date.now`/`throw new Error`).

| Brazo | contexto | n | min | max | mean | stdev | 6/6 |
|-------|----------|---|-----|-----|------|-------|-----|
| **BASELINE** | `CONTEXTO.md` ad-hoc (dump completo) | 9 | 5 | 6 | **5.56** | 0.50 | **5/9** |
| **PARALELA+** | PRP LEAN estructurado (F1/F4) | 9 | 6 | 6 | **6.00** | **0.00** | **9/9** |

**Señal fuerte y detectable:** el PRP LEAN produjo adherencia **perfecta y sin varianza** (9/9); el dump
ad-hoc dejó 4/9 corridas sub-convención (score 5). Consistente con el hallazgo previo del proyecto
("volcar contexto grande baja la precisión"): **estructurar LEAN > dumpear**. Esta es la ganancia PRIMARIA
reclamable de F1/F4 — **precisión**, no tokens.

## PRIMARIO — Validación como autoridad (DoD #2)

**(a) Vivo:** BASELINE integra por auto-reporte → **4/9** salidas sub-convención entrarían sin revisión.
PARALELA+ produjo **0** salidas sub-6, así que `accept_run` no tuvo nada que atrapar en el brazo vivo
(mejores entradas por el PRP).

**(b) Determinista (discriminante mecánico):** con un defecto plantado (`Math.random` → check 3/6):

| | resultado |
|---|---|
| BASELINE (confía en `done.json=aprobado`) | **integra el defecto** (pasa) |
| PARALELA+ (`accept_run` = check.sh≥6, autoría-orquestador) | **FAIL exit 2 → defecto ATRAPADO** |
| Control (implementación limpia 6/6) | **PASS exit 0 → sin falso positivo** |

**Combinado:** paralela+ gana en **prevención** (mejor adherencia, menos defectos producidos) **y en
detección** (`accept_run` atrapa el defecto si ocurre, sin falsos positivos). El auto-reporte del worker
NO es autoridad; la re-validación del orquestador sí.

## SECUNDARIO — Tokens (banda, SIN conclusión)

Tokens ponderados por worker (`in + 1.25·cache_create + 0.1·cache_read + out`):

| Brazo | min | max | mean (n=9) |
|-------|-----|-----|------------|
| BASELINE | 76K | 157K | 109K |
| PARALELA+ | 110K | 215K | 148K |

Los rangos **se solapan** fuertemente; la media observada de paralela+ es mayor (ratio 1.35) pero con n=9
y CV alto **está dentro del ruido que §5.3 predijo**. **NO se declara ganador ni perdedor en tokens** —
afirmar "+35%" sería tan deshonesto como afirmar un ahorro. (No incluye costo de scout ni de `accept_run`.)

## SECUNDARIO — Break-even del scout

En este E2E los PRP se **autoraron directamente** (no se corrió un scout vivo), así que su costo **no se
midió por separado**. El break-even es estructural: el scout explora **1×** y amortiza sobre N=3 workers/rep;
si N fuera 1-2 o las subtareas no compartieran contexto, el scout sería costo neto → sáltalo (documentado
en `skills/paralela/SKILL.md` §2).

## PRIMARIO — No-regresión de espíritu

- **Cold / separados:** cada worker corrió en su propio git worktree, proceso `claude -p` aparte. ✅
- **Integración por clon limpio + master intacto:** el clon standalone quedó con working-tree limpio
  (0 líneas), HEAD intacto; los `index.ts` viven en worktrees, no en master. ✅
- **Interactivo / observable (buzón, tmux/launcher, guard):** validado por un **smoke en vivo aparte**:
  un worker lanzado por el launcher real (`claudea`) creó su worktree +
  sesión tmux, usó el buzón autónomamente (`status.json` → `done.json` con los 5 campos gate), y el
  **guard bloqueó un `git push` en vivo** (el worker lo registró como esperado). La matriz de precisión
  arriba fue headless `-p` a propósito (mide adherencia/tokens, no el path interactivo). ✅
- **Cobertura honesta:** todos los COMPONENTES están validados —ejecución de worker + precisión (matriz);
  launcher + buzón + guard + autonomía (smoke vivo); `accept_run` (discriminante determinista)—. Lo que
  **no** se corrió como una sola pieza viva es la orquestación paralela+ COMPLETA de N workers
  (scout→N workers→ask/answer→accept_run→integración→CERRAR) en una sola sesión (sería correr `/paralela`
  de verdad sobre sí mismo — el meta-riesgo #7 del roadmap lo desaconseja, y es pesado). ⚠️ (parcial, honesto).

## Caveats de reproducibilidad

`repo-sintetico` **no** es un repo git propio (es un subdir del repo padre); el E2E monta un clon
standalone (`git init`) en un directorio temporal aislado para no tocar el repo padre. Los números
dependen del runtime vivo (CLI + API + skip-permissions), como advierte el README. El harness fue un
**script de sesión no versionado** (método reproducible pero dependiente del runtime, igual que el resto
de `laboratorio/`); no se commitea porque no correría sin ese entorno.
