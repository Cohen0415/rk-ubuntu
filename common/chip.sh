#!/bin/bash

UBUNTU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHIPS_DIR="$UBUNTU_DIR/chips"
COMMON_OVERLAY_DIR="$UBUNTU_DIR/common/overlay"

rk_ubuntu_list_chips()
{
    find "$CHIPS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

rk_ubuntu_select_chip()
{
    local chip_list chip_count index choice

    if [ -n "$RK_UBUNTU_CHIP" ]; then
        return
    fi

    mapfile -t chip_list < <(rk_ubuntu_list_chips)
    chip_count="${#chip_list[@]}"

    if [ "$chip_count" -eq 0 ]; then
        echo "No chip configs found in $CHIPS_DIR" >&2
        exit 1
    fi

    if [ "$chip_count" -eq 1 ] || [ ! -t 0 ]; then
        RK_UBUNTU_CHIP="${chip_list[0]}"
        export RK_UBUNTU_CHIP
        return
    fi

    echo "Select Rockchip Ubuntu target:"
    for index in "${!chip_list[@]}"; do
        printf '  %d) %s\n' "$((index + 1))" "${chip_list[$index]}"
    done

    while true; do
        read -r -p "Chip [1-$chip_count]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] &&
           [ "$choice" -ge 1 ] &&
           [ "$choice" -le "$chip_count" ]; then
            RK_UBUNTU_CHIP="${chip_list[$((choice - 1))]}"
            export RK_UBUNTU_CHIP
            return
        fi
        echo "Invalid selection: $choice"
    done
}

rk_ubuntu_load_chip()
{
    rk_ubuntu_select_chip

    RK_UBUNTU_CHIP_DIR="$CHIPS_DIR/$RK_UBUNTU_CHIP"
    RK_UBUNTU_CHIP_CONFIG="$RK_UBUNTU_CHIP_DIR/chip.conf"

    if [ ! -f "$RK_UBUNTU_CHIP_CONFIG" ]; then
        echo "Missing chip config: $RK_UBUNTU_CHIP_CONFIG" >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    . "$RK_UBUNTU_CHIP_CONFIG"

    RK_UBUNTU_HOSTNAME="${RK_UBUNTU_HOSTNAME:-$RK_UBUNTU_CHIP-ubuntu}"
    RK_UBUNTU_PACKAGES_DIR="${RK_UBUNTU_PACKAGES_DIR:-$RK_UBUNTU_CHIP_DIR/packages}"
    RK_UBUNTU_OVERLAY_DIR="${RK_UBUNTU_OVERLAY_DIR:-$RK_UBUNTU_CHIP_DIR/overlay}"
    RK_UBUNTU_COMMON_OVERLAY_DIR="${RK_UBUNTU_COMMON_OVERLAY_DIR:-$COMMON_OVERLAY_DIR}"
    RK_UBUNTU_OVERLAY_FIRMWARE_DIR="${RK_UBUNTU_OVERLAY_FIRMWARE_DIR:-$RK_UBUNTU_CHIP_DIR/overlay-firmware}"
    RK_UBUNTU_OVERLAY_DEBUG_DIR="${RK_UBUNTU_OVERLAY_DEBUG_DIR:-$RK_UBUNTU_CHIP_DIR/overlay-debug}"

    export RK_UBUNTU_CHIP RK_UBUNTU_CHIP_DIR RK_UBUNTU_HOSTNAME
    export RK_UBUNTU_PACKAGES_DIR RK_UBUNTU_COMMON_OVERLAY_DIR RK_UBUNTU_OVERLAY_DIR
    export RK_UBUNTU_OVERLAY_FIRMWARE_DIR RK_UBUNTU_OVERLAY_DEBUG_DIR
    export RK_UBUNTU_RKAIQ_DEB RK_UBUNTU_GPU_DEBS

    echo -e "\033[36m Ubuntu chip: $RK_UBUNTU_CHIP \033[0m"
}
