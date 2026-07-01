# ═════════════════════════════════════════════════════════════════════
# ECU150v2 overlay-root via initramfs — single source of truth.
# Master toggle (set in local.conf): OVERLAY_INITRAMFS_ROOT = "1"
# ═════════════════════════════════════════════════════════════════════

# Master switch. Default off so nothing changes unless explicitly enabled.
# Use ?= (not ??=) to match RAUC_ENABLED's convention; local.conf's = wins.
OVERLAY_INITRAMFS_ROOT ?= "0"

# initramfs that provides /init (overlay-init). Names our image recipe:
#   recipes-core/initramfs-overlay/initramfs-overlay-image_1.0.bb
INITRAMFS_IMAGE ?= "initramfs-overlay-image"

# Bundle the initramfs into the kernel Image. Defaults to ON when the master
# toggle is on, but ?= lets local.conf override it independently — e.g. produce
# a bundled kernel for MANUAL flashing without baking it into the rootfs:
#     OVERLAY_INITRAMFS_ROOT = "0"
#     INITRAMFS_IMAGE_BUNDLE = "1"
INITRAMFS_IMAGE_BUNDLE ?= "${@'1' if d.getVar('OVERLAY_INITRAMFS_ROOT') == '1' else '0'}"