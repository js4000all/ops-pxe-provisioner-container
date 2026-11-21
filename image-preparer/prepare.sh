#!/usr/bin/env bash
set -Eeuo pipefail

ACTION="${1:-prepare}"
ISO_URL="${ISO_URL:-}"
ISO_SHA256="${ISO_SHA256:-}"
ASSETS=/assets
ISO_DIR=$ASSETS/iso
BOOT_DIR=$ASSETS/boot

die() { echo "ERROR: $*" >&2; exit 1; }
hash_file() { sha256sum "$1" | awk '{print $1}'; }
valid_sha() { [[ "$1" =~ ^[[:xdigit:]]{64}$ ]]; }

# Accept an explicit SHA256 or resolve it from the official release directory.
expected_hash() {
  if [[ -n "$ISO_SHA256" ]]; then
    valid_sha "$ISO_SHA256" || die "ISO_SHA256 must be a 64-digit hexadecimal hash"
    printf '%s\n' "$ISO_SHA256" | tr '[:upper:]' '[:lower:]'
    return
  fi
  local manifest filename
  filename="${ISO_URL##*/}"
  manifest=$(mktemp)
  trap 'rm -f "$manifest"' RETURN
  curl --fail --location --retry 3 --silent --show-error \
    "$ISO_URL_DIR/SHA256SUMS" -o "$manifest" || die "Cannot retrieve SHA256SUMS; set ISO_SHA256 explicitly"
  awk -v f="$filename" '($2==f || $2=="*"f || $2=="./"f) && $1 ~ /^[[:xdigit:]]+$/ { print tolower($1); exit }' "$manifest"
}

case "$ACTION" in prepare|refresh|status) ;; *) die "Usage: prepare | refresh | status" ;; esac
[[ "$ISO_URL" == https://* ]] || die "ISO_URL must use HTTPS"
ISO_URL_DIR="${ISO_URL%/*}"
FILENAME="${ISO_URL##*/}"
[[ "$FILENAME" =~ ^[a-zA-Z0-9._-]+\.iso$ ]] || die "Invalid ISO filename"
# Destination is fixed to preserve the current Pixiecore and HTTP configuration.
ISO_FILE=$ISO_DIR/ubuntu-live-server.iso

# Resolve expected SHA256 once per invocation.
EXPECTED=$(expected_hash)
valid_sha "$EXPECTED" || die "Cannot determine ISO SHA256 for $FILENAME"
EXPECTED=$(printf '%s' "$EXPECTED" | tr '[:upper:]' '[:lower:]')

iso_ok() {
  [[ -s "$ISO_FILE" ]] && [[ "$(hash_file "$ISO_FILE")" == "$EXPECTED" ]]
}
boot_ok() {
  [[ -s "$BOOT_DIR/vmlinuz" && -s "$BOOT_DIR/initrd" && -f "$BOOT_DIR/source.sha256" ]] &&
    [[ "$(cat "$BOOT_DIR/source.sha256")" == "$EXPECTED" ]]
}

if [[ "$ACTION" == status ]]; then
  if iso_ok && boot_ok; then
    echo "READY: ISO checksum verified and boot files present ($EXPECTED)"
    exit 0
  fi
  echo "NOT READY: ISO or extracted boot files missing/outdated" >&2
  exit 1
fi

if [[ "$ACTION" == prepare ]] && iso_ok && boot_ok; then
  echo "Already prepared: $ISO_FILE"
  exit 0
fi

mkdir -p "$ISO_DIR" "$BOOT_DIR"
WORK=$(mktemp -d "$ASSETS/.image-preparer.XXXXXXXX")
trap 'rm -rf "$WORK"' EXIT

if [[ "$ACTION" == prepare ]] && iso_ok; then
  echo "Reusing verified ISO"
  cp "$ISO_FILE" "$WORK/installer.iso"
else
  echo "Downloading: $ISO_URL"
  curl --fail --location --retry 3 --continue-at - "$ISO_URL" -o "$WORK/installer.iso"
fi
ACTUAL=$(hash_file "$WORK/installer.iso")
[[ "$ACTUAL" == "$EXPECTED" ]] || die "ISO checksum mismatch: expected=$EXPECTED actual=$ACTUAL"
echo "ISO checksum OK"

mkdir -p "$WORK/boot"
bsdtar -x -f "$WORK/installer.iso" -C "$WORK/boot" casper/vmlinuz casper/initrd ||
  die "Could not extract casper/vmlinuz and casper/initrd"
test -s "$WORK/boot/casper/vmlinuz" || die "Extracted kernel is empty"
test -s "$WORK/boot/casper/initrd" || die "Extracted initrd is empty"

# Prepare all inputs before replacing published files. No change if download,
# verification or extraction fails. Stop PXE while refreshing served assets.
if [[ "$ACTION" == refresh ]] || ! iso_ok; then
  mv -f "$WORK/installer.iso" "$ISO_FILE"
fi
mv -f "$WORK/boot/casper/vmlinuz" "$BOOT_DIR/vmlinuz"
mv -f "$WORK/boot/casper/initrd" "$BOOT_DIR/initrd"
printf '%s\n' "$EXPECTED" > "$BOOT_DIR/source.sha256"
echo "Prepared: $ISO_FILE, $BOOT_DIR/vmlinuz, $BOOT_DIR/initrd"
