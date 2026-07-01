IMAGE_INSTALL:append = " kernel-devicetree"
IMAGE_FSTYPES:append = " ext4"

# ---------------------------------------------------------------------------
# Optionally make the rootfs /boot/Image the *initramfs-bundled* kernel.
#
# Controlled by OVERLAY_INITRAMFS_ROOT (default "0", see ecu150v2-overlay.inc);
# enable in local.conf:
#     OVERLAY_INITRAMFS_ROOT = "1"
#
# Fix: during image assembly, overwrite the rootfs /boot/Image with the
# bundled (initramfs) kernel from the deploy dir.、
#
# The whole block is a no-op unless OVERLAY_INITRAMFS_ROOT == "1", so leaving
# this bbappend in place with the toggle off keeps the normal bare kernel.
# ---------------------------------------------------------------------------

install_initramfs_bundled_kernel() {
    bundled="${DEPLOY_DIR_IMAGE}/Image-initramfs-${MACHINE}.bin"
    if [ ! -e "${bundled}" ]; then
        bbfatal "OVERLAY_INITRAMFS_ROOT=1 but bundled kernel '${bundled}' " \
                "not found. Is INITRAMFS_IMAGE_BUNDLE = \"1\" set?"
    fi

    # Drop the bare-kernel symlink and its target, then drop the bundled kernel
    # in as the real /boot/Image that U-Boot will ext4load + booti.
    if [ -L "${IMAGE_ROOTFS}/boot/Image" ]; then
        # Remove the versioned bare kernel the symlink points at (saves space
        # per RAUC slot); ignore failure if the name ever changes.
        target="$(readlink "${IMAGE_ROOTFS}/boot/Image")"
        rm -f "${IMAGE_ROOTFS}/boot/${target}" || true
    fi
    rm -f "${IMAGE_ROOTFS}/boot/Image"
    install -m 0644 "${bundled}" "${IMAGE_ROOTFS}/boot/Image"
}

# Only wire up the override + dependency when the toggle is on.
python () {
    if d.getVar('OVERLAY_INITRAMFS_ROOT') == '1':
        d.appendVarFlag('do_rootfs', 'depends', ' virtual/kernel:do_deploy')
        d.appendVar('ROOTFS_POSTPROCESS_COMMAND',
                    ' install_initramfs_bundled_kernel;')
}