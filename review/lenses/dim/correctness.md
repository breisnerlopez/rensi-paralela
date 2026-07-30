# Lente dim: CORRECTNESS

- **Lógica:** condiciones invertidas, off-by-one, comparaciones erróneas, precedencia.
- **Edge cases:** vacío, null/None, cero, negativos, límites, unicode, concurrencia.
- **Manejo de errores:** ¿se tragan excepciones? ¿estados parciales? ¿reintentos idempotentes?
- **Contratos:** precondiciones/postcondiciones; ¿se respetan invariantes?
- Señal de alarma: solo happy-path, sin pruebas del caso de falla.
