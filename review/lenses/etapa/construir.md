# Lente etapa: CONSTRUIR (cuestionar la implementación)

- **Fidelidad al plan:** ¿el diff hace lo que el plan dijo? ¿hay *scope creep* o desvío no acordado?
- **Correctitud:** casos borde, errores, nulos/vacíos, concurrencia. ¿Qué entrada lo rompe?
- **Regresiones:** ¿rompe algo existente? contratos, callers, comportamiento previo.
- **Idioma del código:** ¿sigue convenciones, naming y patrones del código circundante, o introduce estilo ajeno?
- **Simplicidad:** ¿hay complejidad innecesaria? ¿se pudo **reutilizar** algo existente en vez de crear?
- **Verificación:** ¿se **ejecutó/observó** lo construido, o solo "compila/debería andar"? ¿qué NO se probó?
