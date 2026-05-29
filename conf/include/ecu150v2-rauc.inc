# ═════════════════════════════════════════════════════════════════════
# ECU150v2 RAUC OTA — single source of truth.
# Toggle by setting RAUC_ENABLED = "1" in local.conf.
# ═════════════════════════════════════════════════════════════════════

RAUC_ENABLED ?= "0"

# Compatibility string — referenced by:
#   - recipes-core/rauc/files/rauc-setup-env.sh (via @RAUC_SYSTEM_COMPATIBLE@ placeholder)
#   - recipes-core/bundles/update-bundle.bb     (RAUC_BUNDLE_COMPATIBLE)
RAUC_SYSTEM_COMPATIBLE ?= "ecu150v2"

# Bundle format default; bundle recipe may override per-bundle.
RAUC_BUNDLE_FORMAT ?= "plain"

# Conditional integration — only when explicitly enabled.
DISTRO_FEATURES:append = "${@' rauc' if d.getVar('RAUC_ENABLED') == '1' else ''}"
IMAGE_INSTALL:append   = "${@' rauc libubootenv-bin' if d.getVar('RAUC_ENABLED') == '1' else ''}"

