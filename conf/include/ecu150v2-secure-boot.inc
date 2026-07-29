# ═════════════════════════════════════════════════════════════════════
# ECU150v2 HABv4 Secure Boot — single source of truth.
# Toggle by setting SECURE_BOOT_ENABLED = "1" in local.conf — one line,
# when the build host follows the key-dir convention below (mirrors the
# existing RAUC_KEYS_DIR pattern):
#   ~/.config/cst                  symlink -> actual CST install (tool only,
#                                  read-only, shareable across products)
#   ~/.config/hab-keys-ecu150v2/   per-product keys/ + crts/ + csf_hab4.cfg
#                                  (secret; NEVER inside the CST dir)
# Override SIG_TOOL_PATH / SIG_DATA_PATH only when deviating.
#
# Mechanism comes from meta-nxp-security-reference-design/meta-secure-boot.
# CAUTION: that layer's layer.conf force-appends all three signing
# MACHINE_FEATURES globally. Default-off therefore requires actively
# REMOVING them here (:remove always beats :append, parse order irrelevant).
# ═════════════════════════════════════════════════════════════════════

# One knob signs the whole chain (bootloader + kernel). There is no
# kernel sub-toggle on purpose: NXP U-Boot's booti authenticates the
# kernel automatically whenever CONFIG_IMX_HAB is set.
SECURE_BOOT_ENABLED ?= "0"

# Tool vs keys are deliberately two variables: the tool is public,
# shareable and replaceable; the keys are secret, per-product and
# irreplaceable. NXP's silent fallback (SIG_DATA_PATH -> SIG_TOOL_PATH)
# is exactly what these defaults prevent.
SIG_TOOL_PATH ?= "${HOME}/.config/cst"
SIG_DATA_PATH ?= "${HOME}/.config/hab-keys-ecu150v2"

# Neutralise the layer.conf force-append unless explicitly enabled.
# u-boot-imx-signature is never used on 8M (imx-boot-signature covers it).
MACHINE_FEATURES:remove = "u-boot-imx-signature"
MACHINE_FEATURES:remove = "${@'' if d.getVar('SECURE_BOOT_ENABLED') == '1' else 'imx-boot-signature linux-imx-signature'}"

# Fail fast at parse time with actionable messages. NXP's own checks come
# too late (mid-build).
#
# Deliberately NOT checked here: the presence of ${SIG_DATA_PATH}/csf_hab4.cfg.
# imx-boot-signature.bb accepts either csf_hab4.cfg or csf_hab4_pkcs11.cfg and
# silently falls back to its own csf_hab4.cfg.sample when neither exists
python () {
    if d.getVar('SECURE_BOOT_ENABLED') != '1':
        return
    sig_tool = d.getVar('SIG_TOOL_PATH') or ''
    sig_data = d.getVar('SIG_DATA_PATH') or ''
    if not os.path.isdir(sig_tool):
        bb.fatal("SIG_TOOL_PATH (%s) not found — install NXP CST and "
                 "symlink it: ln -s <cst-x.x.x> ~/.config/cst "
                 "(or override SIG_TOOL_PATH in local.conf)" % sig_tool)
    if not os.path.isdir(sig_data):
        bb.fatal("SIG_DATA_PATH (%s) not found — create the per-product "
                 "key dir (guide Step 1) or override SIG_DATA_PATH" % sig_data)
}