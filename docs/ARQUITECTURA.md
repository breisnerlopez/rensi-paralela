# Arquitectura y rationale — `rensi-paralela`

Este documento explica **qué diseño** tiene el orquestador y **por qué** cada decisión, anclando el
*porqué* en la evidencia de [`INVESTIGACION.md`](INVESTIGACION.md). La referencia mecánica precisa
(args, exit codes, formatos) vive en [`REFERENCIA.md`](REFERENCIA.md); aquí va el razonamiento.

**Titular honesto.** El aporte de `rensi-paralela` es **precisión, auditabilidad y supervisión
observable** del trabajo paralelo con agentes. **No** es un truco para ahorrar tokens: contra un
baseline justo que ya pre-empaqueta contexto, el efecto en tokens es ≈0/indetectable con repeticiones
realistas (medido — ver [`INVESTIGACION.md`](INVESTIGACION.md) §3). Vender ahorro de tokens sería
deshonesto; el proyecto no lo hace.

---

## 1. El modelo: cold + worktree + observable

Una sesión **orquestadora** descompone la tarea, lanza **N workers** (sub-sesiones `claude`), cada una
en su propio **git worktree** con su rama, todas **observables en vivo** (panel tmux + remote-control
móvil/web). El orquestador supervisa por un **buzón de archivos**, auto-resuelve por gate lo que puede,
escala al humano lo que debe, e **integra por clon limpio** en una sola rama con gate CERRAR + tests.

### Por qué cold (no warm-resume, no fork in-process)

La hipótesis intuitiva era "migrar a workers calientes que hereden caché para ahorrar". **La medición la
refutó** ([`INVESTIGACION.md`](INVESTIGACION.md) §2):

- **Warm-resume NO ahorra.** Claude Code incrusta el `cwd` en el system prompt **antes** del contenido.
  El mismo `cwd` que aísla un worktree es el que **invalida el caché** del contexto. Un worker que hace
  `--resume` en un worktree hereda el *contenido* pero **re-crea el caché** (medido: cache_read ~23.7k
  = solo bootstrap; cache_creation ~42.8k = recrea todo) → cuesta **MÁS** que un worker cold
  pre-empaquetado. El "muro estructural" hace que warm-en-worktree no sea una palanca.
- **El fork in-process SÍ preserva caché, pero NO es observable.** El fork con `isolation:worktree`
  hereda el system prompt del padre (con su `cwd`) y solo redirige escrituras (medido: lee ~63k de
  caché). Pero **vive dentro de la sesión** del orquestador → no es una sesión independiente,
  observable ni attachable por el humano. Y (§3 de la investigación) tampoco se traduce en ahorro
  práctico: el costo lo domina el **trabajo del agente** (multi-turno), no la entrega de contexto.

Conclusión de diseño: el modelo **cold + worktrees separados + observable** es correcto **por
observabilidad e independencia**, no por tokens. Su única palanca de tokens robusta —acotar el trabajo—
es ortogonal al mecanismo de entrega de contexto.

> **Honestidad sobre "más rápido":** la única medición wall-clock del repo (`laboratorio/RESULTADOS.md`,
> ~21s vs ~62s) es **cold-proc vs fork-in-process**, NO paralela-orquestador vs subagentes `Task` nativos
> (que también corren en paralelo). Frente a `Task` nativo, la velocidad **no está medida** — no la
> presentamos como ventaja establecida. La ventaja establecida de los workers en worktrees es de
> **capacidad** (aislamiento-FS + diálogo en vuelo + procesos durables/observables), no de velocidad.

### Por qué observable

A diferencia de los multiplexores de worktrees públicos (p.ej. claude-squad, Crystal, Uzi, ccswarm —
que **a la fecha de esta investigación (2026)** eran multiplexores de aislamiento sin buzón/gate/
integración automática; pueden haber evolucionado — verifica; [`INVESTIGACION.md`](INVESTIGACION.md) §5),
aquí el orquestador **descompone, supervisa, auto-resuelve por gate, escala al humano e integra**. Cada
worker es una sesión attachable: el humano puede tomar el control de un pane en cualquier momento (base
del guardarraíl H5). Esa observabilidad es un requisito de diseño, no un extra — es lo que permite el
handshake de preguntas y el escalamiento al usuario.

---

## 1.b Alcance real: un nicho, no un reemplazo general de subagentes

**Sé honesto sobre cuándo paralela gana y cuándo NO** (esto pasó por un gate adversarial retador→auditor
sobre la utilidad del propio proyecto). La mayoría del trabajo paralelizable **no necesita paralela**: la
regla por defecto (también en `~/.claude/CLAUDE.md`) es **subagentes nativos** (`Task`/`Explore`) —
worktrees solo si varios **escriben** en paralelo; en read-only o secuencial, worktree es desperdicio.

**Nicho donde paralela gana** — trabajo que **ESCRIBE** donde `Task` nativo se queda corto por **AL MENOS
UNO** de estos requisitos duros (basta uno; no hace falta la conjunción):
1. **Escrituras no particionables limpiamente:** varias subtareas editan **zonas solapadas del mismo
   repo** → necesitas **aislamiento-FS por worktree** (los subagentes `Task` comparten una sola
   working-copy y colisionarían). Si escriben **archivos distintos**, esto NO aplica: `Task` particiona.
2. **Workers durables:** procesos que **sobrevivan** al orquestador (compactación/caída) — los subagentes
   `Task` mueren con el turno del padre.
3. **Diálogo/observabilidad con workers vivos:** buzón ask/answer, tomar el control de un pane en vivo.

Si las subtareas escriben **archivos distintos, son cortas y sin diálogo** (ej. clásico: 3 módulos en 3
archivos), subagentes `Task` con partición **bastan** — no uses paralela. El caso de producción demostrado
(abajo) cumplía los tres a la vez, pero **cualquiera** de los tres justifica la maquinaria. (El rango
"pocas subtareas" es una regla de dedo, no una cifra medida.)

**Honestidad del diferenciador (medido vs asertado):**
- **Capacidad real, demostrada:** el aislamiento-FS por worktree y el diálogo-en-vuelo son cosas que
  `Task` nativo **no** puede dar, y se han ejercitado en **uso de producción real** (un refactor
  concurrente de un monorepo, particionado por módulo en worktrees separados, con buzón ask/answer vivo,
  observabilidad tmux, integrado y **pusheado a `main` tras el gate**). No es una feature buscando uso.
- **NO medido:** la ventaja **cuantitativa** de paralela frente a subagentes `Task` con partición (¿es más
  rápido? ¿menos overhead?) **no se ha A/B-medido**. La utilidad (capacidad) está demostrada; la
  *superioridad cuantitativa* sobre `Task` es un experimento pendiente (ver `ROADMAP-Y-PLAN.md`). No la
  vendemos como establecida.

---

## 2. Diseño de F1–F4 (objetivo: precisión + trazabilidad, NO tokens)

Las cuatro features de `paralela+` v0.2 existen para elevar **precisión** y **auditabilidad**, con
efecto en tokens deliberadamente ≈0. El diseño mecánico está en [`REFERENCIA.md`](REFERENCIA.md); aquí
el porqué.

### F1 · PRP (Parallel Requirements Package) — por PRECISIÓN

Un scout explora el repo **1×** y emite por subtarea un `PRP-<id>.md` **LEAN** (archivos/símbolos/
contexto declarado/criterio de aceptación). `prp_lint.sh` **rechaza** PRPs gigantes (>400 líneas /
>15000 chars).

**Por qué LEAN y no dump:** medido empíricamente ([`INVESTIGACION.md`](INVESTIGACION.md) §3), **volcar
contexto grande EMPEORA la precisión** — entierra lo clave; el worker que explora encuentra justo lo que
necesita. Por eso el linter **penaliza el tamaño**: un PRP grande casi siempre es un vertedero.

**Por qué no es "un extra encima":** el PRP es el **sustituto estructurado** del pre-empaquetado ad-hoc
que el orquestador haría igual (misma función, más consistencia y trazabilidad), no trabajo adicional.
Su ganancia fiable es precisión, **no** menos tokens. **Break-even del scout:** explora 1× y amortiza
sobre N workers; con N pequeño (≈1–2) o subtareas sin contexto compartido, el scout es costo neto → se
salta.

**Evidencia E2E** (`laboratorio/RESULTADOS-PARALELA-PLUS-E2E.md`): precisión PARALELA+ 9/9 a 6/6 con
stdev 0, vs. baseline mean 5.56 (4/9 sub-6). El PRP LEAN adhiere más consistente que el dump ad-hoc.

> **Qué mide (y qué NO) ese E2E — honestidad:** compara **PRP-LEAN vs dump ad-hoc**, y **ambos brazos son
> paralela** (`claude -p` en worktrees). La ganancia medida es de la **estructura LEAN**, no del mecanismo
> de paralelismo — es **ortogonal**: no hay razón mecánica conocida para que un subagente `Task` nativo con
> el mismo PRP LEAN no obtuviera la misma mejora de adherencia (el PRP es contenido de prompt, no depende
> del worktree) — **no se ha probado directamente**. Por tanto F1/F4 **no son evidencia de que los
> workers-en-worktree superen a `Task`
> nativo**; son una disciplina de prompting que paralela adopta. El diferenciador real de paralela es de
> **capacidad** (ver "Alcance real"), no de precisión.

### F2 · Validación como autoridad — por CONFIABILIDAD del "hecho"

Un worker puede reportar "hecho" sin que sea verdad. La verdad **no** es su auto-reporte: es un
acceptance **de autoría del orquestador**, **re-corrido** por el orquestador contra la rama. Detalle de
las decisiones de seguridad en §4. Evidencia: `accept_run` atrapa el defecto plantado que el self-report
deja pasar, sin falso positivo.

### F3 · Completitud del handoff — por TRAZABILIDAD (lint, no gate)

`handoff_complete.sh` **reporta** (WARN) secciones/campos faltantes del handoff, pero **exit siempre 0**
— no bloquea. **Por qué warn y no gate:** los handoffs estructurados **no ayudan al LLM downstream** (
prueba controlada: texto libre 3.0/3 ≈ schema 2.75/3, empate — [`INVESTIGACION.md`](INVESTIGACION.md)
§4); su valor es trazabilidad/auditoría para **humanos**. Bloquear forzaría a re-describir trabajo ya
commiteado = tokens sin mejora del resultado y loops de reescritura. Un `done.json` delgado ≠ trabajo
delgado.

### F4 · Contexto declarado — por PRECISIÓN

Sección obligatoria del PRP (`## Contexto necesario`) que declara **solo** lo que la subtarea usa. Misma
lógica que F1: menos ruido, más señal. No promete tokens.

---

## 3. El gate adversarial (disciplina de todo el ciclo)

El proyecto usa un gate **retador → auditor** en cada transición de etapa (idea → plan → construir →
cerrar). Los actores son read-only; **correr y juzgar** el gate es del orquestador (no se delega).

- **Retador** (adversarial): refuta el entregable de la etapa en vez de aprobarlo. Default escéptico.
  Modelo por criticidad (Sonnet normal, Opus en alto-riesgo).
- **Auditor** (2do nivel, Opus): solo si el retador deja duda **o** el cambio es de **alto riesgo**
  (security ∪ data ∪ config-prod) → auditoría obligatoria aunque el retador apruebe. Independiente del
  retador.

**Dónde aparece en `/paralela`:**
- **Auto-gate del worker (construir):** cada worker corre su propio retador sobre su **diff completo**
  (anti-sesgo de framing) antes de cerrar. Es un **primer-pase** que paraleliza la revisión y mejora el
  diff. El worker **nunca** lanza auditor (ese es central).
- **Supervisión (§5 SKILL.md):** las preguntas de los workers que son **decisiones de definición o
  sensibles** pasan por el gate antes de responderse; las triviales/factuales se responden directo; los
  forks de preferencia se **escalan al usuario**. Las preguntas internas de retador/auditor no
  re-disparan el gate (anti-recursión).
- **CERRAR central — INNEGOCIABLE y no delegable.** El auto-gate del worker es aditivo, **no** sustituye
  la revisión independiente del orquestador sobre el **diff integrado completo de contenido**. Un riesgo
  de contenido en ruta inocua que `diff-risk.sh` (ciego al contenido) no marca se atrapa **aquí**. El
  elevador `diff-risk.sh` **fuerza** el auditor si `RISK=high`, pero `RISK=normal` **no** exime del
  CERRAR de contenido (es elevador, no filtro).

---

## 4. Decisiones de seguridad (pasaron por gate adversarial)

Estas decisiones fueron **refutadas y corregidas** en el gate CERRAR de Fase 2 (ver el re-freeze en
[`DISENO-INTERFACES.md`](DISENO-INTERFACES.md) §WS-B). Son el núcleo de la robustez de F2.

### 4.1 Acceptance de autoría-orquestador (NO worker-autora)

**Modelo original refutado:** "el worker ships `acceptance.sh` en su worktree". Era **auto-reporte** —
el mismo agente que hace el trabajo escribiría el test que lo aprueba (podría shipear un
`echo PASS; exit 0`) — y un hueco de seguridad (re-ejecutar bytes autoría-worker). **Corrección:** el
acceptance lo **autora el orquestador** como parte del PRP (subagente scout barato), no el worker ni el
humano. El criterio de verdad es **independiente de quien lo cumple**: si el worker deja el trabajo mal,
el acceptance —que él no escribió— lo delata. Autoridad > auto-reporte.

### 4.2 Ruta canónica FUERA del buzón + re-materialización fresca

El acceptance canónico vive en una ruta orquestador-**EXCLUSIVA** `$ORCH/acceptance/<id>.sh`, **nunca**
en `$ORCH/<id>/` (buzón del worker) ni en el worktree — **ambos escribibles por el worker**. Si la copia
"canónica" viviera ahí, el worker podría sobreescribirla con un `echo PASS; exit 0` + payload y reabrir
el bypass que F2 cierra. Antes de re-correr, el orquestador **re-materializa el acceptance fresco** desde
su copia del PRP (la que retiene), sobreescribiendo cualquier manipulación. La señal `--no-acceptance` y
la ruta también se derivan del PRP (fuente que el orquestador controla), nunca de un archivo del worktree.

### 4.3 `timeout` y fail-closed

`accept_run.sh` corre el acceptance bajo `timeout` (`ACCEPT_TIMEOUT`, def. 120 s) para acotar cuelgue/
DoS. Toda anomalía (exit ≠ 0/2, timeout, 1ª línea incoherente con el exit, falta de argumento, worktree/
script inexistente) → **FAIL** (fail-closed). Un acceptance que no afirma `PASS` limpiamente no pasa.
Igual `diff-risk.sh`: ante cualquier error o diff sospechoso → `RISK=high` (fuerza auditor).

### 4.4 Validar-antes-de-mergear

La integración es por **clon limpio** (`git clone` a `$ORCH/integra`, `core.hooksPath` vaciado — no se
opera sobre el `.git` compartido). **Antes** de mergear cada rama, el orquestador re-corre su acceptance
canónico (F2): `PASS` → candidata a merge; `FAIL` → no se mergea hasta resolver; `SKIP` → su verificación
recae en el CERRAR de contenido. Es un smoke-test por-rama **temprano** (atrapa el defecto barato, antes
de integrar), que **no** sustituye el CERRAR integral. La base del `diff-risk.sh` es la **merge-base
real** de integración, nunca un valor provisto por el worker.

### 4.5 Guardarraíles del worker (H3/H4/H5) y push manual

Los workers corren con `--append-system-prompt` (H3, reglas duras) + `--settings` con `worker-guard.py`
(H4, hook `PreToolUse` que **deniega mecánicamente** push/red/escalada/rutas sensibles, aun bajo
skip-permissions). H5 captura preguntas fuera de protocolo por lectura de pantalla tmux. El push/merge a
la rama base es **siempre manual** — el orquestador reporta y para; nunca firma ni pushea solo.

### 4.6 Residual aceptado (bajo precondición repos-confiables)

Correr el acceptance (F2) y la suite en el CERRAR **ejecuta el código del worktree bajo prueba** — el
**mismo sobre de riesgo** que el gate CERRAR corriendo la suite del repo sobre el merge. `accept_run.sh`
**no es un sandbox**. Este residual se **acepta explícitamente** bajo la **precondición dura** de
`/paralela`: se corre **solo sobre repos confiables**, y los workers usan `--dangerously-skip-permissions`
sin aislamiento fuerte, riesgo asumido de forma informada. La mitigación no es aislamiento (declinado por
el usuario) sino: lógica de test autoría-orquestador + `timeout` + denylist H4 + repos confiables. Para
contención total haría falta contenedor/usuario dedicado — fuera de alcance por decisión informada.

---

## 5. Prerequisites del runtime (qué se bundlea y qué es externo)

`rensi-paralela` bundlea su lógica **y** el gate adversarial completo; lo único externo es el runtime
vivo (CLI + utilidades de sistema). `install.sh` coloca lo bundleado en tu `~/.claude/`:

1. **`claude` CLI** (Claude Code) con acceso a API/red — externo. `install.sh` instala los skills en
   `~/.claude/skills/`.
2. **Un launcher de sesiones en worktrees** (`<launcher>` en SKILL.md): dado `-w <id>`, crea
   worktree+rama, arranca un worker `claude` con permisos y reenvía los flags por-lanzamiento
   (`--settings`, `--append-system-prompt`, `--model`). El repo **incluye un launcher de referencia**
   (`launcher/claudea`) que `install.sh` instala en `~/.local/bin/claudea` **solo si no hay ninguno**
   (respeta un `claudea` en el PATH, un `$PARALELA_LAUNCHER` o el archivo destino ya existente; nunca
   sobreescribe el tuyo). Flags: `--no-launcher` para omitirlo, `--launcher-dest <ruta>` para el destino.
   El launcher de referencia es **genérico** (sin usuario/sudo/bootstrap hardcodeados) → puede requerir
   **adaptación al entorno**: esa adaptación es la limitación honesta, no su ausencia.
3. **El gate CERRAR viene bundleado** (ya no es bring-your-own): `install.sh` instala el skill
   `skills/revisar/`, los agentes `agents/{retador,auditor}.md` y las 12 lentes de `review/lenses/`
   (`_base.md` + `dim/*` + `etapa/*`) en `~/.claude/`. Funciona out-of-the-box. Su **calidad** depende de
   tener buenos lentes/agentes — que ahora se incluyen; puedes ajustarlos a tu criterio.
4. **`python3`, `git`, `tmux`** — externo.

**Limitaciones honestas** (regla del proyecto; ver [`INVESTIGACION.md`](INVESTIGACION.md) y el README):
el path interactivo/observable (launcher + buzón + guard + autonomía del worker) se validó con un **smoke
en vivo** (worktree+tmux, `status`→`done`, push bloqueado por el guard), pero la orquestación paralela+
**completa** de N workers no se corrió como una sola sesión viva (meta-riesgo: no correr paralela sobre sí
misma); el launcher incluido es **de referencia y genérico** (puede requerir adaptación a tu entorno, no
garantiza correr tal cual); el `laboratorio/` requiere el runtime vivo para reproducir números; la regla
anti-narración de workers es pulido **no-medido** (sin baseline), no un ahorro vendible.
