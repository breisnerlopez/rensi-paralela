#!/usr/bin/env python3
# worker-guard.py — Hook PreToolUse para workers de /paralela: BLOQUEA (deny) las
# acciones externas/peligrosas que la "regla dura" solo pedía por prompt. Se pasa al
# worker vía `--settings` por-lanzamiento (opt-in; cero huella en sesiones normales).
# Deny = exit 2 con motivo en stderr (protocolo de hooks de Claude Code).
#
# HONESTIDAD: es una DENYLIST (defensa en profundidad), no una jaula. Sube mucho la
# barrera vs prompt-only y corta los vectores obvios (push/red/escalada/rutas sensibles),
# pero un ataque decidido puede ofuscar (base64|bash, etc.). Para contencion total hace
# falta el aislamiento (contenedor/usuario dedicado) que el usuario declino.
import sys, json, re, os

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)  # fail-open: no romper al worker si el input no parsea

tool = d.get("tool_name", "") or ""
ti = d.get("tool_input", {}) or {}
HOME = os.environ.get("HOME") or os.path.expanduser("~")

def deny(msg):
    sys.stderr.write(
        "BLOQUEADO por /paralela (worker sin acciones externas): %s. "
        "Si de verdad lo necesitas, usa el protocolo ask para pedirselo al orquestador." % msg
    )
    sys.exit(2)

# Rutas realmente sensibles. CLAVE: los dotfiles del home se anclan al $HOME REAL
# (normalizando rutas absolutas de home a '~'), para NO tener falsos positivos con la
# ruta del propio worktree, que vive en <repo>/.claude/worktrees/ (que NO es ~/.claude).
HOME_DOTS = re.compile(r'~/\.(ssh|claude|aws|kube|cloudflared|gnupg|docker|npmrc|config/gh)\b', re.I)
GLOBAL_SENS = re.compile(r'(/etc/|\bauthorized_keys\b|\.git/hooks\b|\bcredentials\b|id_rsa|id_ed25519)', re.I)

def hits_sensitive(s):
    if not s:
        return False
    s2 = s.replace(HOME, "~")  # /home/user/.ssh -> ~/.ssh ; worktree (/repo/.claude/...) intacto
    return bool(HOME_DOTS.search(s2) or GLOBAL_SENS.search(s2))

if tool == "Bash":
    cmd = ti.get("command", "") or ""
    # red saliente / escalada / acceso remoto
    if re.search(r'(?:^|[^\w])(sudo|ssh|scp|sftp|rsync|curl|wget|nc|ncat|telnet)(?:[^\w]|$)', cmd, re.I):
        deny("comando de red/escalada/remoto")
    # push a remoto (accion externa irreversible)
    if re.search(r'git\s+(?:[^&|;]*\s)?push', cmd, re.I):
        deny("git push (accion externa)")
    # tocar rutas sensibles
    if hits_sensitive(cmd):
        deny("ruta sensible en el comando")
elif tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
    fp = ti.get("file_path") or ti.get("notebook_path") or ""
    if hits_sensitive(fp):
        deny("escritura a ruta sensible: %s" % fp)

sys.exit(0)
