FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:ecu150v2 = " \
            file://0001-Port-ECU-150v2-to-linux-imx-6.12-on-deviceTree.patch \
            file://0002-Drivers-code-created-and-modified.patch \
            file://0003-Upstream-driver-code-modifications.patch \
            "

# ECU-150v2 patches imx8mp-evk.dts heavily (camera/audio/LVDS nodes removed),
# which breaks every downstream NXP EVK overlay/variant DTB that #include's it.
# Drop those variants from the kernel DTB build set so they do not fail compile.
# (The same list also lives in conf/machine/ecu150v2.conf for clarity; we
# repeat it here so the dependency is local to the kernel recipe that owns
# the dts patches.)
KERNEL_DEVICETREE:remove:ecu150v2 = "${ECU150V2_REMOVED_EVK_DTBS}"



