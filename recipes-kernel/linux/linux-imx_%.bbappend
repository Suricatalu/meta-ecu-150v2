FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:ecu150v2 = " \
            file://0001-Port-ECU-150v2-to-linux-imx-6.12-on-deviceTree.patch \
            file://0002-Drivers-code-created-and-modified.patch \
            file://0003-Upstream-driver-code-modifications.patch \
            file://rauc.cfg \
            "

DELTA_KERNEL_DEFCONFIG:append:ecu150v2 = " rauc.cfg"

# ECU-150v2 patches imx8mp-evk.dts heavily (camera/audio/LVDS nodes removed),
# which breaks every downstream NXP EVK overlay/variant DTB that #include's it.
# Drop those variants from the kernel DTB build set so they do not fail compile.
# (The same list also lives in conf/machine/ecu150v2.conf for clarity; we
# repeat it here so the dependency is local to the kernel recipe that owns
# the dts patches.)
KERNEL_DEVICETREE:remove:ecu150v2 = "${ECU150V2_REMOVED_EVK_DTBS}"

# The following patches are eventpoll-related patches from the Linux kernel mailing list that 
# fix a use-after-free bug in the ep_remove() function. They are applied in order to ensure that
# the eventpoll implementation is safe and does not lead to memory corruption or crashes.
SRC_URI:append:ecu150v2 = " \
            file://badepoll/0001-eventpoll-use-hlist_is_singular_node-in-__ep_remove.patch \
            file://badepoll/0002-eventpoll-split-__ep_remove.patch \
            file://badepoll/0003-eventpoll-kill-__ep_remove.patch \
            file://badepoll/0004-eventpoll-drop-vestigial-__-prefix-from-ep_remove.patch \
            file://badepoll/0005-eventpoll-rename-ep_remove_safe-back-to-ep_remove.patch \
            file://badepoll/0006-eventpoll-move-epi_fget-up.patch \
            file://badepoll/0007-eventpoll-fix-ep_remove-struct-eventpoll-struct-file-UAF.patch \
            "



