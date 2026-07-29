# paralela+ — Roadmap y Plan de Implementación (v0.2)

> **Gate PLAN pasado con condiciones** (retador Opus). Este doc integra C1–C6. **Auditor OBLIGATORIO
> antes de construir** (paralela es skill privilegiada: lanza workers con `--dangerously-skip-permissions`
> + guardarraíles de seguridad → dimensión security/config).
> **Espíritu innegociable:** paralelizar interactivo y **monitoreable** — workers cold en git worktrees,
> procesos separados observables, buzón ask/answer, gate adversarial, integración por clon limpio.
> **Regla de honestidad:** toda mejora se mide; nada se vende sin evidencia con reps.

## 0. Por qué el núcleo NO cambia (medido)
warm-resume no ahorra (cwd rompe caché); fork in-process no es observable; cold es más rápido y
observable → **el modelo de paralela es correcto.** Las mejoras vienen de **precisión y trazabilidad**,
NO de un truco de tokens.

## 1. Reencuadre tras el gate: ¿de qué es la ganancia, honestamente?
El retador demolió la justificación de tokens: **paralela YA pre-empaqueta contexto** (`SKILL.md:148-150`),
así que ya está del lado bueno del 7% cold-prepack-vs-explore. El delta que F1 puede reclamar es
**prepack-estructurado (PRP) vs prepack-adhoc**, que nadie midió y que la evidencia ("el formato no mejora
al LLM", empate 3.0 vs 2.75) sugiere **≈0 en tokens**. Por lo tanto:

| # | Feature | Objetivo PRIMARIO (fiable) | Tokens | Nota |
|---|---|---|---|---|
| F1 | **PRP por subtarea** (blueprint LEAN: rutas/símbolos + contexto declarado + acceptance) | **Precisión** (menos haystack, más foco) | secundario, **NO esperado** (baseline ya prepack-ea; 3 reps no pueden detectar 7% con CV≈2×) | consistencia del prepack, no menos tokens |
| F2 | **Validación-como-autoridad** (acceptance verificable re-corrido por el orquestador) | **Precisión** (verdad = validación, no auto-reporte) | neutro | ver C4: autoría + fallback + valor marginal |
| F3 | **Completitud del handoff — LINT/WARN, no gate** | **Trazabilidad/monitoreo** | ≈0 | NO rechaza/reabre por defecto (evita loop) |
| F4 | **Declaración explícita de contexto** (el PRP declara SOLO lo necesario) | **Precisión** (menos ruido) | leve, no reclamado | parte del PRP |

**Titular honesto del proyecto:** paralela+ mejora **precisión y auditabilidad** del fan-out interactivo;
**no promete menos tokens** (medido: contra baseline justo el efecto es ≈0/indetectable).

## 2. Baseline JUSTO (C1 — condición dura del método)
El baseline de TODA comparación = **`paralela` actual TAL CUAL, con su pre-empaquetado**, y **la misma
convención/contexto disponible a ambos brazos**. Prohibido comparar contra "worker sin contexto" (hombre
de paja). El discriminante de precisión debe darle la convención a **ambos** brazos; lo que se testea es
si la ESTRUCTURA (PRP + validación) hace el resultado más consistente, no si "tener contexto" ayuda.

## 3. Las 4 features, corregidas

**F1 · PRP (precisión).** Un scout explora 1× y emite por subtarea un `PRP-<id>.md` LEAN: archivos/símbolos
exactos, contexto-necesario **declarado** (F4), y criterio de aceptación. `prp_lint.sh` **penaliza PRPs
gigantes** (LEAN, no dump — medido que el dump baja precisión). **Break-even del scout medido** (C6): su
exploración extra debe amortizar sobre N workers o no se usa.

**F2 · Validación-autoridad (precisión).** Corrección C4:
- **Autoría:** el acceptance lo redacta **el orquestador como parte del PRP** (subagente barato), NO el
  humano. Para tareas **sin PASS/FAIL claro** (exploración/diseño/refactor): el "acceptance" es un
  **criterio verificable no-test** (p.ej. "el símbolo X existe y se usa en Y") o, si no hay ninguno, la
  subtarea se marca **`no-acceptance`** y cae en el gate CERRAR central como hoy (F2 no aplica, no bloquea).
- **Valor marginal sobre el CERRAR actual:** el acceptance por-subtarea corre **en el worker, temprano**
  (atrapa el defecto antes de integrar, barato) y el orquestador lo **re-corre** en el diff de esa rama.
  El CERRAR central sigue corriendo la suite del repo **una vez** al final. No se duplica: acceptance =
  smoke-test local por-rama; CERRAR = verificación integral. Si esta distinción no aporta en la práctica,
  el E2E lo dirá (§5) y se descarta F2.

**F3 · Completitud = LINT/WARN (trazabilidad).** Corrección C3: `handoff_complete.sh` **reporta** secciones
faltantes del `done.json` para auditoría/monitoreo, pero **NO rechaza ni reabre** al worker (un done.json
delgado ≠ trabajo delgado; rechazar forzaría re-describir trabajo ya commiteado = tokens sin mejora). El
orquestador VE el warn al supervisar (sirve al humano que monitorea). Opción "reject" queda fuera de v0.2.

**F4 · Contexto declarado (precisión).** Parte del schema del PRP; el `prp_lint` exige la sección.

## 4. Plan de implementación (paralelizado donde rinde — C-menor)
**Nota honesta:** la ruta crítica la domina el **E2E** (§5), no los 3 scripts. Paralelizar Fase 1 ahorra
poco al wall-clock total; se hace igual porque es gratis (sin solapamiento), sin sobre-invertir en coordinación.
- **Fase 0 (serial, corta):** layout en `paralela-plus/{prp,validation,handoff,tests}` + congelar nombres
  de interfaz compartidos. Staging: NO se tocan los archivos reales de la skill hasta Fase 2.
- **Fase 1 (3 workstreams en paralelo, sin solapamiento):**
  - WS-A: `prp/{prp-template.md, scout-prompt.md, prp_lint.sh}` (+ penalización de tamaño).
  - WS-B: `validation/{acceptance-contract.md, accept_run.sh}` (+ fallback no-acceptance).
  - WS-C: `handoff/{handoff_complete.sh (lint/warn), done-schema.md}` (reusa skill `context-package`).
- **Fase 2 (serial):** tejer en `SKILL.md` + `worker-protocol` (un editor). **Antes de tocar los archivos
  reales de la skill: auditor** (privilegiada/security).

## 5. Plan de pruebas (C5 — método honesto)
**El E2E mide PRIMARIO = precisión + no-regresión del espíritu. Tokens = solo banda, SIN conclusión**
(medido: 3 reps no pueden distinguir ~7% del ruido CV≈2×; forzarlo sería teatro).

### 5.1 Unit por workstream (paralelo, baratas)
- A: `prp_lint` rechaza PRP sin acceptance / sin contexto declarado / **gigante**; acepta LEAN válido.
- B: `accept_run` **atrapa un defecto plantado** que el worker reporta como "hecho" (autoridad > auto-reporte).
- C: `handoff_complete` **reporta** faltantes (warn), NO bloquea; acepta uno completo.

### 5.2 E2E sobre `laboratorio/repo-sintetico` — paralela+ vs baseline JUSTO (§2), 3 reps
- **PRIMARIO — Precisión (discriminante):** convención dada a AMBOS brazos; plantar (a) un requisito de
  adherencia y (b) un **defecto que el acceptance de F2 debe atrapar y baseline dejaría pasar**. Métrica:
  ¿paralela+ atrapa el defecto / adhiere más consistente que baseline? (señal esperada FUERTE y detectable).
- **PRIMARIO — No-regresión de espíritu:** verificar que los workers siguen cold/separados/observables
  (tmux/remote-control activos), interactivos (buzón funciona), integración por clon limpio OK, master intacto.
- **SECUNDARIO — Tokens/tiempo:** reportar **banda** (min–max de 3 reps) SIN declarar ganador. Incluir el
  **costo del scout** y su **break-even** (¿a partir de qué N el scout se amortiza?).
- **Trazabilidad:** ¿los `done.json` de paralela+ pasan el lint de completitud (warn=0) vs baseline?

### 5.3 Criterio de honestidad (explícito en el reporte)
Se ESPERA que tokens salga "sin diferencia medible" — eso NO es un fallo del plan, es lo predicho. El
éxito se juzga por **precisión** (atrapar el defecto, adherencia) y **cero regresión del espíritu**.

## 6. Definition of Done (verificable)
1. F1: `prp_lint` funciona (unit A); en E2E, paralela+ **adhiere a la convención más consistente** que
   baseline justo (no "worker con vs sin contexto").
2. F2: defecto plantado **atrapado por `accept_run`**, no por el worker (unit B + E2E); fallback
   `no-acceptance` documentado y probado en una tarea sin test.
3. F3: `handoff_complete` **reporta** (warn), no bloquea (unit C); el warn es visible al monitorear.
4. E2E: paralela+ corre de punta a punta, workers observables, integra por clon limpio, gate CERRAR pasa,
   master intacto; **cero regresión del espíritu**.
5. Tokens/tiempo reportados como **banda sin conclusión** + break-even del scout; NO se declara "X% menos".
6. **Auditor pasó** sobre el diff real de la skill antes de integrar (security/config).

## 7. Riesgos (de lo medido)
- Sobre-vender tokens → mitigado: F1/F4 justificados por precisión; tokens = banda sin conclusión.
- PRP gigante = haystack → `prp_lint` penaliza tamaño.
- F2 estrecha paralela a tareas testeables → mitigado: fallback `no-acceptance` + valor marginal a validar en E2E.
- F3 loop de reescritura → eliminado (lint/warn, no gate).
- Scout añade costo neto → medir break-even (§5.2); si no amortiza, F1 no se usa.
- Scope-creep (vector store/versionado/merge/multi-provider) → **prohibido**.
- Meta: NO usar paralela sobre sí misma para construir; build con subagentes/worktrees simples.
- Skill privilegiada → **auditor obligatorio** antes de tocar archivos reales.

## 8. Estado
v0.2 — gate PLAN pasado con C1–C6 integradas. **Pendiente para construir:** aprobación del usuario +
auditor sobre el diff real. Este doc es el artefacto versionable a revisar/probar.
