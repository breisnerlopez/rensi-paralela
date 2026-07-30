#!/usr/bin/env bash
# install.sh — instalador de los skills de rensi-paralela.
#
# Copia los skills `paralela`, `worker-protocol` y `context-package` a la ubicación
# estándar de Claude Code ($HOME/.claude/skills por defecto), respaldando lo que ya
# exista, verifica prerequisites (duros y bring-your-own) y corre los unit tests desde
# el destino instalado como post-check.
#
# Uso:
#   ./install.sh [--dest <dir>] [--dry-run] [-h|--help]
#
# Configuración del destino (precedencia): --dest <dir>  >  env DEST=...  >  $HOME/.claude/skills
#
# Códigos de salida:
#   0  éxito (skills instalados; los warnings bring-your-own NO fallan)
#   !=0  error real: prerequisite duro ausente (claude/git/python3), fallo de copia,
#        o uso incorrecto.
set -euo pipefail

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SKILLS="$SCRIPT_DIR/skills"
SKILLS=(paralela worker-protocol context-package revisar)
SRC_AGENTS="$SCRIPT_DIR/agents"          # retador.md, auditor.md -> <claude>/agents
SRC_LENSES="$SCRIPT_DIR/review/lenses"   # lentes del gate        -> <claude>/review/lenses
SRC_LAUNCHER="$SCRIPT_DIR/launcher/claudea"
DEFAULT_DEST="$HOME/.claude/skills"
DEFAULT_LAUNCHER_DEST="$HOME/.local/bin/claudea"

# ---------------------------------------------------------------------------
# Colores (solo si es una TTY)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''; C_B=''; C_0=''
fi

ok()   { printf '%s✓%s %s\n' "$C_OK" "$C_0" "$*"; }
warn() { printf '%s✗ WARN%s %s\n' "$C_WARN" "$C_0" "$*"; }
err()  { printf '%s✗ ERROR%s %s\n' "$C_ERR" "$C_0" "$*" >&2; }
info() { printf '%s\n' "$*"; }
hdr()  { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }

usage() {
  cat <<EOF
install.sh — instala los skills de rensi-paralela en Claude Code.

Uso:
  ./install.sh [--dest <dir>] [--dry-run] [-h|--help]

Opciones:
  --dest <dir>      Directorio destino de skills (default: \$HOME/.claude/skills,
                    o la variable de entorno DEST si está definida). Los agentes y
                    lentes del gate se instalan junto a él (<claude>/agents, <claude>/review).
  --no-launcher     NO instala el launcher de referencia. Por defecto, el launcher
                    (launcher/claudea) se instala en ~/.local/bin SOLO si no existe ya
                    uno (claudea en PATH, \$PARALELA_LAUNCHER, o el archivo destino);
                    si ya existe, se OMITE (nunca se sobreescribe el tuyo).
  --launcher-dest <ruta>  Destino del launcher (default: ~/.local/bin/claudea).
  --dry-run         Muestra qué haría (copias, respaldos) SIN tocar el disco.
  -h, --help        Esta ayuda.

Instala skills: ${SKILLS[*]}
        + agentes del gate (retador, auditor) y lentes en <claude>/agents y <claude>/review/lenses.
EOF
}

# ---------------------------------------------------------------------------
# Parseo de argumentos
# ---------------------------------------------------------------------------
DRY_RUN=0
NO_LAUNCHER=0
# ¿El usuario fijó destino EXPLÍCITAMENTE (env DEST o --dest)? Se captura ANTES de
# normalizar, para distinguir "no dio destino" (usa default) de "dio vacío" (footgun -> error).
DEST_EXPLICIT=0
[[ -n "${DEST+x}" ]] && DEST_EXPLICIT=1   # env DEST definida, aunque sea cadena vacía
DEST="${DEST:-}"   # normaliza para set -u; se resuelve más abajo

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { err "--dest requiere un directorio."; exit 2; }
      DEST="$2"; DEST_EXPLICIT=1; shift 2 ;;
    --dest=*)
      DEST="${1#--dest=}"; DEST_EXPLICIT=1; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --no-launcher)
      NO_LAUNCHER=1; shift ;;
    --launcher-dest)
      [[ $# -ge 2 ]] || { err "--launcher-dest requiere una ruta."; exit 2; }
      LAUNCHER_DEST="$2"; shift 2 ;;
    --launcher-dest=*)
      LAUNCHER_DEST="${1#--launcher-dest=}"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      err "Argumento desconocido: $1"; usage >&2; exit 2 ;;
  esac
done

# Resolver destino final. Rechazar destino vacío EXPLÍCITO (--dest '' o DEST='') ANTES de aplicar el
# default: si DEST está SET pero vacío, es un footgun (instalaría en el home sin que el usuario lo note).
if (( DEST_EXPLICIT )) && [[ -z "$DEST" ]]; then
  err "Destino vacío (--dest '' o DEST=''); abortando por seguridad. Omite --dest para usar el default."
  exit 2
fi
DEST="${DEST:-$DEFAULT_DEST}"
# Raíz de config de Claude: agents/ y review/ viven JUNTO a skills/, no dentro.
# Se deriva del padre de DEST (así, con --dest a un tmp, todo queda autoconsistente).
CLAUDE_DIR="$(dirname "$DEST")"
AGENTS_DEST="$CLAUDE_DIR/agents"
LENSES_DEST="$CLAUDE_DIR/review/lenses"
LAUNCHER_DEST="${LAUNCHER_DEST:-$DEFAULT_LAUNCHER_DEST}"   # override por env o --launcher-dest

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------------------
# Cabecera
# ---------------------------------------------------------------------------
hdr "rensi-paralela · instalador"
info "Origen : $SRC_SKILLS"
info "Destino: $DEST"
if (( DRY_RUN )); then
  info "${C_DIM}Modo   : --dry-run (no se modifica nada)${C_0}"
else
  info "Modo   : instalación real"
fi

# Sanidad del origen: los 3 skills deben existir en el repo.
if [[ ! -d "$SRC_SKILLS" ]]; then
  err "No existe el directorio de origen: $SRC_SKILLS"
  exit 1
fi
for s in "${SKILLS[@]}"; do
  if [[ ! -d "$SRC_SKILLS/$s" ]]; then
    err "Skill de origen faltante: $SRC_SKILLS/$s (repo incompleto)."
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 1) Prerequisites
# ---------------------------------------------------------------------------
hdr "Prerequisites"
HARD_MISSING=0

check_hard() {
  local cmd="$1" desc="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd  — $desc  ($(command -v "$cmd"))"
  else
    warn "$cmd AUSENTE (duro) — $desc"
    HARD_MISSING=$((HARD_MISSING + 1))
  fi
}
check_soft() {
  local cmd="$1" desc="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd  — $desc  ($(command -v "$cmd"))"
  else
    warn "$cmd ausente — $desc (recomendado; no bloquea la instalación)"
  fi
}

check_hard  claude  "CLI de Claude Code; los skills se cargan desde \$HOME/.claude/skills"
check_hard  git     "worktrees por worker; integración por rama"
check_hard  python3 "guardas y unit tests (worker-guard.py, post-check)"
check_soft  tmux    "paneles observables en vivo de los workers (runtime de /paralela)"

# Componente externo. El GATE (revisar + agentes + lentes) ahora viene con el repo y se
# instala más abajo; el único componente que debes proveer/adaptar es el LAUNCHER.
hdr "Launcher de worktrees (único componente externo)"
LAUNCHER_OK=0
if command -v claudea >/dev/null 2>&1; then
  ok "launcher 'claudea' en PATH  ($(command -v claudea))."
  LAUNCHER_OK=1
elif [[ -n "${PARALELA_LAUNCHER:-}" ]] && command -v "${PARALELA_LAUNCHER%% *}" >/dev/null 2>&1; then
  ok "launcher: \$PARALELA_LAUNCHER=${PARALELA_LAUNCHER}"
  LAUNCHER_OK=1
else
  warn "launcher de worktrees NO detectado."
  info "     Se instalará automáticamente la REFERENCIA saneada (launcher/claudea) más abajo,"
  info "     salvo que uses --no-launcher. También puedes definir \$PARALELA_LAUNCHER a tu propio launcher."
  info "     Sin launcher, /paralela no arranca workers."
fi
# El gate (revisar + retador/auditor + lentes) se bundlea e instala con este script.
REVISAR_OK=1

# ---------------------------------------------------------------------------
# 2) Copia (con respaldo no destructivo)
# ---------------------------------------------------------------------------
hdr "Instalación de skills"
declare -a BACKED_UP=()
declare -a INSTALLED=()

if (( DRY_RUN )); then
  info "${C_DIM}(dry-run: acciones simuladas)${C_0}"
  info "Crearía directorio destino: $DEST"
fi

if (( ! DRY_RUN )); then
  mkdir -p "$DEST"
fi

for s in "${SKILLS[@]}"; do
  src="$SRC_SKILLS/$s"
  dst="$DEST/$s"

  # Respaldo si el destino ya existe (nunca pisar en silencio).
  if [[ -e "$dst" ]]; then
    bak="$dst.bak-$TIMESTAMP"
    # Evita colisión si ya existiera un backup con el mismo timestamp.
    if [[ -e "$bak" ]]; then
      bak="$dst.bak-$TIMESTAMP-$$"
    fi
    if (( DRY_RUN )); then
      info "  ${C_WARN}respaldaría${C_0} $dst  ->  $bak"
    else
      mv -- "$dst" "$bak"
      warn "respaldado: $dst  ->  $bak"
    fi
    BACKED_UP+=("$s -> $(basename "$bak")")
  fi

  # Copia.
  if (( DRY_RUN )); then
    info "  ${C_OK}copiaría${C_0}    $src  ->  $dst"
  else
    cp -R -- "$src" "$dst"
    ok "instalado: $s  ->  $dst"
  fi
  INSTALLED+=("$s")
done

# Agentes del gate (retador, auditor) -> <claude>/agents/
if [[ -d "$SRC_AGENTS" ]]; then
  hdr "Instalación de agentes del gate"
  (( DRY_RUN )) || mkdir -p "$AGENTS_DEST"
  for a in retador auditor; do
    asrc="$SRC_AGENTS/$a.md"; adst="$AGENTS_DEST/$a.md"
    [[ -f "$asrc" ]] || continue
    if [[ -e "$adst" ]]; then
      abak="$adst.bak-$TIMESTAMP"; [[ -e "$abak" ]] && abak="$adst.bak-$TIMESTAMP-$$"
      if (( DRY_RUN )); then info "  ${C_WARN}respaldaría${C_0} $adst  ->  $abak"
      else mv -- "$adst" "$abak"; warn "respaldado: $adst  ->  $(basename "$abak")"; fi
    fi
    if (( DRY_RUN )); then info "  ${C_OK}copiaría${C_0}    $asrc  ->  $adst"
    else cp -- "$asrc" "$adst"; ok "agente: $a  ->  $adst"; fi
  done
fi

# Lentes del gate -> <claude>/review/lenses/
if [[ -d "$SRC_LENSES" ]]; then
  hdr "Instalación de lentes del gate"
  if [[ -e "$LENSES_DEST" ]]; then
    lbak="$LENSES_DEST.bak-$TIMESTAMP"; [[ -e "$lbak" ]] && lbak="$LENSES_DEST.bak-$TIMESTAMP-$$"
    if (( DRY_RUN )); then info "  ${C_WARN}respaldaría${C_0} $LENSES_DEST  ->  $lbak"
    else mv -- "$LENSES_DEST" "$lbak"; warn "respaldado: $LENSES_DEST  ->  $(basename "$lbak")"; fi
  fi
  if (( DRY_RUN )); then info "  ${C_OK}copiaría${C_0}    $SRC_LENSES  ->  $LENSES_DEST"
  else mkdir -p "$(dirname "$LENSES_DEST")"; cp -R -- "$SRC_LENSES" "$LENSES_DEST"; ok "lentes  ->  $LENSES_DEST"; fi
fi

# Launcher de referencia: se instala SOLO si NO existe ya un launcher (comportamiento
# por defecto). Si ya hay un 'claudea' en PATH, un $PARALELA_LAUNCHER, o un archivo en el
# destino -> se OMITE (no se toca el tuyo; sin backup ni shadowing). Desactivar: --no-launcher.
if (( NO_LAUNCHER )); then
  info "${C_DIM}--no-launcher: no se instala el launcher de referencia.${C_0}"
elif (( LAUNCHER_OK )) || [[ -e "$LAUNCHER_DEST" ]]; then
  info "${C_DIM}launcher ya presente; se omite el de referencia (no se sobreescribe).${C_0}"
else
  hdr "Launcher de referencia (no había ninguno; se instala)"
  if [[ ! -f "$SRC_LAUNCHER" ]]; then
    warn "no encontré $SRC_LAUNCHER; omito el launcher."
  else
    ldir="$(dirname "$LAUNCHER_DEST")"
    if (( DRY_RUN )); then
      info "  ${C_OK}instalaría${C_0} $SRC_LAUNCHER  ->  $LAUNCHER_DEST (+x)"
    else
      mkdir -p "$ldir"; cp -- "$SRC_LAUNCHER" "$LAUNCHER_DEST"; chmod +x "$LAUNCHER_DEST"
      ok "launcher instalado  ->  $LAUNCHER_DEST"
      LAUNCHER_OK=1
      case ":$PATH:" in *":$ldir:"*) : ;; *) warn "$ldir no está en tu PATH; añádelo para usar 'claudea'." ;; esac
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 3) chmod +x a scripts del skill paralela
# ---------------------------------------------------------------------------
if (( ! DRY_RUN )); then
  target="$DEST/paralela"
  if [[ -d "$target" ]]; then
    # Marca ejecutables todos los .sh y .py copiados (incl. tests/).
    while IFS= read -r -d '' f; do
      chmod +x "$f"
    done < <(find "$target" -type f \( -name '*.sh' -o -name '*.py' \) -print0)
  fi
else
  info "  ${C_DIM}dry-run: haría chmod +x a *.sh y *.py bajo $DEST/paralela${C_0}"
fi

# ---------------------------------------------------------------------------
# 4) Post-check: unit tests desde el destino instalado
# ---------------------------------------------------------------------------
hdr "Post-check (unit tests desde el destino instalado)"
TESTS_RESULT="no ejecutado"
POST_FAIL=0
if (( DRY_RUN )); then
  info "${C_DIM}dry-run: correría bash $DEST/paralela/tests/{a,b,c}_test.sh${C_0}"
  TESTS_RESULT="omitido (dry-run)"
else
  tests_dir="$DEST/paralela/tests"
  if [[ -d "$tests_dir" ]]; then
    test_fail=0
    for t in a b c; do
      tf="$tests_dir/${t}_test.sh"
      if [[ -f "$tf" ]]; then
        if out="$(bash "$tf" 2>&1)"; then
          # última línea de resumen del test
          summary="$(printf '%s\n' "$out" | tail -n 1)"
          ok "${t}_test.sh: PASS  ${C_DIM}(${summary})${C_0}"
        else
          summary="$( { printf '%s\n' "$out" | grep -E 'FAIL' | head -n 3 | tr '\n' ';'; } || true )"
          warn "${t}_test.sh: FAIL  — ${summary:-ver log}"
          test_fail=$((test_fail + 1))
        fi
      else
        warn "${t}_test.sh no encontrado en el destino (omitido)."
      fi
    done
    if (( test_fail == 0 )); then
      TESTS_RESULT="PASS (a,b,c)"
    else
      TESTS_RESULT="FAIL en $test_fail test(s)"
      POST_FAIL=1
    fi
  else
    warn "No hay tests en el destino ($tests_dir); post-check omitido."
    TESTS_RESULT="omitido (sin tests)"
  fi
fi

# ---------------------------------------------------------------------------
# 5) Resumen final
# ---------------------------------------------------------------------------
hdr "Resumen"
info "Destino     : $DEST"
info "Instalados  : ${INSTALLED[*]:-(ninguno)}"
if (( ${#BACKED_UP[@]} )); then
  info "Respaldados : ${#BACKED_UP[@]}"
  for b in "${BACKED_UP[@]}"; do info "   - $b"; done
else
  info "Respaldados : ninguno (no había skills previos)"
fi
info "Post-check  : $TESTS_RESULT"

info ""
if (( LAUNCHER_OK )); then
  info "${C_B}Todo listo:${C_0} gate (revisar + agentes + lentes) instalado y launcher detectado."
else
  info "${C_B}Falta el launcher:${C_0} usaste --no-launcher y no había ninguno. Copia launcher/claudea a un dir de tu PATH,"
  info "   o vuelve a correr sin --no-launcher. El gate (revisar + agentes + lentes) ya quedó instalado."
fi

info ""
if (( DRY_RUN )); then
  info "${C_B}Dry-run completado.${C_0} Vuelve a correr sin --dry-run para instalar."
else
  info "${C_B}Siguiente paso:${C_0} abre Claude Code y ejecuta  ${C_B}/paralela${C_0}  sobre un repo confiable."
fi

# ---------------------------------------------------------------------------
# Código de salida
# ---------------------------------------------------------------------------
if (( HARD_MISSING > 0 )); then
  err "$HARD_MISSING prerequisite(s) duro(s) ausente(s): los skills se copiaron, pero /paralela NO correrá hasta resolverlos."
  exit 1
fi
if (( POST_FAIL > 0 )); then
  err "El post-check (unit tests) falló desde el destino instalado: la instalación quedó en un estado dudoso."
  exit 1
fi
exit 0
