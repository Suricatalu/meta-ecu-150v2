FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Base ECU-150v2 board port — always applied.
SRC_URI:append:ecu150v2 = " \
            file://0001-imx8mp_evk-Port-ECU-150v2-board-to-uBoot2025.patch \
            file://0002-imx8mp_evk-Add-ECU-150v2-LPDDR4-timing.patch \
            file://0003-imx8mp_evk-Add-Ubuntu-boot-policy.patch \
            "

# HAB support: hab_status / hab_auth_img commands in U-Boot.
SRC_URI:append:ecu150v2 = "${@' file://hab.cfg' if d.getVar('SECURE_BOOT_ENABLED') == '1' else ''}"