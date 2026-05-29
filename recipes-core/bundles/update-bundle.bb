SUMMARY = "ECU150v2 RAUC update bundle (rootfs only, v1)"
LICENSE = "MIT"

inherit bundle

RAUC_BUNDLE_COMPATIBLE  = "${RAUC_SYSTEM_COMPATIBLE}"
RAUC_BUNDLE_VERSION     = "${DATETIME}"
RAUC_BUNDLE_VERSION[vardepsexclude] = "DATETIME"
RAUC_BUNDLE_DESCRIPTION = "ECU150v2 rootfs update"
# RAUC_BUNDLE_FORMAT default "plain" is provided by conf/include/ecu150v2-rauc.inc.
# To override per-bundle, add one line here, e.g.:
#   RAUC_BUNDLE_FORMAT = "verity"

RAUC_BUNDLE_SLOTS = "rootfs"
RAUC_SLOT_rootfs  = "imx-image-core"
RAUC_SLOT_rootfs[fstype] = "ext4"

# Signing key default paths (physical isolation: private keys live OUTSIDE
# this layer, never committed). Override in local.conf for CI / HSM.
RAUC_KEYS_DIR     ?= "${HOME}/.config/rauc-keys-ecu150v2"
RAUC_KEY_FILE     ?= "${RAUC_KEYS_DIR}/dev.key.pem"
RAUC_CERT_FILE    ?= "${RAUC_KEYS_DIR}/dev.cert.pem"
RAUC_KEYRING_FILE ?= "${RAUC_KEYS_DIR}/ca.cert.pem"