---
name: paralela
description: Orquesta trabajo en paralelo lanzando N sub-sesiones Claude (workers), cada una en su propio git worktree y observable en móvil/web (remote-control), mientras la sesión principal supervisa, auto-resuelve por gate adversarial las preguntas que pueda, escala al usuario solo lo que de verdad lo necesita, e integra todo en una sola rama con gate CERRAR + tests. Úsalo cuando el usuario pida paralelizar una tarea descomponible en subtareas genuinamente independientes.
argument-hint: "<descripción de la tarea a paralelizar>"
---

Este skill te convierte en **ORQUESTADOR** de `$ARGUMENTS`. Tú NO ejecutas el trabajo de las
subtareas: lo hacen los workers. Te reservas el juicio (partición, gate, integración) y delegas
el resto. **Nunca** firmes/pushees/deploys sin que el usuario lo pida (regla Git global).

**Precondición dura:** solo sobre **repos confiables**. Los workers corren con
`--dangerously-skip-permissions` sin aislamiento fuerte; asume ese riesgo de forma informada antes de
lanzar. No lances `/paralela` sobre código ajeno/no revisado.

## 1. Clasifica y anuncia gates
Trabajo grande/alto-riesgo por defecto (automatización + config). Anuncia al usuario los gates que
aplicarás (idea ligero ya hecho al definir la tarea; **CONSTRUIR** en cada worker es responsabilidad
del worker vía su propio ciclo; **CERRAR** en la integración). El usuario puede objetar.

## 2. Descompón (tu decisión) y pide aprobación
Parte la tarea en subtareas **genuinamente independientes** — sin solapamiento de archivos; worktree
solo se justifica porque escriben en paralelo. Si no son realmente independientes, dilo y propón
secuencial (no fuerces worktrees). Asigna a cada subtarea un `<id>` **único**, saneado a `[a-z0-9_-]`
y que **empiece por alfanumérico** (el launcher valida el nombre del worktree y rechaza espacios/símbolos;
un id que empieza con `-` lo tomaría el launcher como flag). Explora el repo (delega a subagentes
Explore) para trazar las costuras. **Presenta la partición al usuario y ESPERA aprobación** (es un
fork de definición: parar-y-preguntar).

**F1 · PRP por subtarea (precisión).** Tras aprobar la partición, lanza **un scout** (subagente
Explore, explora el repo **1×**) siguiendo `"$SKILL_DIR/scout-prompt.md"`: emite por subtarea un
`PRP-<id>.md` **LEAN** (plantilla `"$SKILL_DIR/prp-template.md"`) con archivos/símbolos exactos,
**contexto necesario declarado** (F4: solo lo que la subtarea usa) y **criterio de aceptación** (F2).
Valida cada uno con `"$SKILL_DIR/prp_lint.sh" PRP-<id>.md` (exit≠0 = falta una sección obligatoria o
es un **dump gigante** → arréglalo; medido: el dump baja precisión, por eso el linter penaliza tamaño).
El PRP es el **sustituto estructurado** del pre-empaquetado ad-hoc (misma función, más consistencia y
trazabilidad), **no un extra encima** — su ganancia fiable es **precisión**, no menos tokens.
**Break-even del scout:** explora 1× y amortiza sobre N workers; si N es pequeño (≈1-2) o las subtareas
no comparten contexto, **sáltalo** y pre-empaqueta ad-hoc como en §4 (el scout sería costo neto).

## 3. Prepara el buzón y los guardarraíles
`SKILL_DIR` = el directorio donde está instalado este skill (los archivos `orch-lib.sh`,
`worker-guard.py` y `diff-risk.sh` vienen con él; en Claude Code suele ser `~/.claude/skills/paralela/`).
```
SKILL_DIR="${SKILL_DIR:-$HOME/.claude/skills/paralela}"   # dir de este skill (bundled)
ORCH="${TMPDIR:-/tmp}/paralela/<task-slug>"; mkdir -p "$ORCH/bin"
cp "$SKILL_DIR/orch-lib.sh" "$ORCH/bin/orch-lib.sh"
# H4: settings por-lanzamiento con el hook PreToolUse que BLOQUEA acciones externas del worker.
# Verificado: se mergea con otros hooks globales del entorno (no los pisa) y deniega incluso bajo skip-permissions.
GUARD="$SKILL_DIR/worker-guard.py"
cat > "$ORCH/bin/guard-settings.json" <<JSON
{"hooks":{"PreToolUse":[{"matcher":"Bash|Write|Edit|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"python3 $GUARD"}]}]}}
JSON
```
Por worker: `$ORCH/<id>/`. Contrato de archivos (todos **atómicos**, vía `atomic_write`/`emit_json`):
`status.json` (heartbeat), `ask-<seq>.json` (pregunta), `answer-<seq>.json` (respuesta, texto plano),
`done.json` (rama+resumen), `blocked.json` (TTL vencido).

## 4. Lanza los workers (con guardarraíles)
Desde la raíz del repo, por cada subtarea, lanza un worker observable **con `--settings` (H4) y
`--append-system-prompt` (H3)**. Aquí `<launcher>` es tu **lanzador de sesiones en worktrees**
(bring-your-own; ver Prerequisites): dado `-w <id>`, crea un git worktree con su rama, arranca ahí un
worker `claude` con permisos apropiados, y reenvía los flags por-lanzamiento (`--settings`,
`--append-system-prompt`, `--model`). Incrusta rutas ABSOLUTAS ya expandidas (el shell del worker no tiene
`$ORCH`; si pasas la variable se evalúa vacía y no encuentra su buzón):
```
<launcher> -w <id> \
  [<flag-de-proveedor> <workers-provider>] \   # OPCIONAL: solo si el usuario pidió workers en otro backend (ver abajo)
  --model sonnet \
  --settings "$ORCH/bin/guard-settings.json" \
  --append-system-prompt "Eres un WORKER de /paralela. REGLAS DURAS: trabaja solo en tu worktree; NUNCA acciones externas (push/deploy/red/sudo/tocar ~/.ssh,~/.claude,.git/hooks); ante decisión genuina NO adivines, usa el protocolo ask. Un hook PreToolUse bloquea mecánicamente las acciones externas. SÉ DIRECTO: sin preámbulos ni recapitulaciones conversacionales (nadie las lee en vivo; el orquestador solo lee tus archivos del buzón) — pero mantén COMPLETOS status.json, ask, y el summary/veredicto de done.json, y no recortes tu razonamiento." \
  "Invoca el skill worker-protocol y síguelo. Contexto: id=<id>; box=/ruta/abs/orch/<id>; rama=worktree-<id>; subtarea: <descripción precisa y acotada>. BLUEPRINT (F1) — respétalo (archivos/símbolos/contexto declarado/criterio de aceptación): <<pega aquí el contenido de PRP-<id>.md>>."
```
- **F1 en el prompt:** si corriste el scout, **incrusta el `PRP-<id>.md`** en el prompt del worker (es
  el pre-empaquetado estructurado; reemplaza al ad-hoc, no lo suma). Sin scout, pre-empaqueta ad-hoc
  como describe la sección "Eficiencia de tokens".
- **F2 · acceptance autoría-orquestador:** el `## Criterio de aceptación` del PRP lo **autoraste tú**
  (scout), NO el worker. **Extrae ese acceptance a una ruta orquestador-EXCLUSIVA, FUERA del buzón del
  worker** `$ORCH/<id>/` (que el worker escribe por protocolo). Usa `$ORCH/acceptance/<id>.sh` —
  **nunca** `$ORCH/<id>/...`: si la copia "canónica" viviera en el buzón, el worker podría sobreescribirla
  con un `echo PASS; exit 0` + payload y reabrir el bypass que F2 cierra. Esa copia exclusiva es la que
  re-correrás en §6. El worker puede correr su copia del PRP como smoke-test, pero **la autoridad es tu
  re-corrido de la copia que él no puede tocar**, no su palabra ni un archivo de su worktree/buzón.
- **H4 `--settings`**: hook PreToolUse que **deniega** push/red/escalada/rutas sensibles — control mecánico
  (verificado: bloquea aun con skip-permissions y se mergea con otros hooks del entorno). Es defensa-en-profundidad (denylist), no jaula.
- **H3 `--append-system-prompt`**: reglas duras a nivel system-prompt (refuerzo de saliencia; el control duro es H4).
- Ambos son flags por-lanzamiento reenviados por el launcher → **cero huella en tus sesiones normales**.
- **Modelo por criticidad (eficiencia de tokens):** por defecto `--model sonnet` — los workers son el grueso
  del consumo (~67% del output + del cache_read medido) y Sonnet es ~5× más barato que Opus. **Escala esa
  subtarea a `--model opus`** solo si es crítica (alto-riesgo: security/data/config-prod, o grande /
  baja-reversibilidad). El **orquestador** (esta sesión) y el **auditor central** se quedan en Opus por criticidad.
- **Backend alternativo por worker (OPCIONAL, si tu launcher lo soporta):** si el usuario pide que **los workers**
  usen otro proveedor de modelo y tu launcher expone un flag para ello (bring-your-own; ver Prerequisites), captura
  `<workers-provider>` y añádelo a **cada** invocación del launcher. La idea es que `--model sonnet` se remapee al
  modelo equivalente del proveedor vía la **config de proveedor (opcional)** de tu entorno. **Tú, el orquestador, NO
  cambias de backend** — sigues en el proveedor con que se lanzó esta sesión (Opus para el juicio: partición, gate
  CERRAR, auditor central). Solo los workers cambian. **Salvedades:** (a) contra un host no-Anthropic el worker puede
  **perder Remote Control** (observabilidad móvil), pero tu supervisión NO depende de eso — la liveness (H1) usa panel
  tmux + buzón de archivos, que siguen; (b) verifica que el modo worktree de tu launcher no colisione con sus otros
  guards de continuidad; (c) requiere la config de proveedor + su credencial (si falta, el worker debería abortar
  fail-closed y lo verás como `failed`, no como sesión colgada).
Notas: rama `worktree-<id>`; observable como `<repo>-<id>`; sesión tmux = `<repo>_worktree-<id>`;
lanzamiento concurrente seguro (flock); no bloquees tu shell (verifica `tmux ls`). Respuestas a los
workers (`answer-<seq>.json`) = **texto plano** vía `atomic_write`; el worker las usa tal cual.

## 5. Supervisa (bucle event-driven)
Re-despiértate (Monitor/ScheduleWakeup) y en cada tick **DELEGA a un subagente efímero** la
lectura+digest de `$ORCH/*/`, que te devuelva un resumen compacto — así tu contexto crece
~O(decisiones), no O(ticks×workers). **H1 — liveness que NO depende del worker** (el `status.json` es
solo una pista): deriva el estado real de señales que el worker no controla —
(a) `tmux display -p -t <repo>_worktree-<id> '#{pane_dead}'` y `pgrep -f "worktrees/<id>"` (¿vivo?);
(b) mtime del último commit en `worktree-<id>` (¿progresa?). **Regla anti-falso-positivo:** solo infiere
"atascado" por falta de progreso si NO hay un `ask-<seq>` sin `answer` — un worker en `orch_wait`
esperando respuesta (hasta TTL, ~15 min) legítimamente no commitea. Con el digest:
- **`ask-<seq>.json` pendiente** → clasifica la pregunta y responde escribiendo atómico
  `$ORCH/<id>/answer-<seq>.json`:
  - trivial / factual / lectura de código → responde directo.
  - **decisión de definición o sensible** → corre el gate (skill `revisar`: retador; +auditor si
    alto-riesgo) sobre la pregunta y sintetiza la respuesta con el veredicto como insumo.
  - **fork genuino de preferencia / externo / irreversible / input solo-del-usuario** → **ESCALA al
    usuario** (agrupa varias pendientes en un solo mensaje). No inventes lo que solo el usuario decide.
  - Las preguntas internas de retador/auditor NO re-disparan el gate (anti-recursión).
- **`blocked.json`** (worker cerró por TTL) → cuando tengas la respuesta, reanúdalo (`claude --resume`)
  o ciérralo y reasigna.
- **`done.json` presente — completitud del handoff (F3, LINT/WARN, NO gate):** el digest corre
  `"$SKILL_DIR/handoff_complete.sh" <handoff>` y **surface el WARN** al monitorear (secciones/campos
  faltantes para trazabilidad). **Nunca reabre ni rechaza** al worker por esto (exit siempre 0; un
  `done.json` delgado ≠ trabajo delgado) — es señal para el humano que monitorea, no un bloqueo.
- **worker muerto / `pane_dead`=1 / heartbeat vencido** → márcalo `failed`; la integración procede con
  los vivos y **reporta** cuáles fallaron.
- **H5 — pregunta/permiso FUERA de protocolo** (el buzón NO lo captura): un worker puede preguntar en
  lenguaje natural o colgarse tras un deny/permiso **sin** escribir `ask-<seq>.json`. Cuando H1 detecta
  "atascado" (vivo + sin progreso + **sin `ask` pendiente**), NO asumas que trabaja — **lee la pantalla
  real**: `tmux capture-pane -p -t <repo>_worktree-<id>`. Si muestra una pregunta o un prompt `❯` idle:
  - clasifícala igual que un `ask` (trivial→directo / definición→gate / fork→escala al usuario);
  - **responde por send-keys en DOS pasos** (verificado: `send-keys "txt" Enter` junto NO envía —
    hay que separar): `tmux send-keys -t <ses> "<respuesta>"` → `sleep 2` → `tmux send-keys -t <ses> Enter`;
    **re-captura** con `capture-pane` para confirmar que se procesó;
  - si es ambiguo o el send-keys no toma, **ESCALA al usuario con el texto capturado** — la sesión es
    observable/attachable y el humano puede tomar el control directo del pane.

## 6. Integra — CERRAR central INNEGOCIABLE (tuya; el auto-gate del worker es aditivo, no lo sustituye)
El auto-gate de cada worker es un **primer-pase**: paraleliza y entrega diffs mejorados, pero **NO
reemplaza** tu revisión independiente. Cuando todos los vivos tengan `done.json`:
0. **Lee el `gate_refutacion` REAL de cada worker** (su contenido, no solo el booleano) — es insumo de
   tu juicio, nunca un semáforo en el que confíes ciegamente.
1. **Clon LIMPIO** (no operes en el `.git` compartido):
   ```
   git clone <repo> "$ORCH/integra" && cd "$ORCH/integra"
   mkdir -p "$ORCH/empty-hooks" && git config core.hooksPath "$ORCH/empty-hooks"
   ```
2. `git fetch <repo> worktree-<id>:worktree-<id>` por worker vivo; crea rama integradora `<task-slug>`.
   **Aún NO mergees** — primero valida cada rama (2b).
2b. **Validación-autoridad (F2) — ANTES de mergear, la verdad es la validación, no el auto-reporte.**
   Por cada rama viva, con la rama en un checkout/worktree, **re-materializa el acceptance FRESCO desde
   TU copia del PRP** (la que tú retienes, no un archivo del worker) a la ruta orquestador-exclusiva
   `$ORCH/acceptance/<id>.sh` — re-escríbela justo antes de correr, sobreescribiendo cualquier
   manipulación. Luego re-corre: `"$SKILL_DIR/accept_run.sh" <checkout-de-worktree-<id>>
   <$ORCH/acceptance/<id>.sh>`. **Nunca** apuntes a `$ORCH/<id>/...` (buzón escribible por el worker) ni
   a un `acceptance.sh` del worktree. Si el PRP declaró `acceptance: no-acceptance`, pasa
   `--no-acceptance` en su lugar (deriva la señal del PRP, no del worktree). Interpreta: `PASS` → la rama es candidata a merge; `FAIL`/exit 2 → **no la mergees**
   hasta resolver (subagente arregla, tú juzgas; ambiguo → escala); `SKIP (no-acceptance)` → sin
   smoke-test propio, su verificación recae en el CERRAR de contenido (paso 4). **Seguridad:** correr el
   acceptance ejecuta el código del worktree bajo prueba (mismo sobre que el CERRAR corriendo la suite
   del repo); la lógica de test es **tuya** (no del worker) y va bajo `timeout` — precondición repos
   confiables, no es sandbox.
2c. **Mergea solo las ramas `PASS`/`SKIP`** en orden sobre `<task-slug>`. Conflicto → subagente resuelve,
   tú juzgas; semántico/ambiguo → escala. Esto es **smoke-test por-rama temprano** (atrapa el defecto
   antes de integrar, barato); **no** sustituye el CERRAR integral del paso 4.
3. **Elevador de riesgo por rama (mecánico, fail-closed):** por cada rama corre
   `"$SKILL_DIR/diff-risk.sh" <merge-base-CONFIABLE> worktree-<id>` (script incluido con este skill) — la base es la real de
   integración (`git merge-base <base> worktree-<id>`), **NUNCA** un valor provisto por el worker.
   `RISK=high` → **auditor central (Opus) obligatorio** sobre esa rama, al que le pasas el **diff final
   completo** (no el resumen del worker). El worker NUNCA lanza auditor. `diff-risk` es un ELEVADOR
   (fuerza auditor), **NO un filtro**: `RISK=normal` **NO** exime del CERRAR de contenido del paso 4.
4. **Gate CERRAR central (INNEGOCIABLE):** corre `revisar cerrar` leyendo el **diff integrado COMPLETO
   de contenido**, de forma independiente (retador → auditor si high o queda duda). Los workers hicieron
   un primer-pase; **la revisión independiente de TODO el contenido es tuya y no se delega ni se
   sustituye por confiar en ellos** (un riesgo de contenido en ruta inocua que `diff-risk` no marca se
   atrapa aquí). + tests del repo. **Verificación por veredicto (tokens):** no corras build/tests
   pesados (`turbo build`, `pnpm test`, con logs de 10-15K chars) en TU hilo — **delégalos a un
   subagente efímero** que ejecute y devuelva solo `PASS/FAIL + ≤5 líneas del fallo`, no el log. El
   juicio del gate es tuyo; el log crudo no debe residir en tu contexto.
5. **Reporta y PARA** a pedir el push/merge a la rama base (nunca firmes ni pushees solo).

## 7. Limpieza
Por worker: **mata el PROCESO** del worker (`pkill -f "worktrees/<id>"` o el pid) — `tmux
kill-session` NO basta: el `claude` sobrevive detached y retiene el lock del worktree. Luego
`git worktree remove -f -f <path>` + `git worktree prune` + `git branch -D worktree-<id>`, y borra `$ORCH`.
Direccionamiento útil (medido): sesión tmux del worker = `<repo>_worktree-<id>`; remote-control = `<repo>-<id>`.

## Eficiencia de tokens (aplica a ti y a los workers)
- **Explora con tools nativas `Read`/`Grep`/`Glob`**, no `cat`/`grep`/`find` en Bash: son más compactas y
  paginables. Si tu entorno usa un **reescritor/compresor de comandos** (un hook que comprime la salida de
  `grep`/`git`/`find`), en Bash encadena con `&&`/`;` (**no** salto de línea) para que alcance; no antepongas
  `cd` innecesario.
- **Pre-empaqueta el contexto compartido UNA vez** en el prompt de cada worker (layout de `packages/`,
  `tsconfig`/`workspace` relevante, contenido de scripts/documentos que si no releerían N workers a
  20K chars cada uno, y la lista de consumidores/imports por módulo que ya trazaste). Evita que cada
  worker rehaga el mismo `grep` repo-wide.
- **Salida cruda de build/test = coste puro.** Aunque uses un compresor de comandos, muchos NO capturan
  `node …`, heredocs `python3` ni `pnpm build|test` genéricos (pasan la salida cruda); típicamente solo
  comprimen `pnpm install`/`lint`/`tsc`/test-runners con parser. En workers y en ti, canaliza esa salida
  (`| tail`/`| grep`), nunca cruda. En workspaces pnpm usa `pnpm install --frozen-lockfile` (por worker) —
  evita el conflicto de lock y el output de árbol de deps que se repite por worker.
- **Verificación por veredicto:** delega builds/tests a un subagente que devuelva PASS/FAIL, no el log
  (ver §6.4). Igual para el digest de supervisión (§5).

---
**Invariantes:** repos confiables · workers sin acciones externas · buzón siempre atómico ·
integración por clon limpio · push manual · exploración con tools nativas · verificación por veredicto ·
PRP LEAN (no dump, F1) · validación re-corrida por el orquestador (F2) · completitud del handoff = warn, no gate (F3).
