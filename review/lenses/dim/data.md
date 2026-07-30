# Lente dim: DATA  (ALTO RIESGO → auditoría siempre)

- **Migraciones:** ¿reversible? ¿backfill seguro? ¿bloqueos de tabla en caliente?
- **Pérdida de datos:** DELETE/DROP/UPDATE sin WHERE acotado; truncamientos.
- **Idempotencia:** ¿re-ejecutar rompe o duplica?
- **Integridad:** FKs, constraints, transacciones; estados intermedios visibles.
- **Respaldo/rollback:** ¿hay copia previa? ¿cómo se revierte?
