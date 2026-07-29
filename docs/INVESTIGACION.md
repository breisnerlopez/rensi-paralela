# Investigación: qué optimiza de verdad el trabajo paralelo con agentes (y qué es espejismo)

> Todo aquí está **medido** con experimentos reproducibles y repeticiones, y estresado con un gate
> adversarial (un agente retador + un auditor independiente). Se documentan también las conclusiones
> intermedias que la propia medición **refutó** — porque esa honestidad es el aporte principal.
> Entorno: Claude Code 2.1.220. Los ejemplos sobre "un monorepo real de referencia" usan una copia
> desechable de un repo real (~15-25k tokens de contexto arquitectónico compartido), sin exponer su código.

## 0. Punto de partida y método
Pregunta original: reducir el consumo de tokens (y ganar velocidad/precisión) en flujos con **muchas
sesiones en git worktrees + uso intensivo de subagentes**. Hipótesis inicial del usuario: "un framework de
memoria lo resolvería, porque cada worker vuelve a leer todo el contexto".

Método: **medir antes de concluir.** Cada afirmación se sostuvo o cayó por evidencia (git como verdad,
`usage` de los transcripts para tokens), no por plausibilidad. Un retador refutaba cada etapa; un auditor
reproducía de cero los hallazgos críticos.

## 1. La memoria/RAG NO es la palanca de tokens
El cache-miss de los worktrees es **estructural**: Claude Code incrusta el `cwd` en el system prompt, así
que dos sesiones en directorios distintos construyen prefijos distintos y no comparten caché — *incluidos
worktrees del mismo repo*. El grueso del gasto de un worker es **exploración de código** (50-80% en tareas
reales) + bootstrap fijo. La re-lectura de *memoria/hechos* es <10% del volumen. Un motor de memoria
semántica encima (vector DB + embeddings + MCP) **suma** tokens: es contraproducente para el objetivo.

→ Descartado: construir/adoptar un framework de memoria para ahorrar tokens. La memoria sirve a la
**continuidad/precisión** entre sesiones (auto-memory nativa en markdown basta), no al costo.

## 2. Mecánica nativa medida: fork / `--resume` / `/subtask` / nesting / caché
Verificado empíricamente + auditado:

- **`fork` programático** (herramienta Agent + `subagent_type:fork`) está gateado por
  `CLAUDE_CODE_FORK_SUBAGENT=1`. Un fork hereda el contexto del padre, puede lanzar subagentes normales,
  **no** puede forkear otra vez.
- **`/subtask`** (fork interactivo) **nunca** aísla en worktree — edita el checkout/rama actual (probado con
  varios parámetros; el arg-hint solo acepta `<task>`).
- **`--continue`/`-c` es por-directorio**; **`--resume <id>`** cubre el proyecto + sus worktrees.
- **Nesting** de subagentes: default 3 en 2.1.220 (era 5 antes), configurable con
  `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; el límite es **por proceso**.

### El muro estructural (clave)
Medido con un contexto grande, misma sesión base:
| Resume desde… | cache_read | cache_creation |
|---|---:|---:|
| **mismo dir** | 66,012 (hereda TODO vía caché) | 39 |
| **worktree** | 23,702 (solo bootstrap) | 42,792 (re-crea todo) |

**El mismo `cwd` que aísla un worktree es el que invalida el caché** del contexto (va en el system prompt
antes del contenido). Un worker separado que hace `--resume` en un worktree hereda el *contenido* pero
**re-crea el caché** → cuesta MÁS que un worker cold pre-empaquetado. (El `read≈23,702` que aparece hasta
en un `claude -p "di OK"` sin contexto es **bootstrap**, no herencia — un error de lectura fácil que costó
una conclusión intermedia.)

### La excepción: el fork **in-process**
El fork in-process con `isolation:worktree` **sí preserva el caché** (medido: lee ~63k de caché, crea ~150)
porque hereda el system prompt del padre (con su `cwd`) y `isolation` solo redirige las escrituras. Pero
**vive en la sesión** del orquestador → no es observable/independiente. Y (ver §3) no se traduce en ahorro
práctico.

## 3. EL CAPSTONE: la entrega de contexto ≈ ruido; el trabajo domina
Con **repeticiones** (no un solo run), NINGUNA optimización de *entrega de contexto* ahorra tokens de forma
fiable:
- Sobre el monorepo real, cold **pre-empaquetado** vs cold **explorando** (3 reps): **7% de diferencia,
  dentro del ruido, y el pre-empaquetado perdió 2 de 3 reps.** La variancia entre reps "idénticas" fue de
  **2×** con cambios de ganador. Un "56% de ahorro" observado en un solo run era **ruido**.
- El costo lo domina el **trabajo del agente** (multi-turno: leer, escribir, reintentar), no cómo se le
  entrega el contexto.
- **Volcar un contexto grande EMPEORA la precisión** (entierra lo clave; el worker que explora encuentra
  justo lo que necesita).

> **Nota de reproducibilidad.** La evidencia cruda de ese "monorepo real" (los transcripts y su `usage`) es
> **confidencial y NO se incluye** en este repo — queda fuera del alcance público. Lo reproducible aquí es el
> **laboratorio sintético** presente ([`laboratorio/`](../laboratorio/): spike y umbral sobre `repo-sintetico/`):
> ilustra el método y el fenómeno (el "56% de ahorro" de un solo run vs. la señal que emerge con reps), no
> los números concretos del monorepo real.

→ La única palanca de tokens realmente robusta es **reducir el trabajo** (tareas acotadas), no la entrega
de contexto. Y "agentes finos que exploran en fresco" es una estrategia razonable, no un antipatrón.

## 4. Handoffs estructurados: no ayudan al LLM, sí a los humanos
Prueba controlada (mismo contenido, dos formatos, 4 reps): un agente downstream respetó las decisiones del
upstream **igual desde texto libre (3.0/3) que desde un schema estructurado (2.75/3)** — empate. El valor
del schema es **trazabilidad/auditoría/parseabilidad** y forzar completitud del emisor, **no** que el
modelo "entienda mejor" ni ahorrar tokens (≈0 medido).

*(Nota práctica: un handoff que empieza con frontmatter `---` rompe `claude -p "---…"` porque la CLI lo
toma como flag. Anteponer siempre un preámbulo.)*

## 5. El ecosistema (qué ya existe)
- **Handoff estructurado en markdown** es un patrón **mainstream** (p.ej. skills `session-handoff` en
  colecciones de 30k★, `claude-handoff`, `agent-session-resume`) — pero **nadie lo mide**.
- **Pre-empaquetar contexto ANTES de la tarea** es el espacio grande y validado: **spec-driven** (spec-kit
  124k★, OpenSpec 63k★, BMAD 51k★) y **PRP** (product requirement prompts, ~14k★). Es lo más alineado con
  el único lever real (no re-explorar), aunque orientado a features nuevas.
- **Orquestadores de worktrees públicos** (claude-squad, Crystal, Uzi, ccswarm) son **multiplexores de
  aislamiento** — sin buzón ni gate ni integración automática. `rensi-paralela` ya está por delante ahí.
- **Frameworks de estado** (LangGraph, CrewAI, OpenAI Agents SDK) pasan estado tipado in-process, sin
  worktrees. Nadie combina worktrees-paralelo-observable + handoff estructurado + gate; ahí hay hueco.

## 6. Por qué `paralela+` toma este camino
Dado todo lo anterior, el diseño se ancla en evidencia, no en marketing:
- **No** migrar a workers calientes (warm-resume no ahorra; fork in-process no es observable) → el modelo
  **cold + worktrees + observable** es correcto y más rápido.
- **No** prometer ahorro de tokens (contra un baseline justo que ya pre-empaqueta, el efecto es
  ≈0/indetectable con reps realistas).
- **Sí** invertir en **precisión** (PRP LEAN por subtarea, validación ejecutable como autoridad,
  declaración explícita de contexto) y **trazabilidad** (handoff completo como lint/warn, no como gate que
  genere loops de reescritura).
- Prohibido el scope-creep que la medición descartó: vector store, versionado/merge de paquetes, capa
  multi-provider, volcado de contexto "por las dudas".

Detalle accionable en [`../ROADMAP-Y-PLAN.md`](../ROADMAP-Y-PLAN.md).

## 7. Lecciones de método (lo más transferible)
1. **Mide, no asumas.** Al menos 6 conclusiones intermedias atractivas cayeron al medir (incluida "hay
   paralela con caché caliente" y "el fork-warm es mejor").
2. **Verifica estado real** (git, `usage`), no el auto-reporte del agente — que llegó a *narrar* un
   worktree que no existía.
3. **Repite.** Un solo run con caché ruidoso (CV≈2×) miente; el promedio de reps corrige.
4. **Baseline justo.** Comparar contra un hombre de paja (worker "sin contexto") infla cualquier mejora.
5. **Gate adversarial.** Un retador que refuta y un auditor que reproduce atraparon errores que la
   confianza no habría atrapado.
