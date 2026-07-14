python () {
    if d.getVar('RAUC_ENABLED') != '1':
        raise bb.parse.SkipRecipe("RAUC is disabled (RAUC_ENABLED != '1')")
}

# ca.cert.pem handling — follows upstream meta-rauc/scripts/README step 1:
#   The base rauc-conf.bb already declares
#     RAUC_KEYRING_FILE ??= "ca.cert.pem"
#     RAUC_KEYRING_URI  ??= "file://${RAUC_KEYRING_FILE}"
#     SRC_URI += "${RAUC_KEYRING_URI}"
#   and installs the file to ${sysconfdir}/rauc/ in do_install.
#   FILESEXTRAPATHS:prepend below makes BitBake's file:// fetcher pick our
#   layer's files/ca.cert.pem FIRST, transparently overriding meta-rauc's
#   example CA. So do NOT re-add `file://ca.cert.pem` to SRC_URI here and
#   do NOT install it again in do_install — both are already handled by the
#   base recipe; duplicating them only adds noise / duplicate-URI warnings.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://rauc-setup-env.sh \
    file://rauc-setup-env.service \
"

inherit systemd
SYSTEMD_SERVICE:${PN}    = "rauc-setup-env.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/rauc-setup-env.sh ${D}${bindir}/rauc-setup-env.sh

    # Replace @RAUC_SYSTEM_COMPATIBLE@ placeholder with the value from ecu150v2-rauc.inc
    sed -i "s/@RAUC_SYSTEM_COMPATIBLE@/${RAUC_SYSTEM_COMPATIBLE}/g" \
        ${D}${bindir}/rauc-setup-env.sh
    
    sed -i "s/@RAUC_BUNDLE_FORMATS@/${RAUC_BUNDLE_FORMAT}/g" \
        ${D}${bindir}/rauc-setup-env.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/rauc-setup-env.service \
        ${D}${systemd_system_unitdir}/rauc-setup-env.service

    install -d ${D}${sysconfdir}/rauc
    
    # Overwrite the example system.conf with a placeholder; the real content
    # is generated at boot by rauc-setup-env.service.
    echo "# Placeholder - generated at boot by rauc-setup-env.service" \
        > ${D}${sysconfdir}/rauc/system.conf

    install -d ${D}/var/lib/rauc
    install -d ${D}/data
}

FILES:${PN} += " \
    ${bindir}/rauc-setup-env.sh \
    ${systemd_system_unitdir}/rauc-setup-env.service \
    ${sysconfdir}/rauc/system.conf \
    ${sysconfdir}/rauc/ca.cert.pem \
    /var/lib/rauc \
    /data \
"

RDEPENDS:${PN} += "bash"