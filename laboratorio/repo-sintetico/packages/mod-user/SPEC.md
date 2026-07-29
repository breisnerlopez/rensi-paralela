# Implementar packages/mod-user/index.ts

Exporta `class UserService` con un método `async create(input: unknown): Promise<Result<{ id: string }>>` que:
- valida el input con `Core.validate` (schema con al menos un campo),
- ante input invalido produce un Result con `ok:false` y `code:"INVALID"` (via `Core.fail`),
- genera el id con `Core.id` usando el PREFIJO correcto del dominio 'user' (segun CONTEXTO.md),
- loguea con `Core.log`, devuelve `Core.ok({ id })`.
- Se auto-registra con `register("UserService", new UserService())`.
Sigue CONTEXTO.md al pie. NO uses console/Math.random/Date.now/throw new Error.
