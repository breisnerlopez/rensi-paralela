---
name: revisar
description: Corre el gate adversarial (retador → auditor) sobre una etapa del trabajo (idea | plan | construir | cerrar). Úsalo antes de avanzar de etapa en trabajo no trivial, o cuando quieras estresar una idea, un plan, un diff o un documento contra un revisor adversarial y, si queda duda o hay alto riesgo, un auditor especialista.
argument-hint: "[idea|plan|construir|cerrar] <qué revisar>"
---

Orquesta el gate adversarial genérico sobre `$ARGUMENTS`. Pasos:

1. **Clasifica** el trabajo:
   - **etapa**: idea | plan | construir | cerrar. Si el usuario la dio en `$ARGUMENTS`, úsala; si no, dedúcela del estado del trabajo.
   - **nivel** (proporcionalidad, escalado por riesgo): `trivial` | `normal` | `grande/alto-riesgo`.
   - Anuncia al usuario el nivel y qué gates aplicarás: trivial → ninguno; normal → idea ligero + construir; grande/alto-riesgo → los 4 gates + auditor. El usuario puede objetar.

2. **Selecciona lentes** desde `~/.claude/review/lenses/`:
   - siempre `_base.md` + la de etapa `etapa/<etapa>.md`.
   - en construir: las de dimensión `dim/*.md` que apliquen a lo que toca el cambio (por tipo de archivo/contenido).
   - **Alto riesgo** = security ∪ data ∪ config-prod.

3. **Retador**: lanza el subagente `retador` (read-only) con la etapa, el entregable y las rutas de lentes. Es independiente: pásale el entregable, no tu defensa de él.
   - **Modelo por criticidad:** en nivel `normal` déjalo en Sonnet (default); en nivel `grande/alto-riesgo` **sobrescribe con `model: opus`** al lanzarlo con la herramienta Agent. Esfuerzo siempre alto.

4. **Escalamiento**: lanza el subagente `auditor` (model opus) sobre la dimensión afectada SI el retador marca ESCALAR (ítems refutados/no-verificables, desacuerdo), O SI el cambio toca alto riesgo (security/data/config-prod) — auditoría obligatoria aunque el retador apruebe. Pásale el entregable + los hallazgos en disputa.

5. **Sintetiza**: presenta veredicto del retador + (si hubo) fallo del auditor + las correcciones requeridas antes de avanzar de etapa. No avances de etapa con bloqueos sin resolver.
