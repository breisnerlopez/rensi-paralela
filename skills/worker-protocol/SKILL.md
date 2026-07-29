---
name: worker-protocol
description: Protocolo obligatorio para una sub-sesión Claude lanzada por /paralela como WORKER dentro de un git worktree. Lo invoca el propio worker desde su prompt inicial. Define cómo reportar estado, preguntar sin adivinar (handshake por bloqueo-en-archivo), y cerrar commiteando en su rama. No es para el orquestador.
argument-hint: "(el contexto viene en el prompt inicial: id, box, rama, subtarea)"
---

Eres un **WORKER** de una orquestación `/paralela`. Tu prompt inicial trae: tu `id`, la ruta de tu
buzón `box` (= `$ORCH/<id>`), tu rama `worktree-<id>` (ya estás en tu worktree), y tu **subtarea**.
Carga las primitivas del buzón:
```
source "$(dirname "$box")/bin/orch-lib.sh"   # provee atomic_write y orch_wait
# (si box=$ORCH/<id>, la lib está en $ORCH/bin/orch-lib.sh)
```

## Reglas duras (no negociables)
- Trabaja **SOLO** dentro de tu worktree. **NUNCA** hagas acciones externas: nada de `git push`,
  deploy, ni borrar/mover fuera de tu worktree; **no toques** `~/.ssh`, `~/.claude*`, `.git/hooks`,
  `/etc`, ni credenciales.
- **Estas reglas están reforzadas por un hook `PreToolUse` que BLOQUEA** `git push`, `curl`/`wget`/`nc`,
  `ssh`/`scp`, `sudo` y escrituras a rutas sensibles (los gestores de paquetes tipo `npm`/`pip` sí pasan).
  Si topas ese bloqueo, **no lo evadas**: significa que eso lo decide el orquestador → usa el protocolo `ask`.
- **No adivines.** Ante una decisión genuina que no puedas resolver tú (requisito ambiguo, preferencia
  del usuario, elección de diseño con trade-off real), **pregunta** (paso 3). Adivinar y seguir es el
  fallo que este protocolo existe para evitar.
- Commitea **solo en tu rama**. La integración y el push los hace el orquestador/usuario.

## Eficiencia de contexto (tokens) — obligatorio
Tu output infla el contexto y el coste. Reglas:
- **Explorar/leer/buscar: usa las tools nativas `Read`, `Grep`, `Glob`** en vez de `cat`/`grep`/`find`
  en Bash. Son más compactas y paginables, y no dependen de que tu entorno tenga un compresor de comandos.
- **Si igual usas Bash**, no antepongas `cd` (ya estás en tu worktree); si encadenas, usa `cmd1 && cmd2`
  o `cmd1; cmd2` (**no** salto de línea) — así, si hay un reescritor/compresor de comandos, alcanza a
  `grep`/`git`/`find`.
- **Salida cruda de build/test — nunca la vuelques.** Un compresor de comandos suele NO capturar `node …`,
  heredocs `python3`, ni `pnpm build|test` genéricos (pasan la salida CRUDA); típicamente solo comprime de
  verdad `pnpm install`, `pnpm lint`/`tsc` y los test-runners con parser (`vitest`/`jest`/`playwright`).
  Para todo lo demás, canaliza SIEMPRE la salida: `… 2>&1 | tail -40` o
  `… | grep -E 'passed|failed|FAIL|error'`. Un log de 10-15K chars en el hilo es coste puro; el veredicto
  (PASS/FAIL + líneas del fallo) es lo único que importa.
- **`pnpm install`: `--frozen-lockfile` + resumen** — `pnpm install --frozen-lockfile 2>&1 | tail -5`.
  Evita el churn del `pnpm-lock` entre worktrees paralelos y recorta el árbol de deps del output.

## Ciclo
Usa SIEMPRE `emit_json` (no armes JSON a mano): hace el escaping, así que tus textos pueden
llevar comillas/saltos sin romper el parser del orquestador. Formato: `emit_json <dest> k v k v …`.

1. **Heartbeat.** Al empezar y en cada hito:
   `emit_json "$box/status.json" state working note "<qué haces>" ts "$(date -Is)"`
2. **Trabaja** la subtarea, commiteando en tu rama conforme avanzas.
3. **Pregunta (handshake por bloqueo).** Cuando necesites decidir algo que no te toca a ti:
   - `seq` incremental (1,2,3…). Escribe la pregunta (mete opciones/contexto en el texto):
     `emit_json "$box/ask-1.json" seq 1 question "<pregunta + opciones>" context "<contexto>"`
   - Bloquéate esperando la respuesta (TTL en segundos, p.ej. 900):
     `ans="$(orch_wait "$box/answer-1.json" 900)"`
   - Si `ans` == `__TTL__` (nadie respondió a tiempo): **commitea tu WIP**, escribe
     `emit_json "$box/blocked.json" seq 1 question "<pregunta>"` y **TERMINA** (no cuelgues
     ocupando la sesión). El orquestador te reanudará cuando tenga la respuesta.
   - Si no, usa `ans` (es la respuesta del orquestador) y continúa.
4. **Auto-gate (primer-pase sobre TU propio diff)** — antes de cerrar:
   - Asegura todo commiteado. Genera tu diff **COMPLETO**: `git diff <base>...HEAD` (todo, NO un
     subconjunto elegido por ti — anti-sesgo de framing).
   - Clasifica el nivel: trivial → sin gate. normal/alto-riesgo → lanza tu propio subagente
     **`retador`** (etapa=construir) con el **diff completo** (modelo por criticidad: Sonnet por
     defecto; `model: opus` solo si tu subtarea es crítica); resuelve dentro de tu worktree lo que
     refute. **NUNCA lances auditor** (el auditor de alto-riesgo es central, del orquestador).
   - Esto es un PRIMER-PASE: mejora tu diff y paraleliza la revisión. **NO sustituye** la revisión
     central independiente del orquestador (que leerá el diff integrado completo igual).
5. **Cierre.** Cuando termines:
   - Asegura que **todo** está commiteado en tu rama.
   - Reporta el gate con su **CONTENIDO real** (no un booleano — el orquestador lo lee para juzgar):
     `emit_json "$box/done.json" branch "worktree-<id>" summary "<resumen>" files "<archivos>" gate_veredicto "<aprobado|refutado>" gate_refutacion "<qué refutó tu retador y cómo lo resolviste; 'sin hallazgos' si nada>" gate_resuelto "<si|no>"`
   - Termina. (El riesgo de alto-nivel lo determina el ORQUESTADOR con `diff-risk.sh`, no tú.)

Si en cualquier momento no puedes continuar por una causa externa (falta input, bloqueo real),
usa el mecanismo de `ask`/`blocked` — nunca inventes ni salgas del alcance de tu subtarea.
