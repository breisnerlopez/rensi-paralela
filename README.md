# rensi-paralela

**Orquestador de trabajo paralelo, interactivo y monitoreable para coding agents** (Claude Code y
compatibles) — y la investigación empírica que sustenta cada decisión de diseño.

`rensi-paralela` lanza N sub-sesiones ("workers") en **git worktrees** separados, observables en vivo
(remote-control / tmux / móvil), con un **buzón** de preguntas/respuestas y un **gate adversarial** que
supervisa e integra el resultado. A diferencia de la mayoría de orquestadores de worktrees públicos —que
son multiplexores de aislamiento con integración manual—, aquí el orquestador **descompone, supervisa,
resuelve por gate lo que puede, escala al humano lo que debe, e integra** en una sola rama.

## Por qué existe este repo (y por qué es distinto)

La mayoría de herramientas del ecosistema afirman ahorros ("nunca pierdas contexto", "−X% tokens") **sin
medirlos**. Este proyecto nació de una investigación que **midió** — con experimentos reproducibles,
repeticiones y un gate adversarial (retador + auditor) — qué optimizaciones de agentes en paralelo
realmente funcionan y cuáles son espejismos. Los hallazgos guían el diseño y están documentados con
honestidad, incluidas las conclusiones intermedias que la propia medición **refutó**.

**Resumen de lo medido** (detalle en [`docs/INVESTIGACION.md`](docs/INVESTIGACION.md)):

- **La memoria/RAG no es la palanca de tokens** en flujos de worktrees; el costo lo domina la exploración
  de código y el trabajo del agente.
- **Ninguna optimización de *entrega de contexto* ahorra tokens de forma fiable** (fork caliente,
  `--resume`, pre-empaquetado): con repeticiones, el efecto queda dentro del ruido. El *trabajo* del
  agente domina el costo.
- **Volcar contexto grande baja la precisión** (entierra lo clave); pre-empaquetar debe ser **LEAN**.
- **El formato estructurado de handoff no mejora al LLM** (empate vs. prosa), pero **sí** aporta
  trazabilidad/auditoría.
- **Mecánica nativa de Claude Code medida**: `fork`/`--resume`/`/subtask`/nesting/caché con worktrees —
  qué preserva caché y qué no, y por qué el `cwd` que aísla es el que invalida el caché.

**Conclusión de diseño:** el modelo cold + worktrees + observable de `rensi-paralela` es el correcto
(medido). Las mejoras de la hoja de ruta (`paralela+`) apuntan a **precisión y auditabilidad**, no a un
truco de tokens que la evidencia no respalda.

## Estructura
- [`docs/INVESTIGACION.md`](docs/INVESTIGACION.md) — la investigación completa, con evidencia y las
  reversiones honestas donde un solo experimento engañó y las repeticiones corrigieron.
- [`ROADMAP-Y-PLAN.md`](ROADMAP-Y-PLAN.md) — hoja de ruta `paralela+` (v0.2) + plan de implementación y
  pruebas, ya pasada por gate adversarial.
- [`laboratorio/`](laboratorio/) — scripts y resultados reproducibles (sobre un **repo sintético**).
- [`paralela-plus/`](paralela-plus/) — staging de la implementación (contrato de interfaces).

## Estado
Investigación cerrada y documentada. Implementación de `paralela+` en curso (ver hoja de ruta). Las
contribuciones y críticas metodológicas son bienvenidas — especialmente si **miden**.

## Licencia
MIT.
