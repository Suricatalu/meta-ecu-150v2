# Also sign the initramfs-bundled kernel: meta-secure-boot's own
# do_sign_kernel_image hardcodes Image-${MACHINE}.bin and never touches it.
# Background: docs/0068_add_secure_boot/issue_overlayfs_secure_boot_compatibale.md
#
# REQUIRES meta-secure-boot in BBLAYERS. A bbappend whose target recipe is
# absent makes bitbake fail outright, so this is a hard prerequisite -- add
# the layer with scripts/ecu150v2-setup.sh before building.
#
# Everything else needed is already set by the recipe: sigtool/xhab/deploy,
# DEPENDS, do_compile[deptask], SIG_CFGFILE, BOOT_TOOLS and the default S.
#
# BOTH toggles are checked explicitly below. SECURE_BOOT_ENABLED is in fact
# already handled upstream -- the recipe's own REQUIRED_MACHINE_FEATURES =
# "linux-imx-signature" gets removed by ecu150v2-secure-boot.inc when the
# toggle is off, so features_check skips the entire recipe and nothing here
# runs -- but repeating it makes this file readable on its own and drops a
# silent dependency on that other file staying correct.
#
# Gate with if/fi ONLY. Two things that look equivalent are not:
#   * bb.parse.SkipRecipe -- skips the ENTIRE recipe, silently taking NXP's
#     plain-kernel signing with it.
#   * "|| return" -- a return inside an :append body skips every other
#     :append that lands after it, including NXP's own do_deploy:append:hab4.

INITRAMFS_KERNEL = "${KERNEL_IMAGETYPE}-initramfs-${MACHINE}.bin"

do_compile:append() {
    if [ "${SECURE_BOOT_ENABLED}" = "1" ] && [ "${OVERLAY_INITRAMFS_ROOT}" = "1" ]; then
        src="${DEPLOY_DIR_IMAGE}/${INITRAMFS_KERNEL}"
        if [ ! -e "${src}" ]; then
            bbfatal "${INITRAMFS_KERNEL} not found; is INITRAMFS_IMAGE_BUNDLE = \"1\"?"
        fi

        # Pad straight out of the deploy dir to the memory footprint recorded
        # in the arm64 header (image_size at offset 0x10), so the IVT lands
        # exactly where HAB looks for it. That field already covers the
        # initramfs: the cpio is linked into .init.ramfs by
        # CONFIG_INITRAMFS_SOURCE.
        pad="$(od -An -j 16 -N 4 -i ${src} | tr -d ' ')"
        objcopy -I binary -O binary --pad-to "${pad}" --gap-fill=0x00 "${src}" "${S}/ik"

        # The IVT carries ABSOLUTE addresses and is therefore bound to
        # whatever address U-Boot loads this kernel to; it must equal the
        # boot policy's BOOT_KERNEL_ADDR or validate_ivt() rejects the image.
        # Append the 32 bytes in place: header, entry, rsv1, dcd, boot_data,
        # self, csf, rsv2.
        load="$(printf '%u' $(sed -n 's/CONFIG_SYS_LOAD_ADDR=//p' ${DEPLOY_DIR_IMAGE}/${BOOT_TOOLS}/u-boot-imx.config))"
        pad_dec="$(printf '%u' ${pad})"
        ivt="$(expr ${load} + ${pad_dec})"
        csf="$(expr ${ivt} + 32)"
        bbnote "signing ${INITRAMFS_KERNEL}: load=${load} pad=${pad_dec} ivt=${ivt}"
        python3 -c "import struct; open('${S}/ik', 'ab').write(struct.pack('<8I', 0x432000D1, ${load}, 0, 0, 0, ${ivt}, ${csf}, 0))"

        # sign.cfg was already staged by the recipe's own do_sign_kernel_image.
        SIG_TOOL_PATH="${SIG_TOOL_PATH}" SIG_DATA_PATH="${SIG_DATA_PATH}" \
            "${DEPLOY_DIR_IMAGE}/${BOOT_TOOLS}/imx_signer" \
            -d -i "${S}/ik" -c "${S}/${SIG_CFGFILE}"

        if [ ! -e "${S}/signed-ik" ]; then
            bbfatal "signing ${INITRAMFS_KERNEL} failed"
        fi
    fi
}

do_deploy:append() {
    if [ "${SECURE_BOOT_ENABLED}" = "1" ] && [ "${OVERLAY_INITRAMFS_ROOT}" = "1" ]; then
        install -m 0644 "${S}/signed-ik" \
                        "${DEPLOY_DIR_IMAGE}/signed-${INITRAMFS_KERNEL}"
    fi
}
