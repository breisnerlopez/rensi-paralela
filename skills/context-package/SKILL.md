---
name: context-package
description: Handoff estructurado ligero entre agentes/sesiones. Un subagente emite un "context package" en markdown (decisiones, hallazgos, pendientes, referencias) que el orquestador o el siguiente agente consume como punto de partida. Para TRAZABILIDAD y CONTINUIDAD, no para ahorrar tokens.
---

# Context Package (handoff ligero)

## Qué es y para qué (honesto, MEDIDO)
Un paquete de contexto **estructurado en markdown** que un subagente emite al terminar, para que el
orquestador o el siguiente agente lo consuma. Valor y no-valor, según medición (ver `laboratorio/`):
- **NO ahorra tokens** (≈0 fiable; la entrega de contexto es ruido frente al costo del trabajo).
- **NO hace que el LLM "entienda mejor"**: se midió (4 reps) que un agente downstream respeta las
  decisiones igual desde un resumen en TEXTO LIBRE (3.0/3) que desde el schema (2.75/3) — empate.
- **SÍ aporta valor para HUMANOS y MÁQUINAS**: trazabilidad, auditoría, parseabilidad (búsqueda/tooling),
  y — plausible, no testeado — **forzar que el emisor produzca un handoff completo** (llena decisiones/
  riesgos/pendientes que en prosa podría omitir).
Regla: úsalo por gobernanza/auditoría/completitud, NO por tokens ni por "continuidad del agente" (para eso
un buen resumen en prosa basta).

## ⚠ Gotcha práctico (medido)
Un paquete empieza con frontmatter `---`. Si el orquestador lo pega **al inicio** del prompt de un worker
lanzado por CLI (`claude -p "---..."`), la CLI interpreta `---` como una **opción desconocida** y falla.
**Siempre antepón una línea de preámbulo** ("Handoff del agente anterior:\n\n<paquete>") — nunca el `---` en la posición 0.

## Cuándo emitir / consumir
- **Emitir:** al cerrar una subtarea delegada no trivial cuya salida otro agente (o una sesión futura)
  usará. En `/paralela`, el worker lo incluye en su `done.json`/reporte.
- **Consumir:** al arrancar una subtarea que depende de trabajo previo — el orquestador lo pega en el
  prompt del siguiente worker (= pre-empaquetado) en vez de que re-derive las decisiones.
- **Persistir:** guardar como nota de **auto-memory** (`~/.claude/projects/<repo>/memory/`) → portable
  (Obsidian/OpenCode), buscable, auditable. Un archivo por handoff.

## Formato (ver TEMPLATE.md)
Frontmatter mínimo + secciones: Resumen, Decisiones (con porqué), Hallazgos, Archivos, Riesgos,
Pendientes, Para-el-siguiente-agente, Referencias. **Markdown, no JSON** (menos overhead, editable,
Obsidian-nativo).

## Reglas duras (evitar el scope-creep que la medición descartó)
- **Ligero SIEMPRE.** NADA de vector store, búsqueda semántica, motor de versionado/merge, o capa
  multi-provider. Eso reintroduce el peso/overhead de tokens que se midió como contraproducente. Si algún
  día necesitas query sobre muchos paquetes → dropea un MCP existente sobre la carpeta markdown, no lo construyas.
- **Corto.** El paquete debe ser un RESUMEN denso (decisiones + punteros), no un volcado. Un contexto
  grande entierra lo clave y hasta baja la precisión del siguiente agente (medido).
- **Un hecho/decisión por línea**, con el porqué. Referencias por ruta/commit, no pegando archivos enteros.

## Validación
`validate.sh <archivo.md>` verifica que el paquete tenga las secciones requeridas y frontmatter válido.
