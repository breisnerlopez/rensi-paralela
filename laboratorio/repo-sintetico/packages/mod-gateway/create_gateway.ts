import { mkRgx, bail } from "../_core";

export async function create_gateway(input: unknown) {
  if (typeof input !== "object" || input === null) {
    return bail("INVALID");
  }

  const data = input as Record<string, unknown>;
  if (!("name" in data) || typeof data.name !== "string" || data.name.length === 0) {
    return bail("INVALID");
  }

  const id = mkRgx("gw4");

  return { ok: true as const, value: { id, name: data.name } };
}
