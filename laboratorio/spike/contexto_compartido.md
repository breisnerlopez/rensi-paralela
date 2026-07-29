# Contexto compartido del monorepo `acme-platform` (pre-empaquetado por el orquestador)

Este documento es el contexto que TODAS las subtareas comparten. Un worker debe conocerlo para
implementar correctamente su módulo. Contiene: convención de código, el módulo base `_core`, y el
registro de módulos.

## 1. Convención de código (OBLIGATORIA)

- **Nombres de módulos:** `mod-<dominio>` en kebab-case. El export principal de cada módulo es una clase
  `<Dominio>Service` en PascalCase (ej. `mod-billing` → `BillingService`).
- **Validación:** NUNCA validar a mano. Todo input público pasa por `Core.validate(schema, input)` de
  `_core`. Los schemas se declaran con `Core.schema({...})`.
- **Errores:** lanzar `Core.fail(code, msg)` con un `code` de `ErrorCode` (nunca `throw new Error`).
- **IDs:** generar con `Core.id(prefix)` — jamás `Math.random` ni `uuid` directo.
- **Logging:** `Core.log.info/warn/error`, nunca `console.*`.
- **Async:** todos los métodos públicos son `async` y devuelven `Result<T>` (de `_core`), nunca lanzan
  hacia afuera salvo `Core.fail`.
- **Tiempos:** `Core.now()` (inyectable/testeable), nunca `Date.now()`.

## 2. Módulo base `_core` (packages/_core/index.ts) — API pública

```ts
export type Result<T> = { ok: true; value: T } | { ok: false; code: ErrorCode; msg: string };
export type ErrorCode = "INVALID" | "NOT_FOUND" | "CONFLICT" | "FORBIDDEN" | "INTERNAL";

export const Core = {
  // Validación: devuelve el input tipado o lanza Core.fail("INVALID", ...)
  validate<T>(schema: Schema<T>, input: unknown): T { /* ... */ },
  schema<T>(shape: SchemaShape): Schema<T> { /* ... */ },

  // Construcción de resultados
  ok<T>(value: T): Result<T> { return { ok: true, value }; },
  fail(code: ErrorCode, msg: string): never { throw new CoreError(code, msg); },

  // Utilidades deterministas (testeables)
  id(prefix: string): string { /* prefix + monotonic counter, NO random */ },
  now(): number { /* clock inyectable */ },

  log: {
    info(msg: string, meta?: object): void {},
    warn(msg: string, meta?: object): void {},
    error(msg: string, meta?: object): void {},
  },
};

// Los servicios se registran para descubrimiento cruzado:
export function register(name: string, svc: object): void { /* ... */ }
export function resolve<T>(name: string): T { /* ... */ }
```

**Regla de oro:** un módulo NUNCA importa a otro módulo directamente; usa `Core.resolve("<Service>")`.

## 3. Registro de módulos (packages/registry.ts)

```ts
import { register } from "./_core";
// Cada módulo se auto-registra en su index con: register("BillingService", new BillingService())
// El orquestador del monorepo llama a los index en orden alfabético.
```

## 4. Patrón de un módulo (ejemplo de referencia `mod-account`)

```ts
// packages/mod-account/index.ts
import { Core, Result, register } from "../_core";

const CreateAccountSchema = Core.schema({ email: "string", plan: "string" });

export class AccountService {
  async create(input: unknown): Promise<Result<{ id: string }>> {
    const data = Core.validate(CreateAccountSchema, input);          // validación por _core
    if (!data.email.includes("@")) Core.fail("INVALID", "bad email"); // errores por Core.fail
    const id = Core.id("acct");                                       // id por Core.id
    Core.log.info("account.created", { id });                         // log por Core.log
    return Core.ok({ id });
  }
}

register("AccountService", new AccountService());
```

## 5. Convención de tests

Cada módulo lleva `packages/mod-<x>/test.ts` con al menos:
- un caso feliz que verifica que el `Result.ok` trae el shape correcto,
- un caso que verifica que un input inválido produce `Result` con `ok:false` y `code:"INVALID"`,
- **verificación de adherencia:** el test comprueba que el servicio usa `Core.id` (el id lleva el prefijo
  esperado) y `Core.validate` (un input con campo faltante da `code:"INVALID"`, no otro error).

## 6. Notas de arquitectura (para no re-descubrir)

- El monorepo usa `pnpm` workspaces; cada `packages/mod-*` es un paquete.
- No hay red ni DB en los módulos: todo es in-memory sobre `_core`.
- La firma EXACTA que el orquestador espera de cada servicio: método público `async` que recibe `unknown`
  y devuelve `Promise<Result<...>>`. Un servicio que lance una excepción cruda (no `Core.fail`) rompe el
  contrato y el test de adherencia lo detecta.
- El prefijo de `Core.id` por dominio: billing→"bill", user→"usr", order→"ord", notify→"ntf". Usar el
  prefijo correcto es parte de la convención (el test de adherencia lo verifica).
