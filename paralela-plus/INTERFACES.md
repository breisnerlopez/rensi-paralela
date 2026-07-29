# Contrato de interfaces (Fase 0 — CONGELADO para paralelizar Fase 1)

Los 3 workstreams (WS-A/B/C) escriben en subdirs distintos → sin colisión. Este contrato fija los
NOMBRES, ARGUMENTOS y FORMATOS que la integración (Fase 2) y los tests consumen. No cambiar sin re-freeze.

## Layout
```
paralela-plus/
  prp/          # WS-A
  validation/   # WS-B
  handoff/      # WS-C
  tests/        # tests unit por workstream (los agrega cada WS en tests/<ws>_test.sh)
```

## WS-A — PRP layer
- `prp/prp-template.md` — plantilla del blueprint por subtarea. Secciones OBLIGATORIAS (el linter las exige):
  `## Objetivo`, `## Archivos`, `## Símbolos`, `## Contexto necesario` (F4: solo lo que la subtarea usa),
  `## Criterio de aceptación` (referencia a un acceptance ejecutable o un criterio verificable no-test).
- `prp/scout-prompt.md` — instrucción para el subagente scout: explora 1× el repo y emite N `PRP-<id>.md`
  LEAN (uno por subtarea). Debe advertir: LEAN, no dump (medido: dump baja precisión).
- `prp/prp_lint.sh <PRP.md>` — exit 0 = OK; exit≠0 = imprime faltantes. DEBE fallar si: falta una sección,
  falta `## Contexto necesario`, o el archivo es **gigante** (> ~400 líneas o > ~15000 chars = penaliza dump).
- Entrega también: `prp/PRP-ejemplo.md` (un PRP válido de muestra que pasa el linter).

## WS-B — Validación-como-autoridad
- `validation/acceptance-contract.md` — convención: cada subtarea ships `acceptance.sh` en su worktree que
  imprime en la 1ª línea `PASS` o `FAIL` y hasta 5 líneas de detalle; exit 0=PASS, 2=FAIL.
  Fallback: si la subtarea es exploratoria/diseño sin PASS/FAIL, el PRP declara `acceptance: no-acceptance`
  y F2 NO aplica (cae al gate CERRAR central; no bloquea).
- `validation/accept_run.sh <ruta-worktree>` — el ORQUESTADOR re-corre el `acceptance.sh` de ese worktree
  (NO confía en el auto-reporte del worker). Imprime `PASS`/`FAIL` + detalle. Si no hay acceptance.sh y el
  PRP dice `no-acceptance` → imprime `SKIP (no-acceptance)` exit 0; si falta sin declararlo → `FAIL exit 2`.
- Entrega también: `validation/acceptance-ejemplo.sh` (uno que pasa) + un caso de defecto plantado para el test.

## WS-C — Completitud del handoff (LINT/WARN, NO gate)
- `handoff/done-schema.md` — el `done.json`/handoff reusa el schema de handoff estructurado
  `context-package` (secciones Resumen, Decisiones, Hallazgos, Riesgos, Pendientes,
  Para-el-siguiente-agente, Referencias) + campos rama/summary/gate_veredicto del done.json actual.
- `handoff/handoff_complete.sh <archivo>` — **REPORTA** (warn) secciones faltantes; **exit SIEMPRE 0**
  (es lint/warn, NO bloquea — decisión del gate PLAN). Imprime `WARN: falta X Y` o `OK: completo`.
- Entrega también: `handoff/done-ejemplo.md` (completo) para el test.

## Convención común de tests
Cada WS deja `tests/<ws>_test.sh` que ejercita su script con casos válido/ inválido y devuelve
`PASS`/`FAIL` por caso. Sin dependencias externas (bash + grep + python3 stdlib).
