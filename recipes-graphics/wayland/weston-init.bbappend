# ECU-150v2: make Weston tolerate an unconnected HDMI at boot.
#
# Instead of shipping a full weston.ini override (which would have to mirror
# everything meta-freescale / meta-imx-bsp already provide), we just sed in
# the one extra key we need under [core]. This coexists cleanly with the
# other bbappends that also inject keys (use-g2d, repaint-window, ...).

do_install:append() {
    if [ -f "${D}${sysconfdir}/xdg/weston/weston.ini" ]; then
        # Insert right after the [core] header.
        sed -i -e "/^\[core\]/a require-outputs=none" \
            ${D}${sysconfdir}/xdg/weston/weston.ini
    fi
}
