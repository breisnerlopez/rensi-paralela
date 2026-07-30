#!/bin/bash
# sumar.sh — "trabajo entregado" por el worker para la subtarea "implementar sumar(a,b)".
# DEFECTO PLANTADO: el worker reportó "hecho" pero esto RESTA en vez de sumar.
# El auto-reporte dice OK; el acceptance re-corrido por el orquestador lo atrapa (autoridad > reporte).
sumar() { echo $(( $1 - $2 )); }   # <-- BUG: debería ser $1 + $2
