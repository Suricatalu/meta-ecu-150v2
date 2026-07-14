# ═════════════════════════════════════════════════════════════════════
# ECU150v2 RAUC OTA — single source of truth.
# Toggle by setting RAUC_ENABLED = "1" in local.conf.
# ═════════════════════════════════════════════════════════════════════

RAUC_ENABLED ?= "0"

# Compatibility string — referenced by:
#   - recipes-core/rauc/files/rauc-setup-env.sh (via @RAUC_SYSTEM_COMPATIBLE@ placeholder)
#   - recipes-core/bundles/update-bundle.bb     (RAUC_BUNDLE_COMPATIBLE)
RAUC_SYSTEM_COMPATIBLE ?= "ecu150v2"

# ── Adaptive update toggle ────────────────────────────────────────────
# Enable adaptive delta update (block-hash-index) + streaming.
RAUC_ADAPTIVE_ENABLED ?= "0"

# Bundle format is DERIVED from the adaptive toggle:
#   adaptive on  -> "verity" (mandatory: plain cannot be verified per-block)
#   adaptive off -> "plain"  (unchanged legacy behaviour)
RAUC_BUNDLE_FORMAT ?= "${@'verity' if d.getVar('RAUC_ADAPTIVE_ENABLED') == '1' else 'plain'}"

# Poky's default IMAGE_ROOTFS_ALIGNMENT is "1" (KiB), which only guarantees
# 1024-byte alignment -- not 4096. Bump it to "4" (KiB) when adaptive is
# enabled so every generated image lands on a 4096-byte boundary.
IMAGE_ROOTFS_ALIGNMENT = "${@'4' if d.getVar('RAUC_ADAPTIVE_ENABLED') == '1' else '1'}"

# Only guard the RAUC_ENABLED prerequisite here.
python () {
    if d.getVar('RAUC_ADAPTIVE_ENABLED') == '1' and d.getVar('RAUC_ENABLED') != '1':
        bb.fatal("RAUC_ADAPTIVE_ENABLED=1 requires RAUC_ENABLED=1")
}

# Conditional integration — only when explicitly enabled.
DISTRO_FEATURES:append = "${@' rauc' if d.getVar('RAUC_ENABLED') == '1' else ''}"
IMAGE_INSTALL:append   = "${@' rauc libubootenv-bin' if d.getVar('RAUC_ENABLED') == '1' else ''}"

