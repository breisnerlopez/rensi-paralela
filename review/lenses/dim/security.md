# Lente dim: SECURITY  (ALTO RIESGO → auditoría siempre)

- **AuthZ/AuthN:** ¿se verifica permiso en cada entrada sensible? IDOR / referencias directas.
- **Secretos:** claves/tokens/credenciales en código, logs o commits.
- **Inyección:** SQL / command / template; entradas sin sanitizar; deserialización insegura.
- **Datos sensibles:** exposición en respuestas, logs o mensajes de error.
- **Dependencias:** versiones vulnerables; superficie de ataque añadida.
- Señal de alarma: construir queries/comandos por concatenación de input.
