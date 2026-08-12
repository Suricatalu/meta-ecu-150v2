# ═══════════════════════════════════════════════════════════════════
# ECU150v2 /data LUKS encryption — single source of truth.
# Enable with LUKS_DATA_ENABLED = "1" in local.conf.
# ═══════════════════════════════════════════════════════════════════
LUKS_DATA_ENABLED  ?= "0"

# "tpm"     -> unlocked by the on-board TPM, no key in the image
# "keyfile" -> unlocked by /etc/ecu150v2/data.key. NO SECURITY: the key sits in
#              the plaintext rootfs, shared by every unit built from this image.
LUKS_DATA_KEY_MODE ?= "tpm"

# Which partition to encrypt. DELIBERATELY HAS NO DEFAULT -- you must state it
# explicitly in local.conf. There is no safe default: the layout is produced by
# tools/flash/ecu150v2_flash.sh.
# Only "part:N" is supported; the base device (mmcblk0 eMMC / mmcblk1 SD) is
# resolved at runtime from /proc/cmdline root=.
LUKS_DATA_DEVICE   ?= ""
LUKS_DATA_MAPPER   ?= "data"
# When user set LUKS_DATA_DEVICE as "part:3" when also setting RAUC on.
# Plase set LUKS_DATA_MOUNT to "/data" explicitly in local.conf.
LUKS_DATA_MOUNT    ?= "/appdata"

# A recovery keyslot is a SECOND way into the volume, held by a human off-device.
# User can manually add a keyslot later on a per-unit basis with
#   ecu150v2-luks-data.sh --add-recovery-key
LUKS_DATA_RECOVERY_KEY ?= "0"

# Provision on first boot instead of waiting for an explicit --provision run.
LUKS_DATA_AUTO_PROVISION ?= "1"

# Argon2id cost for the recovery keyslot, pinned so it does not depend on
# whichever machine ran luksFormat. Re-measure with `cryptsetup benchmark`
# on the target before changing these three variable.
LUKS_DATA_PBKDF_ITER     ?= "4"
LUKS_DATA_PBKDF_MEMORY   ?= "1048576"
LUKS_DATA_PBKDF_PARALLEL ?= "4"

# keyfile-mode key location ON THE BUILD HOST.
# Create once:  head -c 32 /dev/urandom > ~/.config/luks-keys-ecu150v2/data.key
LUKS_DATA_KEYS_DIR ?= "${HOME}/.config/luks-keys-ecu150v2"
LUKS_DATA_KEYFILE  ?= "${LUKS_DATA_KEYS_DIR}/data.key"

# luksFormat only ever happens through an explicit
# `ecu150v2-luks-data.sh --provision` run. The boot path never formats.
IMAGE_INSTALL:append = "${@' cryptsetup ecu150v2-luks-data' \
    if d.getVar('LUKS_DATA_ENABLED') == '1' else ''}"

# NOT packagegroup-security-tpm2: it pulls in trousers (TPM 1.2), the Microsoft
# TPM simulator TCTI, tpm2-abrmd, pkcs11 and python bindings. None are needed.
IMAGE_INSTALL:append = "${@' tpm2-tools tpm2-tss libtss2-tcti-device systemd-crypt' \
    if d.getVar('LUKS_DATA_ENABLED') == '1' \
    and d.getVar('LUKS_DATA_KEY_MODE') == 'tpm' else ''}"

# All three are required and none is in systemd's default PACKAGECONFIG:
#   cryptsetup         -> systemd-cryptenroll binary
#   tpm2               -> links tpm2-tss so --tpm2-device works
#   cryptsetup-plugins -> libcryptsetup-token-systemd-tpm2.so, without which
#                         `cryptsetup open` silently ignores the LUKS2 token
PACKAGECONFIG:append:pn-systemd = "${@' cryptsetup tpm2 cryptsetup-plugins' \
    if d.getVar('LUKS_DATA_ENABLED') == '1' \
    and d.getVar('LUKS_DATA_KEY_MODE') == 'tpm' else ''}"

python () {
    if d.getVar('LUKS_DATA_ENABLED') != '1':
        return

    mode = d.getVar('LUKS_DATA_KEY_MODE')
    if mode not in ('tpm', 'keyfile'):
        bb.fatal("LUKS_DATA_KEY_MODE must be 'tpm' or 'keyfile', got '%s'" % mode)

    dev = d.getVar('LUKS_DATA_DEVICE') or ''
    if not dev:
        bb.fatal("LUKS_DATA_DEVICE is not set. It has no default on purpose --\n"
                 "state explicitly which partition gets encrypted, because the\n"
                 "number depends on how the card was flashed.\n"
                 "Set it in local.conf. A wrong number that happens to point at\n"
                 "an empty partition WILL be encrypted.")
    if not dev.startswith('part:') or not dev[5:].isdigit():
        bb.fatal("LUKS_DATA_DEVICE must be 'part:N', got '%s'" % dev)

    rec  = d.getVar('LUKS_DATA_RECOVERY_KEY')
    auto = d.getVar('LUKS_DATA_AUTO_PROVISION')
    for name, val in (('LUKS_DATA_RECOVERY_KEY', rec),
                      ('LUKS_DATA_AUTO_PROVISION', auto)):
        if val not in ('0', '1'):
            bb.fatal("%s must be '0' or '1', got '%s'" % (name, val))
    # The recovery key is shown exactly once, on the console. Nobody is watching
    # an unattended first boot, so the two settings cannot both be on.
    if rec == '1' and auto == '1':
        bb.fatal("LUKS_DATA_RECOVERY_KEY='1' requires LUKS_DATA_AUTO_PROVISION='0'.\n"
                 "The recovery key is printed once and is unrecoverable afterwards,\n"
                 "so something has to be there to capture it. Provision those units\n"
                 "by hand:  ecu150v2-luks-data.sh --provision\n"
                 "Or keep auto-provisioning and add a keyslot per unit later:\n"
                 "          ecu150v2-luks-data.sh --add-recovery-key")

    # rauc-setup-env.sh hardcodes p3 and unconditionally does
    # `mount -t ext4 <p3> /data`, so with RAUC on, p3 and /data must go together
    # -- in BOTH directions. Neither failure is recoverable at runtime:
    #   part:3 + other mount -> RAUC mounts a LUKS container as ext4, set -e kills it
    #   other part + /data   -> LUKS wins the race, RAUC state lands on the
    #                           encrypted volume, p3 is never mounted, NO error
    mnt = d.getVar('LUKS_DATA_MOUNT')
    if d.getVar('RAUC_ENABLED') == '1' and (dev == 'part:3') != (mnt == '/data'):
        bb.fatal("RAUC + LUKS mismatch: got LUKS_DATA_DEVICE='%s' with\n"
                 "LUKS_DATA_MOUNT='%s'. rauc-setup-env.sh always mounts p3 at\n"
                 "/data, so those two settings must agree. Decide which one you\n"
                 "actually want:\n"
                 "  (a) encrypt RAUC's own data partition:\n"
                 "        LUKS_DATA_DEVICE = \"part:3\"\n"
                 "        LUKS_DATA_MOUNT  = \"/data\"\n"
                 "  (b) encrypt a SEPARATE partition (flash the card with an\n"
                 "      extra appdata partition first):\n"
                 "        LUKS_DATA_DEVICE = \"part:N\"   (N != 3)\n"
                 "        LUKS_DATA_MOUNT  = \"/appdata\"" % (dev, mnt))

    if mode == 'keyfile':
        kf = d.getVar('LUKS_DATA_KEYFILE') or ''
        kd = d.getVar('LUKS_DATA_KEYS_DIR') or ''
        if not os.path.isfile(kf):
            bb.fatal("LUKS_DATA_KEYFILE (%s) not found. Create it once:\n"
                     "  mkdir -p %s && chmod 700 %s\n"
                     "  head -c 32 /dev/urandom > %s && chmod 400 %s\n"
                     "Do NOT commit it to the layer." % (kf, kd, kd, kf, kf))
}
