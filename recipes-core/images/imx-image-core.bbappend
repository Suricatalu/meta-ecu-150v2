IMAGE_INSTALL:append = " kernel-devicetree"
IMAGE_FSTYPES:append = " ext4"

# ---------------------------------------------------------------------------
# Put the right kernel into the rootfs /boot/Image.
#
# There is no separate boot partition on ECU-150v2: U-Boot ext4loads the
# kernel straight out of the rootfs (/boot/Image, see 0003-Boot-Policy), so
# whatever lands there is what boots. By default that is the kernel
# package's own Image, which is UNSIGNED and does not contain the overlay
# initramfs.
#
# Two independent toggles decide what has to replace it:
#
#   SECURE_BOOT   OVERLAY   /boot/Image must be
#   -----------   -------   ------------------------------------------------
#        0           0      untouched (kernel package's Image is correct)
#        0           1      Image-initramfs-${MACHINE}.bin         unsigned bundled
#        1           0      signed-Image-${MACHINE}.bin            signed plain
#        1           1      signed-Image-initramfs-${MACHINE}.bin  signed bundled
#
# WHY BOTH SIGNED CASES MATTER: with SECURE_BOOT_ENABLED = "1" the bootloader
# is built with CONFIG_IMX_HAB=y and NXP's booti authenticates the kernel on
# every boot -- open devices included. An unsigned /boot/Image does not boot
# at all, whether or not the overlay feature is in play. Background:
# docs/0068_add_secure_boot/issue_overlayfs_secure_boot_compatibale.md
#
# The whole block is a no-op when both toggles are off, so leaving this
# bbappend in place costs a plain build nothing.
# ---------------------------------------------------------------------------

install_rootfs_boot_kernel() {
    if [ "${SECURE_BOOT_ENABLED}" = "1" ]; then
        if [ "${OVERLAY_INITRAMFS_ROOT}" = "1" ]; then
            src="${DEPLOY_DIR_IMAGE}/signed-Image-initramfs-${MACHINE}.bin"
            hint="produced by the linux-imx-signature bbappend in meta-ecu150v2"
        else
            src="${DEPLOY_DIR_IMAGE}/signed-Image-${MACHINE}.bin"
            hint="produced by meta-secure-boot's linux-imx-signature"
        fi
    elif [ "${OVERLAY_INITRAMFS_ROOT}" = "1" ]; then
        src="${DEPLOY_DIR_IMAGE}/Image-initramfs-${MACHINE}.bin"
        hint="is INITRAMFS_IMAGE_BUNDLE = \"1\" set?"
    else
        # Neither toggle: the kernel package's own /boot/Image is correct.
        return
    fi

    if [ ! -e "${src}" ]; then
        bbfatal "cannot install /boot/Image: '${src}' not found (${hint})"
    fi

    # Drop the kernel package's symlink and the versioned file it points at
    # (saves that space in every RAUC slot), then install the real file.
    if [ -L "${IMAGE_ROOTFS}/boot/Image" ]; then
        target="$(readlink "${IMAGE_ROOTFS}/boot/Image")"
        rm -f "${IMAGE_ROOTFS}/boot/${target}" || true
    fi
    rm -f "${IMAGE_ROOTFS}/boot/Image"
    install -m 0644 "${src}" "${IMAGE_ROOTFS}/boot/Image"

    bbnote "installed /boot/Image from ${src}"
}

python () {
    secure = d.getVar('SECURE_BOOT_ENABLED') == '1'
    overlay = d.getVar('OVERLAY_INITRAMFS_ROOT') == '1'

    # Neither toggle: the kernel package's own /boot/Image is already correct.
    if not (secure or overlay):
        return

    # The unsigned bundled kernel is deployed by the kernel recipe itself.
    if overlay:
        d.appendVarFlag('do_rootfs', 'depends', ' virtual/kernel:do_deploy')

    # Signed artifacts come from linux-imx-signature (the plain one from the
    # NXP recipe, the bundled one from our bbappend). Without this dependency
    # do_rootfs races the signing and bbfatal's on a missing file.
    if secure:
        d.appendVarFlag('do_rootfs', 'depends', ' linux-imx-signature:do_deploy')

    d.appendVar('ROOTFS_POSTPROCESS_COMMAND', ' install_rootfs_boot_kernel;')
}

# Secure boot: also make image generation depend on imx-boot-signature so the
# bootloader's imx-boot symlink / imx-boot.tagged already point at signed-*
# by the time wic assembles the image (the .wks rawcopy reads imx-boot.tagged,
# not the imx-boot symlink -- see plan section 2.2).
EXTRA_IMAGEDEPENDS:append = "${@' imx-boot-signature' if d.getVar('SECURE_BOOT_ENABLED') == '1' else ''}"