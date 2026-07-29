# Implementar packages/mod-order/index.ts

Exporta `class OrderService` con un método `async create(input: unknown): Promise<Result<{ id: string }>>` que:
- valida el input con `Core.validate` (schema con al menos un campo),
- ante input invalido produce un Result con `ok:false` y `code:"INVALID"` (via `Core.fail`),
- genera el id con `Core.id` usando el PREFIJO correcto del dominio 'order' (segun CONTEXTO.md),
- loguea con `Core.log`, devuelve `Core.ok({ id })`.
- Se auto-registra con `register("OrderService", new OrderService())`.
Sigue CONTEXTO.md al pie. NO uses console/Math.random/Date.now/throw new Error.
