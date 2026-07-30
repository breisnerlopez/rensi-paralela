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
SKILLS=(paralela worker-protocol context-package)
DEFAULT_DEST="$HOME/.claude/skills"

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
  --dest <dir>   Directorio destino de skills (default: \$HOME/.claude/skills,
                 o la variable de entorno DEST si está definida).
  --dry-run      Muestra qué haría (copias, respaldos) SIN tocar el disco.
  -h, --help     Esta ayuda.

Instala: ${SKILLS[*]}
EOF
}

# ---------------------------------------------------------------------------
# Parseo de argumentos
# ---------------------------------------------------------------------------
DRY_RUN=0
DEST="${DEST:-}"   # env DEST si viene; se resuelve más abajo

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { err "--dest requiere un directorio."; exit 2; }
      DEST="$2"; shift 2 ;;
    --dest=*)
      DEST="${1#--dest=}"; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      err "Argumento desconocido: $1"; usage >&2; exit 2 ;;
  esac
done

# Resolver destino final. Rechazar destino vacío EXPLÍCITO (--dest '' o DEST='') ANTES de aplicar el
# default: si DEST está SET pero vacío, es un footgun (instalaría en el home sin que el usuario lo note).
if [[ -n "${DEST+x}" && -z "$DEST" ]]; then
  err "Destino vacío (--dest '' o DEST=''); abortando por seguridad. Omite --dest para usar el default."
  exit 2
fi
DEST="${DEST:-$DEFAULT_DEST}"

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

# Bring-your-own (WARN, nunca error):
hdr "Componentes bring-your-own (no vienen con el repo)"

# (a) Launcher de worktrees: no hay binario estándar; heurística por env var.
LAUNCHER_OK=0
if [[ -n "${PARALELA_LAUNCHER:-}" ]] && command -v "${PARALELA_LAUNCHER%% *}" >/dev/null 2>&1; then
  ok "launcher de worktrees: \$PARALELA_LAUNCHER=${PARALELA_LAUNCHER}"
  LAUNCHER_OK=1
else
  warn "launcher de worktrees NO detectado (bring-your-own)."
  info "     Sin él, /paralela no puede arrancar workers. Debe: dado '-w <id>' crear worktree+rama,"
  info "     lanzar un worker 'claude' con permisos y reenviar --settings/--append-system-prompt/--model."
  info "     Define \$PARALELA_LAUNCHER apuntando a tu launcher, o consúltalo en SKILL.md (<launcher>)."
fi

# (b) Skill 'revisar' para el gate CERRAR.
REVISAR_OK=0
if [[ -d "$DEST/revisar" ]]; then
  ok "skill 'revisar' presente en $DEST/revisar (gate CERRAR)."
  REVISAR_OK=1
else
  warn "skill 'revisar' NO encontrado en $DEST (bring-your-own)."
  info "     El gate CERRAR (retador→auditor) lo usa /paralela al integrar. Instálalo aparte."
fi

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
info "${C_B}Falta (bring-your-own):${C_0}"
(( LAUNCHER_OK )) || info "   - launcher de worktrees (sin él /paralela no lanza workers)"
(( REVISAR_OK ))  || info "   - skill 'revisar' (gate CERRAR)"
if (( LAUNCHER_OK && REVISAR_OK )); then
  info "   - (nada: launcher y 'revisar' detectados)"
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
