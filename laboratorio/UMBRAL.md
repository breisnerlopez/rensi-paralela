# Umbral: ¿desde qué tamaño de contexto compartido gana warm (fork in-process) a cold (paralela)?

Tarea mínima (responder la fruta) para aislar la ENTREGA de contexto. N=3 workers. Contexto único por fase.

| ctx (~tokens) | cold (tok) | warm (tok) | Δ cold-warm | ganador | cold t(s) | warm t(s) |
|---:|---:|---:|---:|:---:|---:|---:|
| ~1844 | 133487 | 141798 | -8311 | cold | 9 | 28 |
| ~7304 | 312725 | 290477 | 22248 | **warm** | 6 | 30 |
| ~14584 | 769874 | 497516 | 272358 | **warm** | 16 | 35 |
| ~29144 | 0 | 0 | 0 | cold | 0 | 0 |

_Δ>0 => cold gasta más (warm gana). El umbral es el ctx donde Δ pasa de negativo a positivo._
_Una corrida por punto (caché ruidoso). Tokens = suma ponderada (in+1.25·creation+0.1·read+out) de todos los transcripts del repo por fase (warm incluye el orquestador)._
