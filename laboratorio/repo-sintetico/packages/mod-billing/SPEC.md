# Implementar packages/mod-billing/index.ts

Exporta `class BillingService` con un método `async create(input: unknown): Promise<Result<{ id: string }>>` que:
- valida el input con `Core.validate` (schema con al menos un campo),
- ante input invalido produce un Result con `ok:false` y `code:"INVALID"` (via `Core.fail`),
- genera el id con `Core.id` usando el PREFIJO correcto del dominio 'billing' (segun CONTEXTO.md),
- loguea con `Core.log`, devuelve `Core.ok({ id })`.
- Se auto-registra con `register("BillingService", new BillingService())`.
Sigue CONTEXTO.md al pie. NO uses console/Math.random/Date.now/throw new Error.
