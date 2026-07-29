# Laboratorio: paralela (cold) vs fork in-process (warm)

## Resultados (N=3 modulos, modelo sonnet)

| Métrica | paralela (cold) | fork in-process (warm) |
|---|---:|---:|
| **Tokens** (costo ponderado: in + 1.25·creation + 0.1·read + out) | 210959 | 213581 |
| **Tiempo** wall-clock (s) | 21 | 62 |
| **Precisión** (adherencia, suma /18) | 16 | 15 |

### Precisión por módulo (check de adherencia /6)
**cold:**
  - mod-billing: 6 /6 : clase✓ validate✓ fail✓ prefijo✓ async✓ register✓ 
  - mod-user: 5 /6 : clase✓ validate✓ fail✗ prefijo✓ async✓ register✓ 
  - mod-order: 5 /6 : clase✓ validate✓ fail✗ prefijo✓ async✓ register✓ 

**warm:**
  - mod-billing: 5 /6 : clase✓ validate✓ fail✗ prefijo✓ async✓ register✓ 
  - mod-user: 5 /6 : clase✓ validate✓ fail✗ prefijo✓ async✓ register✓ 
  - mod-order: 5 /6 : clase✓ validate✓ fail✗ prefijo✓ async✓ register✓ 


_Notas: cold = 3 procesos `claude --worktree` con contexto pre-empaquetado en el prompt (proxy de
paralela, SIN el overhead de orquestación/tmux/remote-control que paralela real añade → generoso con cold).
warm = 1 orquestador + 3 forks in-process con isolation:worktree (heredan contexto). Tokens = suma
ponderada de TODOS los transcripts del repo (incluye orquestador en warm). Una sola corrida (el caché es
ruidoso; para conclusión firme haría falta N reps)._
