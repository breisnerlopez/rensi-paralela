#!/bin/bash
# Crea el repo sintetico del lab: convencion + _core + 3 modulos a implementar + checker de adherencia.
set -euo pipefail
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$LAB/repo-sintetico"
rm -rf "$R"; mkdir -p "$R/packages/_core"
cd "$R"

# --- CONTEXTO compartido (convencion + API de _core + mapa de prefijos) ---
cp "$LAB/spike/contexto_compartido.md" "$R/CONTEXTO.md"

# --- _core real-ish (para que 'usar _core' sea verificable) ---
cat > packages/_core/index.ts <<'TS'
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
TS

# --- 3 modulos a implementar (stubs con spec) ---
declare -A DOM=( [billing]=bill [user]=usr [order]=ord )
for d in billing user order; do
  mkdir -p "packages/mod-$d"
  cat > "packages/mod-$d/SPEC.md" <<MD
# Implementar packages/mod-$d/index.ts

Exporta \`class ${d^}Service\` con un método \`async create(input: unknown): Promise<Result<{ id: string }>>\` que:
- valida el input con \`Core.validate\` (schema con al menos un campo),
- ante input invalido produce un Result con \`ok:false\` y \`code:"INVALID"\` (via \`Core.fail\`),
- genera el id con \`Core.id\` usando el PREFIJO correcto del dominio '$d' (segun CONTEXTO.md),
- loguea con \`Core.log\`, devuelve \`Core.ok({ id })\`.
- Se auto-registra con \`register("${d^}Service", new ${d^}Service())\`.
Sigue CONTEXTO.md al pie. NO uses console/Math.random/Date.now/throw new Error.
MD
done

# --- checker de adherencia (precision): puntua un index.ts de modulo ---
cat > check.sh <<'SH'
#!/bin/bash
# uso: check.sh <domain> <path-al-index.ts>  -> imprime "score /6 : detalle"
dom="$1"; f="$2"
declare -A PFX=( [billing]=bill [user]=usr [order]=ord )
declare -A CLS=( [billing]=BillingService [user]=UserService [order]=OrderService )
s=0; det=""
[ -f "$f" ] || { echo "0 /6 : NO_FILE"; exit 0; }
grep -q "class ${CLS[$dom]}" "$f" && { s=$((s+1)); det+="clase✓ "; } || det+="clase✗ "
grep -q "Core.validate" "$f"      && { s=$((s+1)); det+="validate✓ "; } || det+="validate✗ "
grep -q "Core.fail" "$f"          && { s=$((s+1)); det+="fail✓ "; } || det+="fail✗ "
grep -Eq "Core\.id\([\"']${PFX[$dom]}[\"']" "$f" && { s=$((s+1)); det+="prefijo✓ "; } || det+="prefijo✗ "
grep -Eq "async +create" "$f"     && { s=$((s+1)); det+="async✓ "; } || det+="async✗ "
grep -q "register(" "$f"          && { s=$((s+1)); det+="register✓ "; } || det+="register✗ "
# penalizaciones (anti-convencion)
if grep -Eq "console\.|Math\.random|Date\.now\(|throw new Error" "$f"; then s=$((s-2)); det+="PENAL(anti-conv) "; fi
echo "$s /6 : $det"
SH
chmod +x check.sh packages/_core/index.ts 2>/dev/null || true

git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "sintetico: _core + specs + checker"
echo "repo sintetico listo en $R (base $(git rev-parse --short HEAD))"
ls -R packages | head -30
