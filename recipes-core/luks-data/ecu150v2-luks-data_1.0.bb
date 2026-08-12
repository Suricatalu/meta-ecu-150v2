SUMMARY = "Unlock the encrypted /data partition (and provision it on demand)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    file://ecu150v2-luks-data.sh \
    file://ecu150v2-luks-data.service \
    file://rauc-setup-env.service.d/10-luks-data.conf \
"

inherit systemd
SYSTEMD_SERVICE:${PN}     = "ecu150v2-luks-data.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = "bash cryptsetup e2fsprogs-mke2fs util-linux coreutils"
RDEPENDS:${PN} += "${@'systemd-crypt tpm2-tools' \
    if d.getVar('LUKS_DATA_KEY_MODE') == 'tpm' else ''}"

# Install the RAUC ordering drop-in only when RAUC keeps its state on the
# encrypted mountpoint. Consumer declares the dependency, not the provider.
LUKS_INSTALL_RAUC_DROPIN = "${@'1' if d.getVar('RAUC_ENABLED') == '1' \
    and d.getVar('LUKS_DATA_MOUNT') == '/data' else '0'}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/ecu150v2-luks-data.sh \
        ${D}${bindir}/ecu150v2-luks-data.sh

    sed -i -e "s|@LUKS_DATA_MAPPER@|${LUKS_DATA_MAPPER}|g" \
           -e "s|@LUKS_DATA_MOUNT@|${LUKS_DATA_MOUNT}|g" \
           -e "s|@LUKS_DATA_DEVICE@|${LUKS_DATA_DEVICE}|g" \
           -e "s|@LUKS_DATA_KEY_MODE@|${LUKS_DATA_KEY_MODE}|g" \
           -e "s|@LUKS_DATA_RECOVERY_KEY@|${LUKS_DATA_RECOVERY_KEY}|g" \
           -e "s|@LUKS_DATA_AUTO_PROVISION@|${LUKS_DATA_AUTO_PROVISION}|g" \
           -e "s|@LUKS_DATA_PBKDF_ITER@|${LUKS_DATA_PBKDF_ITER}|g" \
           -e "s|@LUKS_DATA_PBKDF_MEMORY@|${LUKS_DATA_PBKDF_MEMORY}|g" \
           -e "s|@LUKS_DATA_PBKDF_PARALLEL@|${LUKS_DATA_PBKDF_PARALLEL}|g" \
        ${D}${bindir}/ecu150v2-luks-data.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/ecu150v2-luks-data.service \
        ${D}${systemd_system_unitdir}/ecu150v2-luks-data.service

    if [ "${LUKS_INSTALL_RAUC_DROPIN}" = "1" ]; then
        install -d ${D}${systemd_system_unitdir}/rauc-setup-env.service.d
        install -m 0644 ${UNPACKDIR}/rauc-setup-env.service.d/10-luks-data.conf \
            ${D}${systemd_system_unitdir}/rauc-setup-env.service.d/10-luks-data.conf
    fi

    # Key comes from the build host, never from SRC_URI / version control.
    if [ "${LUKS_DATA_KEY_MODE}" = "keyfile" ]; then
        install -d -m 0700 ${D}${sysconfdir}/ecu150v2
        install -m 0400 "${LUKS_DATA_KEYFILE}" \
            ${D}${sysconfdir}/ecu150v2/data.key
    fi

    install -d ${D}${LUKS_DATA_MOUNT}
}

# do_install reads an absolute path outside the build tree; without this the
# sstate cache silently reuses the previously packaged key.
do_install[file-checksums] += "${@'%s:True' % d.getVar('LUKS_DATA_KEYFILE') \
    if d.getVar('LUKS_DATA_KEY_MODE') == 'keyfile' else ''}"

do_install[vardeps] += "LUKS_DATA_KEY_MODE LUKS_DATA_DEVICE LUKS_DATA_MAPPER \
    LUKS_DATA_MOUNT LUKS_DATA_RECOVERY_KEY LUKS_DATA_AUTO_PROVISION \
    LUKS_INSTALL_RAUC_DROPIN"

FILES:${PN} = " \
    ${bindir}/ecu150v2-luks-data.sh \
    ${systemd_system_unitdir}/ecu150v2-luks-data.service \
    ${systemd_system_unitdir}/rauc-setup-env.service.d \
    ${sysconfdir}/ecu150v2 \
    ${LUKS_DATA_MOUNT} \
"
