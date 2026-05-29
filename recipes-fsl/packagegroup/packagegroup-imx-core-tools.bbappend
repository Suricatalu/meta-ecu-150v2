# Remove udev-extraconf when RAUC A/B is enabled.
#
# udev-extraconf ships /lib/udev/mount.sh and automount.rules, which
# auto-mount every labeled ext4 partition under /run/media/<label>-<dev>.
# With RAUC A/B, the inactive rootfs slot MUST remain unmounted so that
# `rauc install` can write to it safely.  /data is mounted explicitly by
# rauc-setup-env.service, so the auto-mounter is neither needed nor wanted
# when RAUC is active.
#
# When RAUC_ENABLED != "1" (single-rootfs build), udev-extraconf is kept
# so that removable media (USB drives, etc.) still auto-mounts normally.
RDEPENDS:${PN}:remove = "${@'udev-extraconf' if d.getVar('RAUC_ENABLED') == '1' else ''}"
