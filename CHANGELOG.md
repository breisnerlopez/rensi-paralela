# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y el proyecto adhiere a [Versionado Semántico](https://semver.org/lang/es/).

## [Unreleased]

### Añadido
- **Gate CERRAR bundleado:** el skill `revisar`, los agentes `retador`/`auditor` y las
  12 lentes (`review/lenses/`) ahora vienen en el repo y los instala `install.sh`
  (`~/.claude/{skills,agents,review/lenses}`). Antes eran bring-your-own; el gate
  adversarial funciona out-of-the-box.
- **Launcher de referencia** (`launcher/claudea` + `launcher/README.md`): implementación
  genérica y **saneada** (sin usuario/sudo/bootstrap hardcodeados) del contrato
  `<launcher> -w <id>`. `install.sh` lo instala en `~/.local/bin/claudea` **solo si no
  existe ya un launcher** (claudea en PATH, `$PARALELA_LAUNCHER`, o el archivo destino);
  si ya hay uno, lo **respeta** (nunca sobreescribe). Flags: `--no-launcher`,
  `--launcher-dest <ruta>`.

### Cambiado
- `install.sh`: instala también gate (skills/agentes/lentes) y launcher; `--dest` deriva
  la raíz de config para agentes y lentes.
- Docs (README, guía, arquitectura, troubleshooting) reencuadran gate y launcher como
  **incluidos** (ya no bring-your-own).

## [0.2.0] - 2026-07-30

`paralela+`: iteración enfocada en **precisión y auditabilidad** (NO en tokens).

### Añadido
- **F1 · PRP (Parallel Requirements Package):** un scout explora el repo una vez y
  emite por subtarea un `PRP-<id>.md` LEAN (archivos, símbolos, contexto declarado
  y criterio de aceptación). `prp_lint.sh` RECHAZA PRPs gigantes
  (>400 líneas / >15000 caracteres) porque el dump ad-hoc baja la precisión (medido).
- **F2 · Validación con autoridad:** el acceptance lo **autora el orquestador**
  (parte del PRP) y vive en una ruta orquestador-exclusiva, no en el buzón del
  worker. Se re-materializa fresco y se re-corre con
  `accept_run.sh <worktree> <acceptance|--no-acceptance>` bajo `timeout`. La verdad
  es la validación re-corrida, no el auto-reporte del worker (`0=PASS/SKIP`, `2=FAIL`).
- **F3 · Completitud del handoff:** `handoff_complete.sh <archivo>` reporta (WARN)
  las secciones faltantes del handoff reusando el schema de `context-package`;
  **exit siempre 0** (es lint/warn, no bloquea).
- **F4 · Contexto declarado:** sección obligatoria del PRP con solo lo que la
  subtarea realmente usa.

### Cambiado
- **Reorganización:** el staging `paralela-plus/` se colapsó en `skills/paralela/`;
  las referencias a rutas antiguas se actualizaron.
- **Regla anti-narración de workers:** se desalienta la narración superflua de los
  workers. Es un **pulido no medido** (sin baseline); no se vende como ahorro.

### Seguridad
- El **gate CERRAR** atrapó y corrigió **2 rondas de problemas de seguridad** antes
  de integrar (acceptance en ruta orquestador-exclusiva, no en el buzón del worker,
  entre otros endurecimientos).

### Notas de medición (honestidad)
- **E2E:** ganancia de **precisión** medida (primario). El efecto en **tokens** salió
  como una **banda solapada, SIN conclusión** — no se reclama ahorro de tokens.
- El path interactivo/observable (buzón/tmux en vivo) se validó estructuralmente por
  gate, no end-to-end con los cambios de `paralela+` (known-limitation).

## [0.1.0]

Base del proyecto.

### Añadido
- **Investigación empírica** que sustenta el diseño (`docs/INVESTIGACION.md`,
  `laboratorio/`).
- **Orquestador base:** modelo cold + git worktrees observables, buzón de archivos
  (heartbeat, preguntas/respuestas, done, blocked), gate adversarial
  (retador → auditor) e **integración por clon limpio** en una sola rama.
