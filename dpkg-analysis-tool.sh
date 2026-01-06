#!/bin/bash
set -euo pipefail

# === Configuración ===
LOGDIR="./purge-sim"
WHITELIST_FILE="./whitelist.txt"
CRITICAL_FILE="./critical.txt"
mkdir -p "$LOGDIR"

# === Cargar whitelist ===
declare -a WHITELIST
if [[ -f "$WHITELIST_FILE" ]]; then
    mapfile -t WHITELIST < "$WHITELIST_FILE"
fi

# === Cargar critical packages (con categorías) ===
declare -A CRITICAL_PKGS
if [[ -f "$CRITICAL_FILE" ]]; then
    while IFS=: read -r pkg cat; do
        [[ -n "$pkg" ]] && CRITICAL_PKGS["$pkg"]="$cat"
    done < "$CRITICAL_FILE"
fi

# === Archivo de resumen ===
SUMMARY="$LOGDIR/summary.txt"
echo "Purge simulation summary" > "$SUMMARY"
echo "========================" >> "$SUMMARY"

# === Listado de Paquetes ===
# === Guardar en un array los nombres de paquetes + Essential ===
mapfile -t PKGLIST < <(dpkg-query -W -f='${Package};${Essential}\n')

# === Variables de totales ===
TOTAL_PKGS=$(dpkg-query -W -f='${Package}\n' | wc -l | awk '{print $1}')
TOTAL_PACKAGES=0
TOTAL_WHITELIST_AFFECTED=0

# === Función para verificar si un paquete está en el array ===
in_array() {
    local item="$1"
    shift
    local arr=("$@")
    for i in "${arr[@]}"; do
        [[ "$i" == "$item" ]] && return 0
    done
    return 1
}

# === Bucle de simulación ===
for line in "${PKGLIST[@]}"; do
    pkgname="${line%%;*}"
    essential="${line##*;}"

    # === Marcar esenciales ===
    if [[ "$essential" == "yes" ]]; then
        echo "$pkgname : skip [ESSENTIAL]" >> "$SUMMARY"
        continue
    fi

    # === Marcar whitelist ===
    if in_array "$pkgname" "${WHITELIST[@]}"; then
        echo "$pkgname : skip [WHITELIST]" >> "$SUMMARY"
        continue
    fi

    # === Marcar críticos ===
    if [[ -n "${CRITICAL_PKGS[$pkgname]+x}" ]]; then
        echo "$pkgname : skip [critical:${CRITICAL_PKGS[$pkgname]^^}]" >> "$SUMMARY"
        continue
    fi

    echo "Simulating purge for: $pkgname ..."

    # === Primero simular y guardar log ===
    LOGFILE="$LOGDIR/$pkgname.log"
    sudo apt-get -s purge "$pkgname" > "$LOGFILE" 2>&1 || true

    # === Verificar si se eliminaría algún paquete de la whitelist ===
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

    # === Contar dependientes ===
    REMOVED_COUNT=$(echo "$AFFECTED" | wc -l)
    echo "$pkgname : $REMOVED_COUNT dependent packages" >> "$SUMMARY"

    # === Opcional: mostrar paquetes afectados ===
    if [[ $REMOVED_COUNT -gt 0 ]]; then
        echo "  Packages affected: $(echo "$AFFECTED" | tr '\n' ', ' | sed 's/, $//')"
    fi

    ((TOTAL_PACKAGES+=1))
done

# === Totales al final ===
{
    echo ""
    echo "Total installed packages: $TOTAL_PKGS"
    echo "Total packages simulated: $TOTAL_PACKAGES"
    echo "Total skipped (critical/whitelist): $((TOTAL_PKGS - TOTAL_PACKAGES))"
} >> "$SUMMARY"

echo "Simulation complete. Check $LOGDIR/ and $SUMMARY"
