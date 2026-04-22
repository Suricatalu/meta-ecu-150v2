# ECU-150v2: install a systemd drop-in so that Weston waits for
# /dev/dri/card0 to appear before starting.

FILESEXTRAPATHS:prepend := "${THISDIR}/weston:"

SRC_URI += "file://weston.service.d/wait-drm.conf"

do_install:append() {
    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        install -d ${D}${systemd_system_unitdir}/weston.service.d
        install -m 0644 ${UNPACKDIR}/weston.service.d/wait-drm.conf \
            ${D}${systemd_system_unitdir}/weston.service.d/wait-drm.conf
    fi
}

FILES:${PN} += "${systemd_system_unitdir}/weston.service.d/wait-drm.conf"
