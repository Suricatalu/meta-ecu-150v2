FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Base ECU-150v2 board port — always applied.
SRC_URI:append:ecu150v2 = " \
            file://0001-imx8mp_evk-Port-ECU-150v2-board-to-uBoot2025.patch \
            file://0002-imx8mp_evk-Add-ECU-150v2-LPDDR4-timing.patch \
            file://0003-imx8mp_evk-Add-Boot-Policy.patch \
            "

# RAUC A/B boot policy is compiled into U-Boot. Apply it only when RAUC is
# enabled (RAUC_ENABLED = "1" in local.conf, default "0" in ecu150v2-rauc.inc).
SRC_URI:append:ecu150v2 = "${@' file://0004-imx8mp_evk-Enable-RAUC-A-B-bootcmd.patch' if d.getVar('RAUC_ENABLED') == '1' else ''}"

