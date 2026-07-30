# Lente dim: PERFORMANCE

- **Complejidad:** bucles anidados, O(n²) en caliente, N+1 de queries.
- **Recursos:** fugas (conexiones, ficheros, memoria); sin cierre/timeout.
- **Escala:** ¿se probó con volumen real? ¿degradación con el crecimiento?
- **Costo:** llamadas de red/IO redundantes; falta de caché/batch.
