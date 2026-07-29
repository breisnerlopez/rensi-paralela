# orch-lib.sh — primitivas del buzón para /paralela (orquestador y workers).
# Sourcear: `source "$ORCH/bin/orch-lib.sh"`. Validado en Fase 0.

# atomic_write <destino> <contenido> : escribe con tempfile + rename atómico
# (mismo fs), para que un lector nunca vea contenido parcial. El contenido es UN
# solo argumento (comíllalo): usa "$2", no "$*".
atomic_write() {
  local dest="$1" content="$2"
  local dir; dir="$(dirname "$dest")"
  mkdir -p "$dir"
  local tmp; tmp="$(mktemp "$dir/.tmp.XXXXXX")"
  printf '%s' "$content" > "$tmp"
  mv -f "$tmp" "$dest"
}

# emit_json <destino> <k1> <v1> [<k2> <v2> ...] : escribe JSON VÁLIDO y atómico a
# partir de pares clave/valor. python hace el escaping, así que los valores pueden
# contener comillas, saltos de línea, `$`, `\` sin romper el JSON. USAR ESTO para
# status/ask/done/blocked en vez de armar JSON a mano.
emit_json() {
  local dest="$1"; shift
  local dir; dir="$(dirname "$dest")"; mkdir -p "$dir"
  local tmp; tmp="$(mktemp "$dir/.tmp.XXXXXX")"
  python3 -c 'import json,sys
a=sys.argv[2:]; d={a[i]:a[i+1] for i in range(0,len(a)-1,2)}
open(sys.argv[1],"w").write(json.dumps(d))' "$tmp" "$@" && mv -f "$tmp" "$dest"
}

# orch_wait <archivo_respuesta> <ttl_seg> : bloquea hasta que exista el archivo
# (aparece por rename atómico) o venza el TTL. Imprime el contenido, o "__TTL__"
# y retorna 2 si expira. Bloqueo MECÁNICO: el worker no "decide seguir esperando".
orch_wait() {
  local ans="$1" ttl="${2:-300}" waited=0
  while [ ! -f "$ans" ]; do
    sleep 1; waited=$((waited+1))
    if [ "$waited" -ge "$ttl" ]; then echo "__TTL__"; return 2; fi
  done
  cat "$ans"
}
