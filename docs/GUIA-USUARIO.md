# Guía de usuario — `/paralela`

Cómo correr `/paralela` de principio a fin, contado desde tu lugar: el **humano que supervisa**.
`/paralela` te convierte (a tu sesión Claude) en **orquestador**: descompone una tarea, lanza N
sub-sesiones (*workers*) en git worktrees separados y observables, auto-resuelve por gate lo que puede,
te escala solo lo que de verdad requiere tu decisión, e integra todo en una rama.

> **Antes de leer esto** conviene tener claro qué es el proyecto (README) y haber corrido `install.sh`.
> Detalle técnico de scripts y buzón: [`REFERENCIA.md`](REFERENCIA.md). Rationale de diseño:
> [`ARQUITECTURA.md`](ARQUITECTURA.md). Si algo se rompe: [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

---

## 1. ¿Cuándo usar `/paralela` (y cuándo NO)?

`/paralela` sirve para **una** cosa: repartir trabajo que **ESCRIBE** entre workers que corren **al mismo
tiempo**, sin pisarse. Eso solo tiene sentido si la tarea se parte en subtareas **genuinamente
independientes** que producen archivos.

> **Antes de nada — ¿tu trabajo es read-only?** Si es **investigar / buscar / auditar / mapear / revisar**
> (no escribe archivos), **`/paralela` NO es la herramienta**, aunque sea muy paralelizable. Eso se hace
> mejor con **fan-out directo de subagentes `Task`/`Explore`** (sin worktrees, más ligero): solo pídeselo
> al orquestador en lenguaje natural ("investiga A, B y C en paralelo y sintetiza"). `/paralela` es para
> el caso en que varios workers **escriben** a la vez. No confundas "read-only paralelo" con "secuencial":
> el read-only SÍ se paraleliza, pero por subagentes, no por worktrees.

**Úsalo cuando** el trabajo ESCRIBE, las subtareas no dependen unas de otras para empezar, y `Task`
nativo se queda corto por **al menos uno** de estos requisitos duros:

- **No particionable limpio:** varias subtareas editan **zonas solapadas del mismo repo** → necesitas
  aislamiento-FS por worktree. *(Si tocan **archivos distintos**, `Task` particiona: no necesitas paralela.)*
- **Durabilidad / observación en vivo:** los workers son **largos**; quieres que **sobrevivan** a una
  caída/compactación del orquestador, o **verlos/intervenirlos** en vivo.
- **Diálogo:** necesitas que un worker te **pregunte a mitad** (buzón ask/answer) o tomar el control de un pane.

Ejemplo típico: un **refactor grande** de un monorepo confiable, con módulos que se **tocan entre sí**
(solapamiento → aislamiento-FS) o lo bastante **largos** como para querer verlos en vivo. En cambio, tres
módulos en **tres archivos distintos y triviales** (sin solapamiento, cortos, sin diálogo) → `Task` con
partición es más ligero; ahí paralela sobra.

**NO lo uses cuando** las subtareas son **secuencial-dependientes**: si B necesita lo que produce A, o
dos subtareas editan el mismo archivo, los worktrees no te compran nada — solo te dan conflictos de
merge y trabajo tirado. En ese caso el orquestador **te lo dirá y propondrá hacerlo secuencial**; no
fuerces el paralelismo. El worktree se justifica **porque escriben en paralelo**, no por tamaño.

> Regla corta: **paraleliza por independencia real, no por tamaño de la tarea.**

---

## 2. Precondición dura: repos confiables + qué significa skip-permissions

Los workers corren con `--dangerously-skip-permissions`: **no** te piden confirmación por cada acción.
Eso es lo que los hace autónomos y observables sin que tengas que aprobar clic a clic — pero también
significa que un worker puede escribir/ejecutar dentro de su worktree sin freno interactivo.

Hay dos capas que acotan el riesgo (ver [`ARQUITECTURA.md`](ARQUITECTURA.md) y
[`REFERENCIA.md`](REFERENCIA.md) para el detalle H1–H5):

- Un **hook `PreToolUse` (guard)** que **bloquea mecánicamente** acciones externas del worker —
  `git push`, `curl`/`wget`/`nc`, `ssh`/`scp`, `sudo`, escrituras a rutas sensibles (`~/.ssh`,
  `~/.claude`, `.git/hooks`, `/etc`) — **aun bajo skip-permissions**.
- El worker trabaja **solo en su worktree**; la integración y el push los haces tú al final.

Aun así, esto **no es un sandbox**. La regla es innegociable:

> **Solo corre `/paralela` sobre repos que confías.** Nunca sobre código ajeno o sin revisar. Correr
> el acceptance y los tests ejecuta el código bajo prueba en tu máquina.

---

## 3. Prerequisites (bring-your-own runtime)

`/paralela` orquesta un runtime que **no** viene empaquetado. Necesitas tener listo (ver README →
Prerequisites):

1. El **CLI `claude`** (Claude Code) con acceso a red/API, y los skills instalados en `~/.claude/skills/`.
2. Un **launcher de sesiones en worktrees** (bring-your-own). Dado `-w <id>`, crea el worktree + rama,
   arranca ahí un worker `claude` con permisos, y reenvía los flags por lanzamiento (`--settings`,
   `--append-system-prompt`, `--model`). **El binario concreto NO se incluye** — es un contrato: sin
   launcher, `/paralela` no puede lanzar workers de verdad (ver
   [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) → *launcher ausente*).
3. Un skill **`revisar`** (o equivalente) para el gate CERRAR (retador + auditor read-only).
4. `python3`, `git`, `tmux`.

---

## 4. El flujo end-to-end, paso a paso

Lo que ves y haces tú, en orden. Los pasos internos del orquestador están en
[`../skills/paralela/SKILL.md`](../skills/paralela/SKILL.md).

### Paso 0 — Invocas

```
/paralela implementa mod-billing, mod-user y mod-order en acme-platform,
          cada uno siguiendo la convención de _core
```

### Paso 1 — El orquestador clasifica y descompone

Juzga el nivel (por defecto trabajo grande/alto-riesgo: automatización + config) y **anuncia qué gates
aplicará**. Explora el repo para trazar las costuras y propone una **partición** en subtareas, cada una
con un `<id>` único.

### Paso 2 — Te pide APROBAR la partición ⏸️

Esto es un **fork de definición**: el orquestador **para y te pregunta** antes de lanzar nada.
Verás algo como:

```
Partición propuesta (3 subtareas independientes, sin solapamiento de archivos):
  - billing  → packages/mod-billing/index.ts
  - user     → packages/mod-user/index.ts
  - order    → packages/mod-order/index.ts
Gates: IDEA (hecho) · CONSTRUIR (cada worker) · CERRAR (integración). ¿Apruebas?
```

Aquí decides: apruebas, ajustas los cortes, o dices "esto no es independiente, hazlo secuencial".
**Nada se lanza sin tu OK.**

### Paso 3 — Scout emite los PRP (F1, opcional)

Si hay varios workers que comparten contexto, el orquestador lanza **un scout** que explora el repo
**una vez** y emite por subtarea un `PRP-<id>.md` **LEAN** (Parallel Requirements Package): los
archivos/símbolos exactos, el **contexto declarado** (solo lo que esa subtarea usa) y el **criterio de
aceptación**. Un linter rechaza los PRP gigantes — el dump baja la precisión, por eso se penaliza el
tamaño. Con 1–2 workers o sin contexto compartido, el orquestador se salta el scout.

> El PRP **sustituye** al pre-empaquetado ad-hoc; su ganancia fiable es **precisión y trazabilidad**,
> **no** menos tokens (ver *Limitaciones*).

### Paso 4 — Lanza los workers observables

Por cada subtarea, el orquestador arranca (vía tu launcher) un worker en su worktree con el guard
(`--settings`) y las reglas duras (`--append-system-prompt`), y le incrusta su PRP. Cada worker:

- rama `worktree-<id>`, observable como `<repo>-<id>`, sesión tmux `<repo>_worktree-<id>`;
- reporta por un **buzón de archivos** (heartbeat, preguntas, done) — ver Paso 5.

### Paso 5 — Supervisas / respondes lo escalado 👀

El orquestador corre un bucle que revisa el buzón de cada worker (`$ORCH/<id>/`) y deriva su estado
**sin fiarse del worker** (liveness H1: pane de tmux + proceso vivo + mtime del último commit). Lo que
llega a **ti** depende de la clase de pregunta:

| El worker pregunta… | Quién resuelve |
|---|---|
| Trivial / factual / lectura de código | El orquestador, directo |
| Decisión de definición o sensible (trade-off de diseño) | El orquestador corre el **gate** (`revisar`: retador; +auditor si alto-riesgo) y sintetiza la respuesta |
| **Fork genuino de tu preferencia** / algo externo / irreversible / input que solo tú tienes | **Se te ESCALA a ti** (agrupado en un mensaje) |

O sea: **no te llega todo**, solo lo que de verdad necesita tu decisión. El resto se auto-resuelve por
gate. Los workers preguntan con un *handshake por bloqueo en archivo* (`ask-<seq>.json` → esperan tu
`answer-<seq>.json`); si nadie responde en el TTL (~15 min) el worker commitea su WIP, deja
`blocked.json` y termina para no colgar la sesión — el orquestador lo reanuda cuando tenga la respuesta.

### Cómo observar / interactuar directamente

No dependes solo del orquestador; la sesión es **observable y attachable**:

- **Móvil / web:** cada worker aparece como `<repo>-<id>` en remote-control (si tu launcher lo expone).
- **Terminal (tmux):** engánchate al pane con `tmux attach -t <repo>_worktree-<id>`, o mira la pantalla
  sin adjuntarte con `tmux capture-pane -p -t <repo>_worktree-<id>`. Lista sesiones con `tmux ls`.
- Si un worker se queda pidiendo algo **fuera del protocolo** (pregunta en lenguaje natural sin escribir
  `ask-<seq>.json`, o un prompt idle `❯`), el orquestador lee la pantalla y responde por `send-keys`; si
  es ambiguo, **te lo escala con el texto capturado** y tú puedes tomar control del pane directamente.

### Paso 6 — Integra por clon limpio + gate CERRAR

Cuando todos los workers vivos dejan su `done.json`, el orquestador integra en un **clon limpio** (no
opera sobre el `.git` compartido):

1. Trae cada rama `worktree-<id>`.
2. **Re-corre la validación (F2)** con **su** copia del acceptance (la que el worker no puede tocar) —
   la verdad es la validación re-corrida, **no** el auto-reporte del worker. Solo mergea las ramas que
   pasan.
3. Corre un **elevador de riesgo por rama** que fuerza auditor si el diff es de alto riesgo.
4. Corre el **gate CERRAR central (innegociable)**: revisión independiente del diff integrado completo
   (retador → auditor si hay duda o alto-riesgo) + los tests del repo.

### Paso 7 — PARA y te pide el push ⏸️

El orquestador **nunca** firma ni pushea solo. Te reporta el resultado (qué se integró, qué workers
fallaron si alguno, veredicto del gate) y **para a pedirte** el push/merge a la rama base. La última
palabra es tuya.

---

## 5. Ejemplo concreto — 3 módulos independientes

Basado en el repo de laboratorio `laboratorio/repo-sintetico` (`acme-platform`): un monorepo con un
módulo base `_core` y varios módulos de dominio que siguen su convención. Los módulos `mod-billing`,
`mod-user` y `mod-order` son **independientes** (archivos distintos, solo comparten la lectura de la
convención de `_core`) → caso ideal para `/paralela`.

**Tú:**

```
/paralela implementa los módulos mod-billing, mod-user y mod-order de acme-platform.
          Cada uno vive en su packages/mod-<dominio>/index.ts y DEBE seguir la
          convención del _core (Core.validate, Core.fail, Core.id(prefijo),
          async, register()).
```

**Lo que pasa:**

1. El orquestador explora, ve que los tres tocan archivos disjuntos y **propone la partición**
   `billing / user / order`. Te pide aprobar → **apruebas**.
2. Lanza **un scout** que lee `_core` y la convención **una vez** y emite `PRP-billing.md`,
   `PRP-user.md`, `PRP-order.md`, cada uno con: el archivo destino, la API de `Core` que usar, el
   prefijo de `id` correcto (`bill` / `usr` / `ord`) y el **criterio de aceptación** (el `check.sh` del
   repo verifica clase, `Core.validate`, `Core.fail`, prefijo, `async`, `register()`, y penaliza
   `console.`/`Math.random`/`Date.now`/`throw new Error`).
3. Lanza 3 workers en paralelo (`worktree-billing`, `worktree-user`, `worktree-order`). Tú los ves en
   tmux/móvil trabajando a la vez.
4. Uno pregunta algo trivial ("¿el `ErrorCode` para monto inválido es `INVALID`?") → el orquestador
   responde directo. Otro plantea un trade-off de diseño real → el orquestador lo pasa por el gate. Si
   alguno topara una decisión que solo tú puedes tomar, **te llega a ti**. En este ejemplo, nada
   requiere escalar.
5. Los 3 cierran con `done.json`. El orquestador integra en clon limpio, **re-corre el acceptance** de
   cada uno (los tres PASS), corre el gate CERRAR sobre el diff integrado + tests.
6. **Para y te pide** hacer el merge a `main`. Tú das el OK.

Resultado: tres módulos que **adhieren a la convención de forma consistente** (el valor primario medido:
precisión), integrados y revisados, con tu aprobación en los dos puntos que importan (partición y push).

---

## 6. Limitaciones honestas

`/paralela` es útil, pero no vende humo. Antes de esperar algo de él, ten claro:

- **No promete menos tokens.** El valor medido de F1/PRP y del contexto declarado es **precisión y
  auditabilidad**, no ahorro de tokens; el efecto en tokens es ≈0 / indetectable (medido — ver
  [`INVESTIGACION.md`](INVESTIGACION.md) y `laboratorio/RESULTADOS-PARALELA-PLUS-E2E.md`).
- **El path interactivo/observable se validó con un smoke en vivo** (launcher `claudea` → worktree+tmux,
  worker usando el buzón `status`→`done`, guard bloqueando un `push` real), pero la orquestación
  **completa** de N workers en una sola corrida viva NO se ejecutó (meta-riesgo: no correr paralela sobre
  sí misma; y es pesado). Puede haber fricción real en el flujo N-worker que el diseño no capturó.
- **El launcher NO viene incluido** (bring-your-own). Sin él, `/paralela` no lanza workers de verdad.
- La regla anti-narración de los workers (que no escriban prosa conversacional) es **pulido no medido**:
  no hay baseline que lo cuantifique; no lo trates como ahorro garantizado.
- Reproducir los números del `laboratorio/` requiere el runtime vivo (no es autocontenido).

Si algo no se comporta como esperas, empieza por [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).
