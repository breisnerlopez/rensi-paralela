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
