FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:ecu150v2 = " \
            file://0001-imx8mp_evk-Port-ECU-150v2-board-to-uBoot2025.patch \
            file://0002-imx8mp_evk-Add-ECU-150v2-LPDDR4-timing.patch \
            "

