# rensi-paralela

**Orquestador de trabajo paralelo, interactivo y monitoreable para coding agents** (Claude Code y
compatibles) — y la investigación empírica que sustenta cada decisión de diseño.

`rensi-paralela` lanza N sub-sesiones ("workers") en **git worktrees** separados, observables en vivo
(remote-control / tmux / móvil), con un **buzón** de preguntas/respuestas y un **gate adversarial** que
supervisa e integra el resultado. A diferencia de la mayoría de orquestadores de worktrees públicos —que
son multiplexores de aislamiento con integración manual—, aquí el orquestador **descompone, supervisa,
resuelve por gate lo que puede, escala al humano lo que debe, e integra** en una sola rama.

> **Titular honesto:** `paralela+` mejora **precisión y auditabilidad** del fan-out interactivo. **No
> promete menos tokens** — la medición muestra que ese efecto es ≈0/indetectable. Cada afirmación de este
> repo está respaldada por medición con repeticiones, o marcada como no medida.

## Cuándo usar `/paralela` (y cuándo NO)

Es una herramienta de **nicho**, no un reemplazo general de subagentes. La mayoría del trabajo
paralelizable **no la necesita**.

- ✅ **Úsala** para trabajo que **ESCRIBE** donde `Task` nativo se queda corto por **al menos uno** de:
  editan **zonas solapadas del mismo repo** (aislamiento-FS por worktree), workers **durables** (sobreviven
  a la caída del orquestador), o **diálogo a workers vivos** (buzón ask/answer). Nicho típico: un refactor
  grande de un monorepo confiable. Si son **archivos distintos, cortos y sin diálogo**, `Task` particiona y
  no necesitas paralela.
- ❌ **NO la uses** para trabajo **read-only** (investigar/buscar/auditar/mapear): eso es paralelizable por
  **fan-out directo de subagentes `Task`/`Explore`** — más ligero, sin worktrees. Ni para subtareas
  **secuencial-dependientes**.

> **Honestidad del diferenciador:** la **capacidad** de paralela (aislamiento-FS + diálogo en vuelo +
> procesos durables/observables) es real y está demostrada en **uso de producción**. Su **superioridad
> cuantitativa** sobre `Task` nativo (¿más rápida? ¿menos overhead?) **NO está A/B-medida** — es un
> experimento pendiente. Ver [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md) §1.b.

## Quickstart

```bash
git clone https://github.com/breisnerlopez/rensi-paralela.git && cd rensi-paralela
./install.sh                 # copia los skills a ~/.claude/skills/ (con backup); --dry-run para simular
# en Claude Code, sobre un REPO CONFIABLE:
/paralela "implementa X, Y, Z (subtareas independientes)"
```
`install.sh` incluye e instala el **gate** (`revisar` + agentes + lentes) y un **launcher de referencia**
(solo si no tienes ya uno). Lo único externo es el CLI `claude` + `python3`/`git`/`tmux` (ver
[Prerequisites](#prerequisites)).

## Las 4 features de `paralela+`

| # | Feature | Qué hace | Objetivo |
|---|---------|----------|----------|
| **F1** | **PRP** (Parallel Requirements Package) | un scout explora el repo 1× y emite por subtarea un blueprint **LEAN** (`prp_lint.sh` penaliza dumps) | precisión |
| **F2** | **Validación-autoridad** | el acceptance lo **autora el orquestador** (no el worker) y lo re-corre (`accept_run.sh`); la verdad es la validación, no el auto-reporte | precisión |
| **F3** | **Completitud del handoff** | `handoff_complete.sh` **reporta** (WARN) secciones faltantes, **nunca bloquea** | trazabilidad |
| **F4** | **Contexto declarado** | el PRP declara SOLO lo que la subtarea usa | precisión |

Evidencia E2E (detalle en [`laboratorio/RESULTADOS-PARALELA-PLUS-E2E.md`](laboratorio/RESULTADOS-PARALELA-PLUS-E2E.md)):
el PRP LEAN adhirió a la convención **más consistente** (9/9 perfectas, stdev 0) que el dump ad-hoc (4/9
sub-convención); `accept_run` **atrapa** un defecto que el auto-reporte deja pasar; tokens = **banda sin
conclusión** (como se predijo).

## Por qué existe este repo (y por qué es distinto)

La mayoría de herramientas del ecosistema afirman ahorros ("nunca pierdas contexto", "−X% tokens") **sin
medirlos**. Este proyecto nació de una investigación que **midió** — con experimentos reproducibles,
repeticiones y un gate adversarial (retador + auditor) — qué optimizaciones de agentes en paralelo
realmente funcionan y cuáles son espejismos (detalle en [`docs/INVESTIGACION.md`](docs/INVESTIGACION.md)):

- **La memoria/RAG no es la palanca de tokens** en flujos de worktrees; domina la exploración de código.
- **Ninguna optimización de *entrega de contexto* ahorra tokens de forma fiable** (fork caliente,
  `--resume`, pre-empaquetado): con repeticiones, el efecto queda dentro del ruido.
- **Volcar contexto grande baja la precisión** (entierra lo clave); pre-empaquetar debe ser **LEAN**.
- **El formato estructurado de handoff no mejora al LLM** (empate vs. prosa), pero **sí** da trazabilidad.

**Conclusión de diseño:** el modelo cold + worktrees + observable es el correcto (medido); las mejoras de
`paralela+` apuntan a **precisión y auditabilidad**, no a un truco de tokens que la evidencia no respalda.

## Prerequisites

`rensi-paralela` incluye los skills, el **gate** (skill `revisar` + agentes `retador`/`auditor` + lentes)
y un **launcher de referencia**; `install.sh` lo coloca todo. Lo único que aportas es el runtime base:

1. **`claude` CLI (Claude Code)** con acceso a API/red. Los skills viven en [`skills/`](skills/) y se
   instalan con `./install.sh` en `~/.claude/skills/`.
2. **`python3`, `git`, `tmux`.**

Se **incluyen y se instalan** (con `install.sh`):
- El **gate CERRAR**: skill [`revisar`](skills/revisar/), agentes [`retador`/`auditor`](agents/) y
  [lentes](review/lenses/) → `~/.claude/{skills,agents,review/lenses}`.
- Un **launcher de referencia** ([`launcher/claudea`](launcher/)) que cumple el contrato `<launcher> -w <id>`
  (crea worktree+rama, arranca un worker `claude` observable con `--dangerously-skip-permissions` — solo
  sobre **repos confiables** — y reenvía `--settings`/`--append-system-prompt`/`--model`). Genérico y
  saneado; `install.sh` lo instala **solo si no tienes ya un launcher** (si tienes uno, lo respeta). Puedes
  adaptarlo a tu entorno.

## Instalación

```bash
./install.sh                 # instala skills + gate (respalda lo previo a .bak-<ts>) + launcher si falta
./install.sh --dry-run       # muestra qué haría, sin tocar nada
./install.sh --dest /ruta    # destino alternativo de skills
./install.sh --no-launcher   # no instala el launcher de referencia
```
Instala los skills (`paralela`, `worker-protocol`, `context-package`, `revisar`), los **agentes del gate**
(`retador`, `auditor`) y las **lentes** en `~/.claude/{skills,agents,review/lenses}`, aplica permisos de
ejecución, y corre los tests unitarios desde el destino como post-check. El **launcher de referencia** se
instala en `~/.local/bin/claudea` **solo si no tienes ya uno** (si existe, lo respeta).

## Uso y documentación

- **[`docs/GUIA-USUARIO.md`](docs/GUIA-USUARIO.md)** — cómo correr `/paralela` paso a paso, con ejemplo.
- **[`docs/REFERENCIA.md`](docs/REFERENCIA.md)** — referencia técnica: cada script, el buzón, guardarraíles.
- **[`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md)** — diseño y rationale (por qué cold+worktree; F1-F4; seguridad).
- **[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)** — problemas comunes y solución.
- **[`docs/INVESTIGACION.md`](docs/INVESTIGACION.md)** — la investigación completa, con las reversiones honestas.
- **[`ROADMAP-Y-PLAN.md`](ROADMAP-Y-PLAN.md)** — hoja de ruta `paralela+` + estado y DoD.

## Estructura del repo
```
skills/
  paralela/          # skill del ORQUESTADOR: SKILL.md + scripts (prp_lint, accept_run,
                     # handoff_complete, orch-lib, diff-risk, worker-guard) + plantillas + tests/
  worker-protocol/   # protocolo del WORKER
  context-package/   # handoff estructurado (schema + validador)
  revisar/           # skill del gate adversarial (retador → auditor)
agents/              # agentes del gate: retador.md, auditor.md   -> ~/.claude/agents
review/lenses/       # lentes del gate (_base + dim/* + etapa/*)  -> ~/.claude/review/lenses
launcher/            # launcher de referencia (claudea) + su README
docs/                # guía, referencia, arquitectura, troubleshooting, investigación
laboratorio/         # experimentos reproducibles + resultados (sobre un repo sintético)
install.sh           # instalador
```

## Limitaciones honestas

- **No promete menos tokens.** F1/F4 = precisión; el efecto en tokens es ≈0/indetectable (medido).
- **F1/F4 son ortogonales al paralelismo.** La ganancia de precisión medida es de la estructura **PRP
  LEAN**; no hay razón mecánica conocida para que un subagente `Task` nativo con el mismo PRP no la
  obtuviera igual (no probado directamente). NO son evidencia de que los workers-en-worktree superen a
  `Task` — el diferenciador de paralela es de **capacidad** (aislamiento-FS, diálogo en vuelo,
  durabilidad), no de precisión.
- **La superioridad cuantitativa vs `Task` nativo no está medida.** El E2E comparó PRP-LEAN vs dump (ambos
  paralela), no paralela vs `Task`. La capacidad está demostrada en producción; el A/B cuantitativo (¿más
  rápido/menos overhead?) es un experimento **pendiente**.
- **El launcher de referencia es genérico** (sin datos personales); puede requerir **adaptación a tu
  entorno** (permisos elevados, sandbox, etc.). El gate (`revisar` + agentes + lentes) sí viene completo.
- **El path interactivo se validó con un smoke en vivo** (launcher + buzón + guard + autonomía del
  worker), pero la orquestación **completa** de N workers no se corrió como una sola sesión viva.
- La **regla anti-narración** de los workers es pulido **no medido** (sin baseline); no es un ahorro vendible.
- El [`laboratorio/`](laboratorio/) requiere el runtime vivo para reproducir los números.

## Estado
`paralela+ v0.2` **implementado** y verificado (gate CERRAR pasado — retador + auditor; unit tests +
E2E). Ver [`ROADMAP-Y-PLAN.md`](ROADMAP-Y-PLAN.md) y [`CHANGELOG.md`](CHANGELOG.md). Contribuciones y
críticas metodológicas bienvenidas — especialmente si **miden** (ver [`CONTRIBUTING.md`](CONTRIBUTING.md)).

## Licencia
MIT — ver [`LICENSE`](LICENSE).
