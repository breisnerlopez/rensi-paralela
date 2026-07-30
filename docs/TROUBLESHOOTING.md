# Troubleshooting — `/paralela`

Problemas comunes al correr `/paralela`, con el formato **síntoma → causa → solución**. Para el flujo
normal ver [`GUIA-USUARIO.md`](GUIA-USUARIO.md); para el detalle técnico de scripts, buzón y
guardarraíles H1–H5 ver [`REFERENCIA.md`](REFERENCIA.md).

> Convención: `$ORCH` = directorio de orquestación (`${TMPDIR:-/tmp}/paralela/<task-slug>`); el buzón de
> cada worker vive en `$ORCH/<id>/`. La sesión tmux del worker es `<repo>_worktree-<id>` y el
> remote-control es `<repo>-<id>`.

---

## 1. El launcher no existe / `/paralela` no lanza nada

**Síntoma:** el orquestador aprueba la partición pero no arranca ningún worker; error tipo
`command not found` sobre `<launcher>`, o no aparece ninguna sesión en `tmux ls`.

**Causa:** el **launcher de sesiones en worktrees es bring-your-own**: el binario concreto **no** se
incluye en este repo (es un contrato, ver README → Prerequisites y
[`GUIA-USUARIO.md`](GUIA-USUARIO.md) §3). Sin él, `/paralela` no tiene con qué crear los worktrees ni
arrancar los workers.

**Solución:** provee un launcher que cumpla el contrato: dado `-w <id>`, crea worktree + rama, arranca
un worker `claude` con permisos y **reenvía** los flags por lanzamiento (`--settings`,
`--append-system-prompt`, `--model`). Verifica que el `<id>` sea válido (`[a-z0-9_-]`, empieza por
alfanumérico — un id que empieza con `-` el launcher lo tomaría como flag). Mientras no lo tengas,
`/paralela` no puede lanzar workers de verdad; el resto (partición, PRP, gate) sí razona, pero sin
ejecución real.

---

## 2. El guard bloqueó una acción del worker

**Síntoma:** en la pantalla del worker (o en su reporte) aparece que una acción fue **denegada**: un
`git push`, un `curl`/`wget`/`nc`, un `ssh`/`scp`, un `sudo`, o una escritura a `~/.ssh` / `~/.claude` /
`.git/hooks` / `/etc`.

**Causa:** **esto es esperado, no un bug.** El hook `PreToolUse` (`worker-guard.py`, H4) **bloquea
mecánicamente** las acciones externas del worker, **aun bajo `--dangerously-skip-permissions`**. Los
gestores de paquetes (`npm`/`pip`) sí pasan; las acciones externas no. Es defensa en profundidad, por
diseño.

**Solución:** nada que arreglar en el guard. El worker **no debe evadirlo**: que esa acción esté
bloqueada significa que **la decide el orquestador/usuario**, no el worker. El worker correcto usa el
**protocolo `ask`** (escribe `ask-<seq>.json` y espera respuesta) en vez de intentar la acción externa.
Si necesitas de verdad que algo externo ocurra (p. ej. el push final), lo haces **tú** al integrar
(Paso 7 de la guía). Si un worker se cuelga tras el bloqueo sin escribir `ask`, ver §3 (H5).

---

## 3. Worker colgado / atascado

**Síntoma:** un worker no progresa: no hay commits nuevos, no cierra con `done.json`, no escribe `ask`.

**Causa y diagnóstico (liveness H1 — no te fíes del `status.json` del worker):** deriva el estado real
de señales que el worker no controla:

```
tmux display -p -t <repo>_worktree-<id> '#{pane_dead}'   # 1 = pane muerto
pgrep -f "worktrees/<id>"                                 # ¿proceso vivo?
```

y mira el mtime del último commit en `worktree-<id>` (¿progresa?).

- **Vivo + esperando respuesta:** si hay un `ask-<seq>.json` **sin** su `answer-<seq>.json`, el worker
  está legítimamente bloqueado en `orch_wait` (hasta el TTL, ~15 min). **No** es un cuelgue — falta que
  el orquestador/tú respondan. → responde (o ver §4 si venció el TTL).
- **Vivo + sin progreso + SIN `ask` pendiente (H5 — pregunta fuera de protocolo):** el worker puede
  haber preguntado en **lenguaje natural** o haberse colgado tras un deny/permiso **sin** escribir
  `ask-<seq>.json`; el buzón no lo captura. **Lee la pantalla real:**

  ```
  tmux capture-pane -p -t <repo>_worktree-<id>
  ```

  Si muestra una pregunta o un prompt idle `❯`, respóndela por `send-keys` **en dos pasos** (verificado:
  `send-keys "txt" Enter` junto NO envía — hay que separar):

  ```
  tmux send-keys -t <repo>_worktree-<id> "<respuesta>"
  sleep 2
  tmux send-keys -t <repo>_worktree-<id> Enter
  ```

  Re-captura con `capture-pane` para confirmar que se procesó. Si es ambiguo o el `send-keys` no toma,
  **engánchate al pane** (`tmux attach -t <repo>_worktree-<id>`) y toma el control directo.

- **Muerto (`pane_dead`=1 / proceso ausente / heartbeat vencido):** márcalo `failed`. La integración
  procede con los workers vivos y **reporta** cuál falló. Limpia su worktree (§6).

---

## 4. TTL vencido / worker en `blocked.json` — cómo reanudar

**Síntoma:** aparece `$ORCH/<id>/blocked.json`; el worker ya no está corriendo.

**Causa:** el worker hizo una pregunta (`ask-<seq>.json`) y **nadie respondió dentro del TTL** (~15 min).
Por protocolo, en vez de colgar la sesión ocupada, el worker **commitea su WIP**, escribe `blocked.json`
con la pregunta pendiente y **termina**. Es el comportamiento correcto (libera la sesión).

**Solución:** cuando tengas la respuesta, **reanuda** al worker (`claude --resume` de esa sesión) o
**ciérralo y reasigna** la subtarea. La respuesta se entrega como texto plano en
`$ORCH/<id>/answer-<seq>.json`. No pierdes trabajo: el WIP quedó commiteado en `worktree-<id>`.

---

## 5. El buzón: dónde vive y qué contiene

**Síntoma:** quieres inspeccionar el estado real de un worker, o algo parece inconsistente en la
comunicación orquestador↔worker.

**Causa/estructura:** el buzón de cada worker vive en `$ORCH/<id>/`. Todos los archivos se escriben de
forma **atómica** (vía `atomic_write`/`emit_json` de `orch-lib.sh`), así que nunca deberías leer un JSON
a medio escribir:

| Archivo | Qué es |
|---|---|
| `status.json` | heartbeat del worker (pista, no autoridad) |
| `ask-<seq>.json` | pregunta del worker (opciones + contexto) |
| `answer-<seq>.json` | respuesta del orquestador (**texto plano**) |
| `done.json` | cierre: rama + resumen + veredicto del gate |
| `blocked.json` | el worker cerró por TTL vencido (ver §4) |

El acceptance canónico (F2) **NO** vive en el buzón del worker, sino en una ruta
orquestador-exclusiva (`$ORCH/acceptance/<id>.sh`) que el worker no puede tocar — por eso la validación
re-corrida por el orquestador es la autoridad, no el auto-reporte del worker.

**Solución:** para diagnosticar, lee estos archivos directamente. Si un `answer` no fue tomado, revisa
que el worker siga vivo y en `orch_wait` (§3). Detalle del contrato en [`REFERENCIA.md`](REFERENCIA.md).

---

## 6. Limpieza de worktrees colgados

**Síntoma:** al terminar (o tras un worker `failed`), `git worktree remove` falla con un lock, o quedan
worktrees/ramas huérfanos.

**Causa:** matar la sesión tmux **NO basta**. `tmux kill-session` cierra el pane, pero el proceso
`claude` **sobrevive detached** y **retiene el lock** del worktree.

**Solución:** mata primero el **PROCESO**, luego remueve el worktree:

```
pkill -f "worktrees/<id>"                    # (o el pid concreto) — mata el worker detached
git worktree remove -f -f <path-al-worktree> # doble -f
git worktree prune
git branch -D worktree-<id>
```

Al final, borra `$ORCH` (el directorio de orquestación completo). Si `git worktree remove` sigue
quejándose de un lock, confirma con `pgrep -f "worktrees/<id>"` que ya no queda proceso vivo.

---

## 7. El skill `revisar` no está (gate CERRAR)

**Síntoma:** al integrar, el orquestador no puede correr el gate CERRAR; no encuentra `revisar` (ni el
retador/auditor).

**Causa:** el skill **`revisar`** (o un equivalente que exponga retador + auditor read-only) es un
**prerequisite bring-your-own** (README → Prerequisites). No viene empaquetado con este repo.

**Solución:** instala un skill `revisar` que corra el gate adversarial por etapas
(idea|plan|construir|cerrar). El gate CERRAR central es **innegociable** en la integración: sin él, el
orquestador no tiene con qué hacer la revisión independiente del diff integrado. Mientras no lo tengas,
`/paralela` puede lanzar y validar por acceptance, pero **no** cierra con la garantía de revisión que el
diseño exige.

---

## 8. Tokens y salida cruda de build/test

**Síntoma:** tu contexto (el del orquestador) crece rápido, o esperabas que `/paralela` **ahorrara
tokens** y no lo notas.

**Causa (dos cosas distintas):**

1. **Expectativa equivocada:** `/paralela` **no promete menos tokens** — su valor medido es precisión y
   auditabilidad (ver [`GUIA-USUARIO.md`](GUIA-USUARIO.md) §6 → *Limitaciones honestas*). No lo trates
   como técnica de ahorro.
2. **Salida cruda de build/test = coste puro.** Muchos compresores de comandos **no** capturan
   `node …`, heredocs `python3` ni `pnpm build`/`test` genéricos (pasan la salida cruda); típicamente
   solo comprimen bien `pnpm install`, `lint`/`tsc` y test-runners con parser.

**Solución:** no vuelques logs crudos en tu hilo. **Delega builds/tests a un subagente efímero** que
ejecute y devuelva solo `PASS/FAIL + ≤5 líneas del fallo` (verificación por veredicto). Igual para el
digest de supervisión: delega la lectura del buzón a un subagente que devuelva un resumen compacto, para
que tu contexto crezca ~O(decisiones), no O(ticks×workers). Cuando corras algo tú, canaliza la salida
(`… 2>&1 | tail -40` o `| grep -E 'passed|failed|FAIL|error'`), nunca cruda.
