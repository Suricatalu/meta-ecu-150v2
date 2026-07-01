SUMMARY = "Overlay-root init script for initramfs"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

SRC_URI = "file://overlay-init"

do_install() {
    # Install as /init - the entry point the kernel executes in initramfs
    install -d ${D}
    install -m 0755 ${UNPACKDIR}/overlay-init ${D}/init

    # /dev/console must exist in the cpio so the kernel can attach
    # stdout/stderr of /init before devtmpfs is mounted
    install -d ${D}/dev
    mknod -m 622 ${D}/dev/console c 5 1

    # Mountpoints used by the script (the rest are created at runtime
    # with mkdir -p under /run/)
    install -d ${D}/proc ${D}/sys ${D}/run
}

inherit allarch

FILES:${PN} = "/init /dev /proc /sys /run"
