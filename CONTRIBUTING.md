# Guía de contribución — `rensi-paralela`

Gracias por tu interés. Este proyecto es un orquestador de trabajo paralelo para
coding agents, más la investigación empírica que lo sustenta. Contribuir aquí
significa alinearse con su **espíritu**: precisión medida, auditabilidad y
honestidad. Lee esta guía completa antes de abrir un PR.

## Regla de honestidad (innegociable)

**Nada se vende sin datos.** Toda contribución que reclame un ahorro o una mejora
(precisión, tokens, latencia, robustez) debe **medirse con evidencia reproducible**
(repeticiones, no una corrida) y adjuntar los números crudos. Si el efecto no es
concluyente, se reporta como tal — no se maquilla.

Ejemplo del propio repo: la ganancia de **precisión** de `paralela+` se midió
(9/9 a 6/6, stdev 0 vs. baseline con varianza) y se documenta como resultado
primario. En cambio, el efecto en **tokens** salió como una **banda solapada, sin
conclusión**, y así se reporta — no se afirma que la herramienta ahorre tokens.
Esa es la vara: si tu cambio no puede demostrar lo que promete, no lo prometas.

Corolarios:
- No presentes un pulido no-medido como ahorro (p. ej. la regla anti-narración de
  workers es pulido sin baseline; se declara como tal).
- No uses `paralela` sobre sí misma para construir este proyecto (evita el reclamo
  circular y no auditable).

## Gate adversarial

Todo cambio **no trivial** pasa por el gate adversarial antes de integrarse:

1. **Retador** (read-only, adversarial) refuta el cambio en su etapa
   (idea | plan | construir | cerrar).
2. **Auditor** (2do nivel, especialista) **obligatorio** si el cambio es de
   **alto riesgo**: `security ∪ data ∪ config`, aunque el retador apruebe.

La **skill `paralela` es privilegiada**: los workers corren con
`--dangerously-skip-permissions` acotados por guardarraíles (H3
`--append-system-prompt`, H4 `worker-guard.py`). Por eso **cualquier cambio dentro
de `skills/paralela/` (o que toque los guardarraíles) requiere auditor**, sin
excepción. El productor del cambio no juzga su propio gate.

## Correr los tests antes de un PR

Corre la suite de la skill y adjunta la salida en el PR:

```bash
bash skills/paralela/tests/a_test.sh
bash skills/paralela/tests/b_test.sh
bash skills/paralela/tests/c_test.sh
```

Los tests deben pasar sin regresión. Si tocas la lógica de PRP, acceptance o
handoff, añade/actualiza el fixture correspondiente en
`skills/paralela/tests/fixtures/`.

## Estilo

- **Idioma: español** (código, comentarios, docs, mensajes de commit).
- **Scripts bash robustos:** `set -euo pipefail`, rutas absolutas, escrituras
  atómicas, códigos de salida explícitos (convención del repo: `0=PASS/SKIP`,
  `2=FAIL` donde aplique).
- **Exploración con herramientas nativas** (glob/grep/read); no reinventes.
- **No firmes commits ni PRs:** sin trailers `Co-Authored-By`, sin líneas
  "Generated with…", sin enlaces de sesión.

## Alcance PROHIBIDO (scope-creep de la hoja de ruta)

Estas ideas están **explícitamente fuera de alcance**; los PRs que las introduzcan
serán rechazados salvo discusión previa y reapertura del roadmap:

- Vector store / indexación semántica del repo.
- Versionado o snapshotting propio (git ya es la fuente de verdad).
- **Merge automático** sin gate CERRAR ni revisión humana.
- Soporte multi-provider como objetivo (el contrato es bring-your-own runtime).

## Precondición de seguridad

- La herramienta opera **solo sobre repos confiables** (los workers corren con
  permisos elevados).
- **No debilites los guardarraíles.** H3 (`--append-system-prompt`), H4
  (`--settings` con `worker-guard.py`) y el `worker-guard` que BLOQUEA
  push/red/sudo/rutas sensibles son parte del contrato de seguridad; relajarlos es
  alto riesgo y requiere auditor con fallo vinculante.

## Cómo enviar un PR

1. Rama desde `main` (nunca commitees directo a `main`).
2. Cambio acotado, con evidencia medida si reclama una mejora.
3. Tests corridos y su salida adjunta.
4. Declara si el cambio es de alto riesgo (skill/guardarraíles) para el auditor.
