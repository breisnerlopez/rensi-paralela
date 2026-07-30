# Referencia técnica — `rensi-paralela`

Referencia precisa de los ejecutables, el contrato del buzón, los guardarraíles y los formatos de
archivo. Todo lo de aquí está verificado contra el código fuente en
[`../skills/paralela/`](../skills/paralela/) y [`../skills/worker-protocol/`](../skills/worker-protocol/).

Para el diseño y el *porqué* de estas decisiones, ver [`ARQUITECTURA.md`](ARQUITECTURA.md). Para el
contrato de interfaces congelado en Fase 0 (histórico), ver [`DISENO-INTERFACES.md`](DISENO-INTERFACES.md).

Convención de exit codes usada en el proyecto: **`0` = éxito/PASS/SKIP/OK**, **`1` = rechazo de lint**,
**`2` = FAIL de validación o error de uso**. El detalle exacto por script está abajo.

---

## 1. Ejecutables

### 1.1 `prp_lint.sh <PRP.md>` — linter del PRP (F1)

Fuente: [`../skills/paralela/prp_lint.sh`](../skills/paralela/prp_lint.sh). Valida que un PRP
(Parallel Requirements Package) sea **LEAN** y esté completo. `set -euo pipefail`.

**Argumentos:** exactamente uno, la ruta al `PRP-<id>.md`.

**Qué valida:**
1. **Secciones obligatorias** — las 5 con título de nivel `##` **exacto** (match de línea completa,
   permite espacios finales, no prefijo):
   `## Objetivo`, `## Archivos`, `## Símbolos`, `## Contexto necesario`, `## Criterio de aceptación`.
2. **Penalización anti-dump (tamaño):** RECHAZA si el archivo supera **400 líneas** (`MAX_LINES`)
   **o** **15000 caracteres** (`MAX_CHARS`). El conteo de chars usa `wc -m` (locale UTF-8) y cae a
   `wc -c` (bytes) si `wc -m` falla. Son cotas independientes: basta superar una.

**Exit codes:**

| Exit | Significado |
|------|-------------|
| `0`  | OK — LEAN y todas las secciones presentes. Imprime `OK: … pasa el linter (…)`. |
| `1`  | RECHAZADO — falta ≥1 sección **o** es un dump gigante. Imprime qué faltó / por qué. |
| `2`  | Error de uso — falta el argumento o el archivo no existe (mensaje a `stderr`). |

Nota: un PRP puede fallar por secciones y por tamaño a la vez; imprime ambos motivos y sale `1`.

### 1.2 `accept_run.sh <ruta-worktree> <acceptance-script | --no-acceptance>` — validación como autoridad (F2)

Fuente: [`../skills/paralela/accept_run.sh`](../skills/paralela/accept_run.sh). Lo corre el
**orquestador** para validar la rama de una subtarea re-ejecutando el acceptance **de autoría del
orquestador** con `cwd = raíz del worktree`. `set -uo pipefail` (nota: **no** `-e`, para poder
capturar el exit del acceptance y clasificarlo).

**Argumentos (2, ambos obligatorios):**
- `<ruta-worktree>` — directorio del checkout de la rama a validar. Debe existir y ser directorio.
- `<acceptance-script | --no-acceptance>` — o la ruta a un script de acceptance **orquestador-side**
  (nunca del worktree/buzón), o el literal `--no-acceptance`.

**Variables de entorno:**
- `ACCEPT_TIMEOUT` — segundos de límite para el acceptance (default **`120`**). Acota cuelgue/DoS.
  Si el binario `timeout` no está disponible, se corre **sin** límite (degradación). Nota: el exit `124`
  se interpreta como timeout → `FAIL`; si el propio acceptance saliera con `124` por otra causa, también
  se trata como `FAIL` (fail-closed, sin impacto de seguridad — nunca convierte un fallo en PASS).

**Comportamiento:** absolutiza la ruta del script **antes** de cambiar de cwd; lo corre con
`bash` explícito desde `cd "$wt"` bajo `timeout "$ACCEPT_TIMEOUT"`; captura `stdout+stderr` y toma la
**1ª línea** como veredicto reclamado. Fail-closed en toda anomalía.

**Matriz de resultados / exit codes:**

| Situación | Salida (1ª línea) | Exit |
|-----------|-------------------|------|
| `--no-acceptance` | `SKIP (no-acceptance)` | `0` |
| acceptance sale `0` **y** su 1ª línea es exactamente `PASS` | `PASS` (+ detalle relayado) | `0` |
| acceptance sale `0` pero 1ª línea ≠ `PASS` (incoherente) | `FAIL` | `2` |
| acceptance sale `2` (FAIL declarado) | `FAIL` (relayado tal cual) | `2` |
| acceptance excede `ACCEPT_TIMEOUT` (`timeout` devuelve `124`) | `FAIL` | `2` |
| acceptance sale con exit anómalo (crash, `exit 1`, ≠0,2) | `FAIL` | `2` |
| falta 2º argumento, worktree inexistente, o script inexistente | `FAIL` | `2` |

**Regla de coherencia (fail-closed):** un `exit 0` que no imprime `PASS` en la 1ª línea se trata como
FAIL. Un acceptance que no puede afirmar `PASS` limpiamente **no pasa**. Con `--no-acceptance` la
verificación cae al gate CERRAR central (no bloquea la integración).

**Nota de seguridad (precondición: repos confiables).** Correr el acceptance **ejecuta el código del
worktree bajo prueba** — el mismo sobre de riesgo que el gate CERRAR corriendo la suite del repo sobre
el merge. `accept_run.sh` **no es un sandbox**. Mitigaciones: (a) la lógica de test es
**autoría-orquestador**, no del worker → no existe el bypass "PASS falso + payload" vía el propio
script; (b) `timeout` acota cuelgues/DoS; (c) la precondición dura de `/paralela` (repos confiables,
aceptada de forma informada). **No** correr `accept_run.sh` sobre worktrees de código no confiable.

### 1.3 `handoff_complete.sh <archivo>` — completitud del handoff (F3, LINT/WARN)

Fuente: [`../skills/paralela/handoff_complete.sh`](../skills/paralela/handoff_complete.sh). Reporta
secciones/campos faltantes en un handoff. **Contrato innegociable: exit SIEMPRE `0`** — es lint/warn,
nunca bloquea ni reabre al worker.

**Argumento:** la ruta al archivo de handoff (markdown).

**Qué chequea:**
1. Frontmatter presente (1ª línea `---`) y `type: context-package`.
2. Las **7 secciones** obligatorias de `context-package` (títulos `##`, case-insensitive):
   `Resumen`, `Decisiones`, `Hallazgos`, `Riesgos`, `Pendientes`, `Para el siguiente agente`,
   `Referencias`.
3. Los **5 campos de cierre** del `done.json`, como claves de frontmatter (`^clave:`):
   `branch`, `summary`, `gate_veredicto`, `gate_refutacion`, `gate_resuelto`.

**Salida (siempre exit `0`):**

| Caso | Salida |
|------|--------|
| completo | `OK: completo` |
| faltan items | `WARN: falta <items…>` |
| archivo inexistente o sin argumento | `WARN: no existe <archivo>` / `WARN: no existe (sin argumento)` |

El criterio de las 7 secciones + frontmatter es el mismo que
[`../skills/context-package/validate.sh`](../skills/context-package/validate.sh) (que sí sale `2` si
falta algo — ese validador **sí** puede fallar; `handoff_complete.sh` deliberadamente no).

### 1.4 `diff-risk.sh <base_ref> <head_ref>` — elevador de riesgo (fuerza auditor)

Fuente: [`../skills/paralela/diff-risk.sh`](../skills/paralela/diff-risk.sh). Clasifica el diff de una
rama por **patrones de RUTA** para **forzar** el auditor central cuando toca security/data/config-prod.
`set -uo pipefail`.

**Argumentos:**
- `<base_ref>` — la **merge-base CONFIABLE** de integración (`git merge-base …`), **nunca** un valor
  provisto por el worker.
- `<head_ref>` — la rama a clasificar (`worktree-<id>`).

**Salida y exit:** **siempre exit `0`**; el veredicto va en stdout:
- `RISK=high` + `REASON=…` — si el diff toca alguna ruta sensible, o **fail-closed** ante cualquier
  error (refs faltantes/inválidas, `git diff` falla, diff vacío/sospechoso).
- `RISK=normal` — si ninguna ruta del diff matchea la denylist.

**Patrones de ruta de alto riesgo** (regex `grep -iE`, cobertura de rutas obvias, **no** exhaustiva):
`.env`, `*secret*`, `credential`, `authorized_keys`, `migrations/`, `*.sql`, `auth*`, `config/prod`,
`settings.*`, `Dockerfile`, `docker-compose*.yml`, `.github/`, `.gitlab-ci.yml`, `Jenkinsfile`,
`.circleci/`, `.drone.yml`, `*.tf`, `helm/`, `Chart.yaml`, `values.yaml`, `ansible/`, `cloudformation`,
lockfiles (`package(-lock).json`, `yarn.lock`, `requirements*.txt`, `Pipfile`, `go.mod/sum`,
`Cargo.toml/lock`, `pom.xml`, `*.gradle`), `config.*`, `*.pem`, `*.key`.

**Semántica clave — es un ELEVADOR, no un FILTRO.** `RISK=high` ⇒ auditor central (Opus) **obligatorio**
sobre esa rama. `RISK=normal` **NO** exime del gate CERRAR de contenido: es ciego al contenido (denylist
de rutas), así que un riesgo en ruta inocua (auth en `session.ts`, secreto en `constants.ts`,
`DELETE` sin `WHERE` en `db.ts`) lo atrapa el CERRAR central, que lee el diff integrado completo.

### 1.5 `orch-lib.sh` — primitivas del buzón (source, no ejecutable)

Fuente: [`../skills/paralela/orch-lib.sh`](../skills/paralela/orch-lib.sh). Se **sourcea**
(`source "$ORCH/bin/orch-lib.sh"`) desde el orquestador y los workers. Provee 3 primitivas:

- **`atomic_write <destino> <contenido>`** — escribe con `mktemp` en el mismo dir + `mv -f` (rename
  atómico en el mismo filesystem), de modo que un lector nunca vea contenido parcial. El contenido es
  **un solo argumento** (comíllalo: usa `"$2"`, no `"$*"`). Usado para `answer-<seq>.json` (texto plano).
- **`emit_json <destino> <k1> <v1> [<k2> <v2> …]`** — construye JSON **válido y atómico** a partir de
  pares clave/valor; el escaping lo hace `python3`, así que los valores pueden contener comillas,
  saltos de línea, `$`, `\` sin romper el JSON. Es la vía obligatoria para `status`/`ask`/`done`/
  `blocked` (nunca armar JSON a mano). Requiere `python3`.
- **`orch_wait <archivo_respuesta> <ttl_seg>`** (default `ttl=300`) — **bloqueo mecánico**: hace polling
  (`sleep 1`) hasta que el archivo exista (aparece por rename atómico) o venza el TTL. Imprime el
  contenido y retorna `0`; si expira imprime `__TTL__` y retorna `2`. El worker **no** "decide seguir
  esperando" — el bloqueo es mecánico.

### 1.6 `worker-guard.py` — hook `PreToolUse` que bloquea acciones externas (H4)

Fuente: [`../skills/paralela/worker-guard.py`](../skills/paralela/worker-guard.py). Se pasa al worker
vía `--settings` por-lanzamiento (opt-in; cero huella en sesiones normales). Implementa el protocolo de
hooks de Claude Code: lee el evento por `stdin` (JSON), y para **denegar** escribe el motivo a `stderr`
y sale con **exit `2`**; para permitir, exit `0`. Si el input no parsea → exit `0` (**fail-open**: no
romper al worker por un input inválido).

**Matcher configurado** (ver SKILL.md §3): `Bash|Write|Edit|MultiEdit|NotebookEdit`.

**Qué BLOQUEA:**
- **Tool `Bash`** (regex sobre el comando):
  - red saliente / escalada / remoto: `sudo`, `ssh`, `scp`, `sftp`, `rsync`, `curl`, `wget`, `nc`,
    `ncat`, `telnet`.
  - `git … push` (acción externa irreversible).
  - rutas sensibles en el comando (ver abajo).
- **Tools `Write`/`Edit`/`MultiEdit`/`NotebookEdit`:** si el `file_path`/`notebook_path` toca una ruta
  sensible.

**Rutas sensibles.** Los dotfiles del home se anclan al **`$HOME` real**: la ruta se normaliza
reemplazando `$HOME` por `~` **antes** de matchear, para no dar falso positivo con el propio worktree
(que vive en `<repo>/.claude/worktrees/…`, distinto de `~/.claude`). Dos regex:
- `HOME_DOTS`: `~/.ssh`, `~/.claude`, `~/.aws`, `~/.kube`, `~/.cloudflared`, `~/.gnupg`, `~/.docker`,
  `~/.npmrc`, `~/.config/gh`.
- `GLOBAL_SENS`: `/etc/`, `authorized_keys`, `.git/hooks`, `credentials`, `id_rsa`, `id_ed25519`.

**Honestidad (del propio archivo):** es una **denylist** (defensa en profundidad), no una jaula. Sube
mucho la barrera vs. prompt-only y corta los vectores obvios, pero un ataque decidido puede ofuscar
(`base64 | bash`, etc.). Los gestores de paquetes (`npm`/`pip`) **sí** pasan. Para contención total hace
falta aislamiento (contenedor/usuario dedicado) — fuera de alcance por decisión informada.

---

## 2. Contrato del buzón

Un directorio por orquestación `$ORCH = ${TMPDIR:-/tmp}/paralela/<task-slug>`; un subdirectorio por
worker `$ORCH/<id>/` (su **buzón**). Todos los archivos JSON se escriben **atómicamente** (`emit_json`
/ `atomic_write`), de modo que el lector nunca ve un archivo a medio escribir. Rutas auxiliares que
**no** son parte del buzón escribible por el worker: `$ORCH/bin/` (lib + settings del guard),
`$ORCH/acceptance/<id>.sh` (acceptance canónico orquestador-exclusivo), `$ORCH/integra` (clon limpio de
integración).

| Archivo | Quién escribe | Semántica | Formato / campos |
|---------|---------------|-----------|------------------|
| `status.json` | worker | **Heartbeat**: al empezar y en cada hito. Es una *pista*, no la verdad de liveness. | `state` (`working`…), `note` (qué hace), `ts` (`date -Is`) |
| `ask-<seq>.json` | worker | Pregunta ante una **decisión genuina** que no le toca. `seq` incremental (1,2,3…). | `seq`, `question` (pregunta + opciones), `context` |
| `answer-<seq>.json` | orquestador | Respuesta a `ask-<seq>`. **Texto plano** vía `atomic_write` — el worker la usa tal cual. | (texto plano, sin JSON) |
| `done.json` | worker | Cierre de la subtarea: rama + resumen + **contenido real del gate**. | `branch`, `summary`, `files`, `gate_veredicto`, `gate_refutacion`, `gate_resuelto` (ver §4) |
| `blocked.json` | worker | El worker cerró porque su `ask` venció por TTL (`orch_wait` devolvió `__TTL__`). Commitea su WIP y termina; el orquestador lo reanuda cuando tenga la respuesta. | `seq`, `question` |

**Handshake pregunta/respuesta (bloqueo-en-archivo):** el worker escribe `ask-<seq>.json` y se bloquea
en `orch_wait "$box/answer-<seq>.json" <ttl>`. El orquestador clasifica la pregunta y escribe
`answer-<seq>.json` (atómico). Si nadie responde antes del TTL (~900 s recomendado), el worker escribe
`blocked.json`, commitea su WIP y **termina** (no cuelga la sesión). Ver el flujo completo en
[`../skills/worker-protocol/SKILL.md`](../skills/worker-protocol/SKILL.md) §Ciclo.

---

## 3. Guardarraíles H1–H5

De [`../skills/paralela/SKILL.md`](../skills/paralela/SKILL.md) §4–§5. Suben la barrera de seguridad y
detectan estados que el `status.json` (auto-reportado) no garantiza.

- **H1 · Liveness independiente del worker.** El estado real NO se deriva del `status.json` (el worker
  lo controla) sino de señales que **no controla**: (a) `tmux display -p -t <repo>_worktree-<id>
  '#{pane_dead}'` + `pgrep -f "worktrees/<id>"` (¿vivo?); (b) mtime del último commit en `worktree-<id>`
  (¿progresa?). **Regla anti-falso-positivo:** no inferir "atascado" por falta de progreso si hay un
  `ask-<seq>` sin `answer` — un worker en `orch_wait` esperando respuesta legítimamente no commitea.
- **H2 · Contrato del buzón atómico.** (Ver §2.) Todo estado que cruza entre worker y orquestador pasa
  por archivos escritos con rename atómico; nunca por el chat del worker.
- **H3 · `--append-system-prompt`.** Reglas duras a nivel system-prompt (trabajar solo en el worktree,
  nada de acciones externas, usar el protocolo `ask`, sé directo). Es refuerzo de saliencia; el control
  duro es H4.
- **H4 · `--settings` con `worker-guard.py`.** Hook `PreToolUse` que **deniega mecánicamente**
  push/red/escalada/rutas sensibles, incluso bajo `--dangerously-skip-permissions`. Verificado: se
  **mergea** con otros hooks del entorno (no los pisa). Flag por-lanzamiento → cero huella en sesiones
  normales. (Detalle del guard en §1.6.)
- **H5 · Captura de preguntas FUERA de protocolo.** El buzón no captura una pregunta hecha en lenguaje
  natural ni un worker colgado tras un deny/permiso sin `ask-<seq>.json`. Cuando H1 detecta "atascado"
  (vivo + sin progreso + **sin `ask` pendiente**), el orquestador **lee la pantalla real**
  (`tmux capture-pane -p -t <repo>_worktree-<id>`); si hay pregunta o prompt `❯` idle, la clasifica como
  un `ask` y **responde por send-keys en DOS pasos** (verificado: `send-keys "txt" Enter` junto **no**
  envía — hay que separar): `send-keys -t <ses> "<respuesta>"` → `sleep 2` → `send-keys -t <ses> Enter`,
  y **re-captura** para confirmar. Si es ambiguo o el send-keys no toma → **escala al usuario** con el
  texto capturado (la sesión es attachable).

**Precondición dura (transversal):** `/paralela` corre **solo sobre repos confiables** — los workers
usan `--dangerously-skip-permissions` sin aislamiento fuerte. H4 es defensa-en-profundidad, no sandbox.

---

## 4. Contrato del `done.json` y schema del handoff

### 4.1 `done.json` (worker-protocol, paso "Cierre")

Al terminar, el worker emite `done.json` con `emit_json`. Campos:

| Campo | Semántica |
|-------|-----------|
| `branch` | Rama/worktree donde quedó commiteado el trabajo (`worktree-<id>`). |
| `summary` | Resumen del trabajo. El orquestador lo lee como **contenido completo** para su QA. |
| `files` | Archivos tocados. |
| `gate_veredicto` | `aprobado` \| `refutado` — veredicto del retador del auto-gate del worker. |
| `gate_refutacion` | Qué refutó el retador y cómo se resolvió (`sin hallazgos` si nada). **Contenido real**, no un booleano. |
| `gate_resuelto` | `si` \| `no` — si la refutación quedó resuelta. |

El orquestador lee el **contenido real** de `gate_refutacion`/`gate_veredicto` como insumo de su juicio
en el CERRAR central — nunca como un semáforo en el que confiar ciegamente.

### 4.2 Handoff estructurado (F3, opcional pero recomendado)

Para subtareas no triviales el worker deja además un **handoff**: un único markdown que combina el
schema `context-package` (trazabilidad) con los campos de cierre en su frontmatter (auditar el gate).
Esquema (fuente: [`../skills/paralela/done-schema.md`](../skills/paralela/done-schema.md)):

- **Frontmatter** YAML (1ª línea `---`) con `type: context-package` y las 5 claves de cierre de §4.1
  (`branch`, `summary`, `gate_veredicto`, `gate_refutacion`, `gate_resuelto`). `files` va como el campo
  `files:` estándar del frontmatter de context-package (por eso `handoff_complete.sh` no lo exige
  aparte).
- **7 secciones `##`** de context-package: `Resumen`, `Decisiones`, `Hallazgos`, `Riesgos`,
  `Pendientes`, `Para el siguiente agente`, `Referencias`.

Se valida con `handoff_complete.sh` (§1.3): **solo reporta** faltantes (WARN), nunca bloquea. Racional:
un `done.json` delgado ≠ trabajo delgado; reabrir forzaría a re-describir trabajo ya commiteado = tokens
sin mejora del resultado. Plantilla concreta:
[`../skills/context-package/TEMPLATE.md`](../skills/context-package/TEMPLATE.md).

---

## 5. Formato del PRP (F1) y contrato del acceptance (F2)

### 5.1 PRP — Parallel Requirements Package

Un blueprint **LEAN** por subtarea (plantilla:
[`../skills/paralela/prp-template.md`](../skills/paralela/prp-template.md); prompt del scout:
[`../skills/paralela/scout-prompt.md`](../skills/paralela/scout-prompt.md)). **5 secciones `##`
obligatorias con título exacto** (las exige `prp_lint.sh`, §1.1):

| Sección | Contenido |
|---------|-----------|
| `## Objetivo` | Resultado observable en 1–3 frases (el "qué", no el "cómo"). |
| `## Archivos` | Rutas exactas a crear/editar, marcadas `[nuevo]`/`[editar]`. |
| `## Símbolos` | Funciones/clases/constantes/endpoints concretos, con `ruta:línea` y firma si aplica. |
| `## Contexto necesario` | **SOLO** lo que ESTA subtarea usa (F4): contratos, tipos, invariantes, ejemplos mínimos, enlazados por `ruta:símbolo`. **Nada de archivos completos** ni contexto de otras subtareas. |
| `## Criterio de aceptación` | El acceptance (F2), **autoría del orquestador/scout, no del worker**. |

**Límites del linter (anti-dump):** ≤ 400 líneas **y** ≤ 15000 caracteres (superar cualquiera →
RECHAZADO). Medido empíricamente: volcar contexto grande **baja** la precisión; por eso el linter
penaliza el tamaño (ver [`ARQUITECTURA.md`](ARQUITECTURA.md) §F1 e [`INVESTIGACION.md`](INVESTIGACION.md) §3).

### 5.2 Contrato del acceptance (autoría-orquestador)

Fuente: [`../skills/paralela/acceptance-contract.md`](../skills/paralela/acceptance-contract.md). El
`## Criterio de aceptación` puede tomar tres formas: un `acceptance.sh` ejecutable, un criterio
verificable no-test, o el literal `acceptance: no-acceptance` (subtarea exploratoria/diseño → cae al
gate CERRAR). El `acceptance.sh`:

- Es bash (`#!/bin/bash`).
- Imprime en la **1ª línea** exactamente `PASS` o `FAIL` (sin prefijos), + hasta 5 líneas de detalle.
- Propaga exit: **`exit 0` = PASS**, **`exit 2` = FAIL**. La 1ª línea y el exit deben **concordar**
  (coherencia fail-closed; ver §1.2).
- Es determinista y autocontenido; corre desde `cwd = raíz del worktree`, así ejercita el **código del
  worker** (p.ej. `source ./archivo.sh`) con un test que el worker no manipuló.

**Núcleo de la autoridad:** el acceptance lo **autora el orquestador** como parte del PRP y vive en una
ruta orquestador-**EXCLUSIVA** (`$ORCH/acceptance/<id>.sh`), **fuera** del buzón `$ORCH/<id>/` y del
worktree (ambos escribibles por el worker). El orquestador lo **re-materializa fresco** desde su copia
del PRP justo antes de re-correrlo con `accept_run.sh` sobre la rama. La verdad es esa re-corrida, no el
`done.json` del worker. El *porqué* de estas decisiones de seguridad está en
[`ARQUITECTURA.md`](ARQUITECTURA.md) §Seguridad.
