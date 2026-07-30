# Contrato de interfaces — histórico de Fase 0 (CONGELADO)

> **Estado: documento histórico.** Este contrato congeló, para paralelizar Fase 1, los NOMBRES,
> ARGUMENTOS y FORMATOS que la integración (Fase 2) y los tests consumen. **El layout de staging
> `paralela-plus/` ya no existe:** al cerrar el proyecto se **colapsó dentro de
> [`../skills/paralela/`](../skills/paralela/)** (los ejecutables y los `.md` de contrato viven ahora
> ahí, planos). La **referencia técnica vigente** —args/exit codes/formatos actuales— es
> [`REFERENCIA.md`](REFERENCIA.md); el diseño y rationale, [`ARQUITECTURA.md`](ARQUITECTURA.md). Este
> archivo se conserva por trazabilidad del contrato original y del re-freeze del gate CERRAR (WS-B).

Los 3 workstreams (WS-A/B/C) escribían en subdirs distintos → sin colisión.

## Mapa de rutas (staging Fase 0 → layout final)
El colapso fue mecánico: todos los archivos de los tres subdirs quedaron planos en `skills/paralela/`.

| Contrato Fase 0 (`paralela-plus/…`) | Ruta final vigente |
|-------------------------------------|--------------------|
| `prp/prp-template.md` | [`../skills/paralela/prp-template.md`](../skills/paralela/prp-template.md) |
| `prp/scout-prompt.md` | [`../skills/paralela/scout-prompt.md`](../skills/paralela/scout-prompt.md) |
| `prp/prp_lint.sh` | [`../skills/paralela/prp_lint.sh`](../skills/paralela/prp_lint.sh) |
| `prp/PRP-ejemplo.md` | `../skills/paralela/PRP-ejemplo.md` |
| `validation/acceptance-contract.md` | [`../skills/paralela/acceptance-contract.md`](../skills/paralela/acceptance-contract.md) |
| `validation/accept_run.sh` | [`../skills/paralela/accept_run.sh`](../skills/paralela/accept_run.sh) |
| `validation/acceptance-ejemplo.sh` | `../skills/paralela/acceptance-ejemplo.sh` |
| `handoff/done-schema.md` | [`../skills/paralela/done-schema.md`](../skills/paralela/done-schema.md) |
| `handoff/handoff_complete.sh` | [`../skills/paralela/handoff_complete.sh`](../skills/paralela/handoff_complete.sh) |
| `handoff/done-ejemplo.md` | `../skills/paralela/done-ejemplo.md` |
| `tests/<ws>_test.sh` | `../skills/paralela/tests/<ws>_test.sh` |

El resto de este documento es el **texto original del contrato** (nombres/args/formatos), conservado
verbatim salvo las rutas. Donde diga un subdir `prp/`·`validation/`·`handoff/`, léase `skills/paralela/`.

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
> **Re-freeze (Fase 2, gate CERRAR):** el gate refutó el modelo original "el worker ships `acceptance.sh`
> en su worktree" — era auto-reporte (el worker autoraba el test que lo aprueba) y un hueco de seguridad
> (re-ejecutar bytes autoría-worker fuera del guard). Corregido a **autoría-orquestador** + firma de 2
> argumentos, alineado con el roadmap C4.
- `validation/acceptance-contract.md` — convención: el **acceptance lo AUTORA el orquestador** (como parte
  del PRP, F1), vive **orquestador-side** (no en el worktree del worker), imprime en la 1ª línea `PASS`/`FAIL`
  + hasta 5 líneas; exit 0=PASS, 2=FAIL. `accept_run` lo corre bajo `timeout` con cwd=worktree (ejercita el
  código del worker con un test que el worker no controla). Fallback: subtarea exploratoria/diseño sin
  PASS/FAIL → el PRP declara `acceptance: no-acceptance`, F2 NO aplica (cae al CERRAR central; no bloquea).
- `validation/accept_run.sh <ruta-worktree> <acceptance-script | --no-acceptance>` — el ORQUESTADOR corre
  su **acceptance canónico** (autoría-orquestador, ruta orquestador-side) contra el worktree; NO confía en
  el auto-reporte del worker. Imprime `PASS`/`FAIL`/`SKIP` + detalle; exit 0=PASS/SKIP, 2=FAIL. Con
  `--no-acceptance` → `SKIP (no-acceptance)` exit 0; sin 2º argumento → `FAIL exit 2` (no se omite validación);
  anómalo/timeout/1ª-línea-incoherente → `FAIL` (fail-closed).
- Entrega también: `validation/acceptance-ejemplo.sh` (uno que pasa) + un caso de defecto plantado para el test.

## WS-C — Completitud del handoff (LINT/WARN, NO gate)
- `handoff/done-schema.md` — el `done.json`/handoff reusa el schema de handoff estructurado
  `context-package` (secciones Resumen, Decisiones, Hallazgos, Riesgos, Pendientes,
  Para-el-siguiente-agente, Referencias) — **schema y validador ya incluidos en el repo**:
  `skills/context-package/TEMPLATE.md` + `skills/context-package/validate.sh` — más los campos
  rama/summary/gate_veredicto del **contrato de `done.json` definido en `skills/worker-protocol/SKILL.md`**
  (paso "Cierre"), también ya incluido en el repo.
- `handoff/handoff_complete.sh <archivo>` — **REPORTA** (warn) secciones faltantes; **exit SIEMPRE 0**
  (es lint/warn, NO bloquea — decisión del gate PLAN). Imprime `WARN: falta X Y` o `OK: completo`.
- Entrega también: `handoff/done-ejemplo.md` (completo) para el test.

## Convención común de tests
Cada WS deja `tests/<ws>_test.sh` que ejercita su script con casos válido/ inválido y devuelve
`PASS`/`FAIL` por caso. Sin dependencias externas (bash + grep + python3 stdlib).
