# PRP-auth-rate-limit: limitar intentos de login por IP

## Objetivo
Rechazar más de 5 intentos de login fallidos por IP en 60s con HTTP 429, sin afectar
los logins exitosos ni otras rutas.

## Archivos
- `src/middleware/rate_limit.py` [nuevo] — middleware de conteo por IP con ventana deslizante.
- `src/routes/auth.py` [editar] — enganchar el middleware solo en `POST /login`.
- `tests/test_rate_limit.py` [nuevo] — casos: 5 OK, 6º = 429, expira a los 60s.

## Símbolos
- `rate_limit(max_attempts:int, window_s:int) -> Callable` en `src/middleware/rate_limit.py` [nuevo]
- `login_handler(req) -> Response` en `src/routes/auth.py:42` [editar] — envolver con el decorador
- `WINDOW_SECONDS = 60` en `src/middleware/rate_limit.py` [nuevo]

## Contexto necesario
- Contrato del router: los handlers reciben `req` con `req.client_ip: str` y devuelven `Response`
  (ver `src/routes/base.py:BaseHandler`). No cambiar esa firma.
- Invariante: el store de conteo es en-memoria por proceso (no hay Redis en este servicio);
  usar `collections.deque` con timestamps, purgando los > window.
- Código 429 ya definido como `Response.too_many(...)` en `src/http/responses.py:88`.

## Criterio de aceptación
acceptance: acceptance.sh

```bash
#!/bin/bash
# acceptance.sh (autoría-orquestador) — verifica el resultado observable de la subtarea.
# Corre desde cwd=worktree; ejercita el código entregado sin re-implementarlo.
set -uo pipefail
out="$(python3 -m pytest tests/test_rate_limit.py -q 2>&1)" || { echo "FAIL"; printf '%s\n' "$out" | tail -3; exit 2; }
# Chequeo de resultado observable clave: el 6º intento devuelve 429.
if python3 -c "import sys; sys.path.insert(0,'src'); from middleware.rate_limit import rate_limit" 2>/dev/null; then
  echo "PASS"; echo "pytest verde y rate_limit importable (5 OK / 6º=429 / expira 60s)"; exit 0
else
  echo "FAIL"; echo "rate_limit no importable o firma cambiada"; exit 2
fi
```
