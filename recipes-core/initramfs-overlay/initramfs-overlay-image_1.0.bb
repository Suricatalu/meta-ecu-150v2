SUMMARY = "Minimal initramfs image with overlay-root support"
LICENSE = "MIT"

# busybox provides sh, mount, switch_root, awk, grep, findfs, modprobe...
# devtmpfs handles device nodes - no mdev needed.
PACKAGE_INSTALL = " \
    initramfs-overlay \
    busybox \
"

# Only needed if CONFIG_OVERLAY_FS=m (module) - the running ECU-150v2 kernel
# currently ships overlay as a module, so the .ko must live in the initramfs.
PACKAGE_INSTALL += "kmod kernel-module-overlay"

PACKAGE_EXCLUDE = "kernel-image-*"

IMAGE_FEATURES = ""
IMAGE_LINGUAS  = ""
IMAGE_FSTYPES  = "${INITRAMFS_FSTYPES}"
IMAGE_NAME_SUFFIX ?= ""

inherit core-image

IMAGE_ROOTFS_SIZE        = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
