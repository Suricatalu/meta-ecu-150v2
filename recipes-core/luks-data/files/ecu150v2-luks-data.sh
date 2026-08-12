#!/bin/bash
# ECU-150v2 encrypted data partition.
#   (no argument)        unlock + mount. Provisions an unprovisioned target only
#                        when AUTO_PROVISION=1. This is what the service runs.
#   --provision          provision now, regardless of AUTO_PROVISION.
#   --add-recovery-key   add a recovery keyslot to an already provisioned volume.
#
# There is NO recovery keyslot by default. A recovery key can only be captured
# by a human watching the console, and requiring that is what would force
# provisioning to be a manual step. Without it the first boot can provision
# itself; whoever needs a second way in adds it later with --add-recovery-key.
# -E so the ERR trap set in provision() also fires inside called functions.
set -eEuo pipefail

MAPPER_NAME="@LUKS_DATA_MAPPER@"
MOUNTPOINT="@LUKS_DATA_MOUNT@"
DEV_SPEC="@LUKS_DATA_DEVICE@"
KEY_MODE="@LUKS_DATA_KEY_MODE@"
WANT_RECOVERY="@LUKS_DATA_RECOVERY_KEY@"
AUTO_PROVISION="@LUKS_DATA_AUTO_PROVISION@"
PBKDF_ITER="@LUKS_DATA_PBKDF_ITER@"
PBKDF_MEMORY="@LUKS_DATA_PBKDF_MEMORY@"
PBKDF_PARALLEL="@LUKS_DATA_PBKDF_PARALLEL@"

KEYFILE=/etc/ecu150v2/data.key
RECOVERY_TMP=/run/luks-recovery.key
BOOTSTRAP_TMP=/run/luks-bootstrap.key
WAIT_TIMEOUT=10

# LUKS2 header labels. The only way to tell our own half-built container (safe
# to wipe, nothing was ever written to it) from a finished one whose key is
# temporarily unavailable (must never be wiped).
LABEL_WIP=ecu150v2-wip
LABEL_READY=ecu150v2

# LUKS2 payload offset; zeroing this much kills the header and every keyslot.
HEADER_MIB=16

DATA_DEV=""
ROOT_DEV=""

log() { echo "luks-data: $*"; }
die() { echo "luks-data: FATAL: $*" >&2; exit 1; }

# $1 = banner text. /run is tmpfs, so this is the only chance to see the key.
print_recovery_key() {
    [ -s "$RECOVERY_TMP" ] || return 0
    echo
    echo "=============== $1 ==============="
    cat "$RECOVERY_TMP"; echo
    echo "==================================================="
    echo "Store this OFF-DEVICE now. It is never shown again, and /run is"
    echo "tmpfs -- a reboot destroys it. Type it back exactly as shown,"
    echo "with no trailing spaces or newline."
    echo
}

# Flags -> partition number table. Printed on any target-resolution failure so
# the message alone is enough to fix the mismatch.
print_contract() {
    cat >&2 <<EOF

  The partition layout is created by the flash tool
  (tools/flash/ecu150v2_flash.sh), so WHICH number holds the LUKS target
  depends on the flags that card was flashed with. This image was built for
  LUKS_DATA_DEVICE = "${DEV_SPEC}".

      flash flags              LUKS target
      --rauc                   part:3     (the layout we currently ship)
      --appdata                part:2
      --rauc --appdata         part:4
      (--overlay-data does not affect the number)

  There is no default on the Yocto side: LUKS_DATA_DEVICE must be set in
  local.conf to match how the card was flashed.

  Fix either end -- rebuild with a matching LUKS_DATA_DEVICE, or re-flash
  with flags matching this image.
EOF
}

resolve_device() {
    local part_num root_name base
    case "$DEV_SPEC" in
        part:[0-9]*) part_num="${DEV_SPEC#part:}" ;;
        *) die "LUKS_DATA_DEVICE must be 'part:N', got '${DEV_SPEC}'" ;;
    esac

    root_name=$(grep -oP 'root=/dev/\K[^ ]+' /proc/cmdline || true)
    [ -n "$root_name" ] || die "no root=/dev/... in /proc/cmdline"

    ROOT_DEV="/dev/${root_name}"
    base="/dev/${root_name%p[0-9]*}"
    DATA_DEV="${base}p${part_num}"
}

wait_for_dev() {
    local dev="$1" i=0
    while [ "$i" -lt "$WAIT_TIMEOUT" ]; do
        [ -e "$dev" ] && return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# Refuse to format anything that would destroy data. Called only from provision().
# Step (0) is split out because the re-provisioning path below satisfies steps
# (1)/(2) by other means but must still never touch the running rootfs.
guard_not_rootfs() {
    if [ "$DATA_DEV" = "$ROOT_DEV" ]; then
        die "target ${DATA_DEV} is the running rootfs -- refusing"
    fi
}

run_guards() {
    local fstype probe_dir found

    guard_not_rootfs

    # (1) completely blank -> safe
    fstype=$(blkid -o value -s TYPE "$DATA_DEV" 2>/dev/null || true)
    if [ -z "$fstype" ]; then
        log "target ${DATA_DEV} has no filesystem, safe to format"
        return 0
    fi

    # (2) has a filesystem -> mount read-only and check whether it is empty.
    #     A freshly mkfs'd ext4 only contains lost+found and must be allowed.
    probe_dir=$(mktemp -d)
    if ! mount -o ro "$DATA_DEV" "$probe_dir" 2>/dev/null; then
        rmdir "$probe_dir"
        die "target ${DATA_DEV} has fstype '${fstype}' but cannot be mounted -- refusing"
    fi
    found=$(find "$probe_dir" -mindepth 1 ! -name lost+found -print -quit 2>/dev/null || true)
    umount "$probe_dir"
    rmdir "$probe_dir"

    if [ -n "$found" ]; then
        die "target ${DATA_DEV} contains data (fstype ${fstype}) -- refusing. \
Back it up and wipe it first, or pick a different LUKS_DATA_DEVICE."
    fi
    log "target ${DATA_DEV} holds an empty ${fstype}, safe to format"
}

# $1 = 1 to skip the emptiness guards, for the one caller that has already
# proven the target holds nothing (a half-built container of our own).
provision() {
    local skip_guards="${1:-0}"
    local boot_key drop_boot=0
    local -a pbkdf=()

    log "provisioning ${DATA_DEV} (mode: ${KEY_MODE}, recovery keyslot: $([ "$WANT_RECOVERY" = 1 ] && echo yes || echo no))"
    guard_not_rootfs
    if [ "$skip_guards" -eq 0 ]; then run_guards; fi

    # luksFormat always needs one secret to start from. What that secret IS, and
    # whether it survives, is the whole difference between the two policies.
    if [ "$WANT_RECOVERY" = "1" ]; then
        # It stays in the header as the recovery keyslot, so it gets the
        # expensive KDF and has to reach a human before we go any further.
        ( umask 077; head -c 32 /dev/urandom | base32 | tr -d '\n' > "$RECOVERY_TMP" )
        boot_key="$RECOVERY_TMP"
        pbkdf=(--pbkdf argon2id
               --pbkdf-force-iterations "$PBKDF_ITER"
               --pbkdf-memory "$PBKDF_MEMORY"
               --pbkdf-parallel "$PBKDF_PARALLEL")
        trap 'print_recovery_key "PROVISIONING FAILED -- SAVE THIS KEY BEFORE REBOOT"' ERR
    elif [ "$KEY_MODE" = "keyfile" ]; then
        # data.key can open the container from the very first moment, so it is
        # the only keyslot that ever exists. No argon2id slot means no wasted
        # Argon2id attempt on every unlock either.
        [ -f "$KEYFILE" ] || die "${KEYFILE} missing"
        boot_key="$KEYFILE"
        pbkdf=(--pbkdf pbkdf2 --pbkdf-force-iterations 1000)
    else
        # Transient: alive only between luksFormat and the TPM enrol, then removed.
        ( umask 077; head -c 32 /dev/urandom > "$BOOTSTRAP_TMP" )
        boot_key="$BOOTSTRAP_TMP"
        pbkdf=(--pbkdf pbkdf2 --pbkdf-force-iterations 1000)
        drop_boot=1
    fi

    cryptsetup luksFormat --type luks2 --batch-mode \
        --key-file "$boot_key" \
        --label "$LABEL_WIP" \
        --cipher aes-xts-plain64 --key-size 512 \
        --sector-size 4096 \
        "${pbkdf[@]}" \
        "$DATA_DEV"

    case "$KEY_MODE" in
        tpm)
            # --tpm2-pcrs= (empty) on purpose: omitting the flag entirely does
            # NOT mean "no PCRs" -- systemd-cryptenroll's own default is PCR 7,
            # which is always zero here (no UEFI), so the empty string is what
            # actually keeps this a plain "seal to this chip" policy.
            systemd-cryptenroll --unlock-key-file="$boot_key" \
                --tpm2-pcrs= --tpm2-device=auto "$DATA_DEV"
            ;;
        keyfile)
            if [ "$boot_key" != "$KEYFILE" ]; then
                [ -f "$KEYFILE" ] || die "${KEYFILE} missing"
                cryptsetup luksAddKey --batch-mode \
                    --key-file "$boot_key" \
                    --pbkdf pbkdf2 --pbkdf-force-iterations 1000 \
                    "$DATA_DEV" "$KEYFILE"
            fi
            ;;
        *) die "unknown KEY_MODE '${KEY_MODE}'" ;;
    esac

    # Prove the runtime key works BEFORE the bootstrap secret goes away. This is
    # the only thing between a missing token plugin and a container nobody can
    # open -- systemd-cryptenroll succeeds even when cryptsetup cannot use the
    # token it just wrote.
    unlock

    if [ "$drop_boot" -eq 1 ]; then
        cryptsetup luksRemoveKey "$DATA_DEV" "$boot_key"
        log "bootstrap keyslot removed; the TPM is now the only way in"
    fi

    if [ "$WANT_RECOVERY" = "1" ]; then
        trap - ERR
        print_recovery_key "RECOVERY KEY"
    fi
    wipe_tmp_keys

    finish_mkfs_and_mount
    cryptsetup config "$DATA_DEV" --label "$LABEL_READY"
    log "provisioning done"
}

wipe_tmp_keys() {
    local f
    for f in "$RECOVERY_TMP" "$BOOTSTRAP_TMP"; do
        [ -e "$f" ] || continue
        shred -u "$f" 2>/dev/null || rm -f "$f"
    done
}

# Add a second way into an already provisioned volume. Deliberately a separate,
# explicit action: the key is printed once and cannot be retrieved afterwards.
add_recovery_key() {
    cryptsetup isLuks --type luks2 "$DATA_DEV" \
        || die "${DATA_DEV} is not provisioned -- nothing to add a keyslot to"

    case "$KEY_MODE" in
        tpm)
            command -v systemd-cryptenroll >/dev/null \
                || die "systemd-cryptenroll missing -> PACKAGECONFIG[cryptsetup] on systemd"
            systemd-cryptenroll --unlock-tpm2-device=auto \
                --recovery-key "$DATA_DEV"
            ;;
        keyfile)
            [ -f "$KEYFILE" ] || die "${KEYFILE} missing"
            ( umask 077; head -c 32 /dev/urandom | base32 | tr -d '\n' > "$RECOVERY_TMP" )
            cryptsetup luksAddKey --batch-mode \
                --key-file "$KEYFILE" \
                --pbkdf argon2id \
                --pbkdf-force-iterations "$PBKDF_ITER" \
                --pbkdf-memory "$PBKDF_MEMORY" \
                --pbkdf-parallel "$PBKDF_PARALLEL" \
                "$DATA_DEV" "$RECOVERY_TMP"
            print_recovery_key "RECOVERY KEY"
            wipe_tmp_keys
            ;;
        *) die "unknown KEY_MODE '${KEY_MODE}'" ;;
    esac
    log "recovery keyslot added to ${DATA_DEV}"
}

# Formats the already-unlocked mapper device and mounts it. Shared by
# provision() and the interrupted-provisioning recovery path in main().
finish_mkfs_and_mount() {
    mkfs.ext4 -F -L cryptdata "/dev/mapper/${MAPPER_NAME}"
    mount_target
    printf 'provisioned=%s mode=%s\n' "$(date -Is)" "$KEY_MODE" \
        > "${MOUNTPOINT}/.luks-provisioned"
}

# Open the container. Returns non-zero instead of dying, because one caller has
# to tell "cannot open" apart from "real failure" before deciding what to do.
try_unlock() {
    if [ -e "/dev/mapper/${MAPPER_NAME}" ]; then
        return 0
    fi
    case "$KEY_MODE" in
        tpm)
            # Relies on libcryptsetup-token-systemd-tpm2.so reading the token.
            cryptsetup open "$DATA_DEV" "$MAPPER_NAME"
            ;;
        keyfile)
            [ -f "$KEYFILE" ] || return 1
            cryptsetup open --key-file "$KEYFILE" "$DATA_DEV" "$MAPPER_NAME"
            ;;
        *) return 1 ;;
    esac
}

unlock() {
    if [ -e "/dev/mapper/${MAPPER_NAME}" ]; then
        log "${MAPPER_NAME} already open"
        return 0
    fi
    if ! try_unlock; then
        case "$KEY_MODE" in
            tpm) die \
"TPM unlock failed. Two likely causes:
  (a) libcryptsetup-token-systemd-tpm2.so missing -> PACKAGECONFIG[cryptsetup-plugins]
  (b) this container has no systemd-tpm2 token (provisioned in keyfile mode?)
      -> check: cryptsetup luksDump ${DATA_DEV} | grep -A6 Tokens" ;;
            *)   die "keyfile unlock failed" ;;
        esac
    fi
    log "unlocked -> /dev/mapper/${MAPPER_NAME}"
}

# "(no label)" when unset, otherwise the LUKS2 header label.
luks_label() {
    cryptsetup luksDump "$1" 2>/dev/null | sed -n 's/^Label:[[:space:]]*//p' | head -1
}

mount_target() {
    mkdir -p "$MOUNTPOINT"
    if mountpoint -q "$MOUNTPOINT"; then
        log "${MOUNTPOINT} already mounted"
        return 0
    fi
    mount "/dev/mapper/${MAPPER_NAME}" "$MOUNTPOINT" \
        || die "mount ${MOUNTPOINT} failed"
    log "mounted ${MOUNTPOINT}"
}

main() {
    local mode=boot
    case "${1:-}" in
        "")                 mode=boot ;;
        --provision)        mode=provision ;;
        --add-recovery-key) mode=addkey ;;
        *) die "unknown argument '${1}' (accepted: --provision, --add-recovery-key)" ;;
    esac

    resolve_device

    if ! wait_for_dev "$DATA_DEV"; then
        echo "luks-data: FATAL: LUKS target not found: ${DEV_SPEC} (resolved to ${DATA_DEV})" >&2
        print_contract
        exit 1
    fi

    if [ "$KEY_MODE" = "tpm" ]; then
        wait_for_dev /dev/tpmrm0 \
            || die "/dev/tpmrm0 never appeared -- is the TPM driver loaded? (dmesg | grep -i tpm)"
    fi

    if [ "$mode" = "addkey" ]; then
        add_recovery_key
        return 0
    fi

    # --type luks2 rejects a foreign LUKS1 header (or one from another
    # project): isLuks with no --type would accept it here and only fail
    # later inside unlock(), with a misleading diagnostic.
    if cryptsetup isLuks --type luks2 "$DATA_DEV"; then
        if ! try_unlock; then
            # Cannot open it. Whether that is recoverable depends entirely on
            # whether WE left it here half-built.
            if [ "$(luks_label "$DATA_DEV")" = "$LABEL_WIP" ]; then
                log "found our own unfinished container (label ${LABEL_WIP}) that cannot be opened"
                log "it never held a filesystem, so nothing can be lost -- rebuilding it"
                guard_not_rootfs
                dd if=/dev/zero of="$DATA_DEV" bs=1M count="$HEADER_MIB" conv=fsync status=none
                provision 1
                return 0
            fi
            unlock   # finished container: reuse the diagnostic and die
        fi
        log "unlocked -> /dev/mapper/${MAPPER_NAME}"

        # A container that exists but holds no filesystem means luksFormat
        # succeeded but mkfs never ran: provisioning was interrupted (e.g.
        # power loss). The header is untouched, so the keys are still good --
        # just finish the mkfs step.
        if [ -z "$(blkid -o value -s TYPE "/dev/mapper/${MAPPER_NAME}" 2>/dev/null || true)" ]; then
            if [ "$mode" != "provision" ] && [ "$AUTO_PROVISION" != "1" ]; then
                die "${DATA_DEV} is LUKS but holds no filesystem -- provisioning was interrupted. Run:  $(basename "$0") --provision  to finish it."
            fi
            log "finishing an interrupted provisioning: mkfs only, header untouched"
            finish_mkfs_and_mount
            cryptsetup config "$DATA_DEV" --label "$LABEL_READY"
        else
            # Already provisioned: --provision is a no-op, never a reformat.
            if [ "$mode" = "provision" ]; then
                log "${DATA_DEV} is already LUKS, nothing to provision"
            fi
            mount_target
        fi
    else
        if [ "$mode" != "provision" ] && [ "$AUTO_PROVISION" != "1" ]; then
            die "${DATA_DEV} is not provisioned. Run:  $(basename "$0") --provision"
        fi
        provision
    fi
}

main "$@"
