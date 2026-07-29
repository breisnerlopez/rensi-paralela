export type ErrorCode = "INVALID" | "NOT_FOUND" | "CONFLICT" | "FORBIDDEN" | "INTERNAL";
export type Result<T> = { ok: true; value: T } | { ok: false; code: ErrorCode; msg: string };
export type Schema<T> = { _t?: T; shape: Record<string,string> };
let _counter = 0;
export class CoreError extends Error { constructor(public code: ErrorCode, msg: string){ super(msg); } }
export const Core = {
  schema<T>(shape: Record<string,string>): Schema<T> { return { shape }; },
  validate<T>(schema: Schema<T>, input: unknown): T {
    if (typeof input !== "object" || input === null) throw new CoreError("INVALID", "not an object");
    for (const k of Object.keys(schema.shape)) if (!(k in (input as any))) throw new CoreError("INVALID", "missing "+k);
    return input as T;
  },
  ok<T>(value: T): Result<T> { return { ok: true, value }; },
  fail(code: ErrorCode, msg: string): never { throw new CoreError(code, msg); },
  id(prefix: string): string { _counter += 1; return prefix + "_" + _counter; },
  now(): number { return 0; },
  log: { info(){}, warn(){}, error(){} },
};
const _reg = new Map<string, unknown>();
export function register(name: string, svc: unknown){ _reg.set(name, svc); }
export function resolve<T>(name: string): T { return _reg.get(name) as T; }
