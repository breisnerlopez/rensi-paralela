# Launcher de referencia (`claudea`)

`claudea` es un **launcher de referencia** para `/paralela`: un wrapper de `claude` (Claude Code) que,
dado `-w <id>`, crea un git worktree con su rama y arranca ahí un worker observable (tmux + remote-control)
con los permisos apropiados, reenviando los flags por-lanzamiento (`--settings`, `--append-system-prompt`,
`--model`) que el orquestador necesita.

Es un launcher **de referencia, incluido e instalado por `install.sh`**: genérico y saneado (sin
usuario/sudo/bootstrap hardcodeados). El contrato lo define `skills/paralela/SKILL.md` (la skill lo invoca
como `<launcher>`); puedes usar este archivo tal cual o **adaptarlo a tu entorno**.

## Contrato que cumple
```
claudea -w <id> [--model <m>] [--settings <f>] [--append-system-prompt <p>] "<prompt del worker>"
```
→ worktree `<repo>/.claude/worktrees/<id>` en rama `worktree-<id>`, sesión tmux `<repo>-<id>`,
worker `claude` con `--dangerously-skip-permissions` + `--remote-control` (observable en móvil/web).

## Requisitos
`claude` (Claude Code) en PATH, `git`, `tmux`, `python3`. El **modo proveedor** opcional (`-b <prov>`,
para correr los workers en otro backend de modelos) requiere además `yq` + `jq` y un
`~/.claude/providers.yaml` (config bring-your-own; no incluida).

## Instalación
`install.sh` lo instala **por defecto en `~/.local/bin/claudea`, pero SOLO si no tienes ya un launcher**
(un `claudea` en el PATH, un `$PARALELA_LAUNCHER` definido, o el archivo destino ya existente). **Si ya
tienes uno, lo respeta y no lo toca** (no lo sobreescribe ni lo respalda — simplemente lo omite).

```bash
./install.sh                          # instala el launcher si no hay ninguno
./install.sh --no-launcher            # NO instala el launcher de referencia
./install.sh --launcher-dest <ruta>   # elige el destino (default ~/.local/bin/claudea)

# a mano (equivalente):
cp launcher/claudea ~/.local/bin/claudea && chmod +x ~/.local/bin/claudea
```
Asegúrate de que el directorio destino esté en tu `PATH`.

## Seguridad (léelo antes de usarlo)
Este launcher está pensado para el flujo de `/paralela` sobre **repos confiables** y **hace cosas
privilegiadas** — entiéndelas antes de copiarlo:
- Arranca los workers con **`--dangerously-skip-permissions`** (sin confirmación por acción). Úsalo solo
  sobre código que confías; el guard (`worker-guard.py`) es defensa en profundidad, **no** un sandbox.
- **Auto-acepta el diálogo de confianza** de Claude Code escribiendo `hasTrustDialogAccepted=true` en tu
  `~/.claude.json` para `$PWD` y la ruta del worktree (necesario para el remote-control en tmux headless).
- Si corres como **root**, exporta `IS_SANDBOX=1` para desbloquear skip-permissions (escape hatch de
  contenedor/sandbox). No lo corras como root fuera de un entorno aislado.
- El **modo proveedor** (`-b`) lee credenciales de `~/.claude/providers.env` (que debe ser `chmod 600`) y
  exporta solo la key del proveedor pedido a la sesión (no filtra las de otros proveedores).

## Notas de adaptación
- **Permisos elevados / sandbox:** corre como el usuario que lo invoca. Si tu entorno necesita otra
  postura (contenedor, usuario dedicado), ajústalo tú.
- **Sin tmux:** si no usas tmux, quita `--tmux` y `--remote-control` — perderás la observabilidad en vivo,
  pero la supervisión de `/paralela` (liveness H1) usa también el buzón de archivos.
