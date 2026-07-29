#!/bin/sh
# ecu150v2-setup.sh - add this product's layers to an existing build directory.
#
# Run AFTER sourcing imx-setup-release.sh:
#     sources/meta-ecu150v2/scripts/ecu150v2-setup.sh
#
# Idempotent: each layer is added only when absent, so re-running is harmless.
#
# WHY THIS IS A REPEATABLE STEP, NOT A ONE-OFF:
#   imx-setup-release.sh restores conf/bblayers.conf from conf/bblayers.conf.org
#   on every re-run and then appends only NXP's own layer list. Anything added
#   by hand -- including meta-ecu150v2 itself -- is silently dropped. Re-run
#   this script after any re-run of imx-setup-release.sh.
#
# meta-secure-boot is REQUIRED, not optional: meta-ecu150v2 carries a
# linux-imx-signature bbappend, and a bbappend whose target recipe is absent
# makes bitbake fail outright (see docs/0068_add_secure_boot).

set -eu

BUILD_DIR="${1:-${BUILDDIR:-$PWD}}"
BBLAYERS_CONF="${BUILD_DIR}/conf/bblayers.conf"

if [ ! -f "${BBLAYERS_CONF}" ]; then
    echo "ecu150v2-setup: not a build directory: ${BUILD_DIR}" >&2
    echo "ecu150v2-setup: source imx-setup-release.sh first, or pass the build dir" >&2
    exit 1
fi

# add_layer <subpath under sources/>
# Writes ${BSPDIR} (defined by bblayers.conf itself) rather than an absolute
# path, so the tree stays relocatable. Match on the trailing quote so that
# meta-rauc does not accidentally match meta-rauc-something, and skip
# commented-out lines.
add_layer() {
    if grep -v '^[[:space:]]*#' "${BBLAYERS_CONF}" | grep -q "/$1\""; then
        printf '  [have] %s\n' "$1"
    else
        printf '  [ add] %s\n' "$1"
        printf 'BBLAYERS += "${BSPDIR}/sources/%s"\n' "$1" >> "${BBLAYERS_CONF}"
    fi
}

echo "ecu150v2-setup: ${BBLAYERS_CONF}"

add_layer meta-ecu-150v2
add_layer meta-rauc
add_layer meta-nxp-security-reference-design/meta-secure-boot

echo "ecu150v2-setup: done"
