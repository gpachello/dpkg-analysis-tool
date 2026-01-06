#!/bin/bash
set -euo pipefail

# === Configuration ===
LOGDIR="./purge-sim"
WHITELIST_FILE="./whitelist.txt"
CRITICAL_FILE="./critical.txt"
mkdir -p "$LOGDIR"

# === Load whitelist ===
declare -a WHITELIST
if [[ -f "$WHITELIST_FILE" ]]; then
    mapfile -t WHITELIST < "$WHITELIST_FILE"
fi

# === Load critical packages (with categories) ===
declare -A CRITICAL_PKGS
if [[ -f "$CRITICAL_FILE" ]]; then
    while IFS=: read -r pkg cat; do
        [[ -n "$pkg" ]] && CRITICAL_PKGS["$pkg"]="$cat"
    done < "$CRITICAL_FILE"
fi

# === Summary file ===
SUMMARY="$LOGDIR/summary.txt"
echo "Purge simulation summary" > "$SUMMARY"
echo "========================" >> "$SUMMARY"

# === Package listing ===
# === Store package names + Essential flag in an array ===
mapfile -t PKGLIST < <(dpkg-query -W -f='${Package};${Essential}\n')

# === Totals ===
TOTAL_PKGS=$(dpkg-query -W -f='${Package}\n' | wc -l | awk '{print $1}')
TOTAL_PACKAGES=0
TOTAL_WHITELIST_AFFECTED=0

# === Helper function: check if a package is in an array ===
in_array() {
    local item="$1"
    shift
    local arr=("$@")
    for i in "${arr[@]}"; do
        [[ "$i" == "$item" ]] && return 0
    done
    return 1
}

# === Simulation loop ===
for line in "${PKGLIST[@]}"; do
    pkgname="${line%%;*}"
    essential="${line##*;}"

    # === Mark essential packages ===
    if [[ "$essential" == "yes" ]]; then
        echo "$pkgname : skip [ESSENTIAL]" >> "$SUMMARY"
        continue
    fi

    # === Mark whitelisted packages ===
    if in_array "$pkgname" "${WHITELIST[@]}"; then
        echo "$pkgname : skip [WHITELIST]" >> "$SUMMARY"
        continue
    fi

    # === Mark critical packages ===
    if [[ -n "${CRITICAL_PKGS[$pkgname]+x}" ]]; then
        echo "$pkgname : skip [critical:${CRITICAL_PKGS[$pkgname]^^}]" >> "$SUMMARY"
        continue
    fi

    echo "Simulating purge for: $pkgname ..."

    # === Run purge simulation and save log ===
    LOGFILE="$LOGDIR/$pkgname.log"
    sudo apt-get -s purge "$pkgname" > "$LOGFILE" 2>&1 || true

    # === Check if whitelist packages would be removed ===
    AFFECTED=$(awk '/^Purg/ {print $2}' "$LOGFILE")
    SKIP_FLAG=0
    for w in "${WHITELIST[@]}"; do
        if echo "$AFFECTED" | grep -qx "$w"; then
            echo "  Skipping $pkgname because it would remove whitelisted package $w"
            SKIP_FLAG=1
            break
        fi
    done

    if [[ $SKIP_FLAG -eq 1 ]]; then
        continue
    fi

    # === Count dependent packages ===
    REMOVED_COUNT=$(echo "$AFFECTED" | wc -l)
    echo "$pkgname : $REMOVED_COUNT dependent packages" >> "$SUMMARY"

    # === Optional: show affected packages ===
    if [[ $REMOVED_COUNT -gt 0 ]]; then
        echo "  Packages affected: $(echo "$AFFECTED" | tr '\n' ', ' | sed 's/, $//')"
    fi

    ((TOTAL_PACKAGES+=1))
done

# === Final totals ===
{
    echo ""
    echo "Total installed packages: $TOTAL_PKGS"
    echo "Total packages simulated: $TOTAL_PACKAGES"
    echo "Total skipped (critical/whitelist): $((TOTAL_PKGS - TOTAL_PACKAGES))"
} >> "$SUMMARY"

echo "Simulation complete. Check $LOGDIR/ and $SUMMARY"
