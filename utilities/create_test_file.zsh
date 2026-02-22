#!/bin/zsh

# Usage: ./make-testfile.zsh <type> <size_in_mb> <output_file>
# Types: zero | random | mixed

set -e

TYPE="$1"
SIZE_MB="$2"
OUT="$3"

[[ -z "$TYPE" || -z "$SIZE_MB" || -z "$OUT" ]] && {
    echo "Usage: $0 <zero|random|mixed> <size_in_mb> <output_file>"
    exit 1
}

case "$TYPE" in
    zero)
        echo "Creating compressible file from /dev/zero..."
        dd if=/dev/zero of="$OUT" bs=1m count="$SIZE_MB" status=progress
        ;;
    random)
        echo "Creating incompressible file from /dev/urandom..."
        dd if=/dev/urandom of="$OUT" bs=1m count="$SIZE_MB" status=progress
        ;;
    mixed)
        echo "Creating mixed compressibility file..."
        TMP1="$(mktemp)"
        TMP2="$(mktemp)"
        dd if=/dev/zero of="$TMP1" bs=1m count=$((SIZE_MB / 2)) status=progress
        dd if=/dev/urandom of="$TMP2" bs=1m count=$((SIZE_MB - SIZE_MB / 2)) status=progress
        cat "$TMP1" "$TMP2" > "$OUT"
        rm -f "$TMP1" "$TMP2"
        ;;
    *)
        echo "Unknown type: $TYPE"
        exit 1
        ;;
esac

echo "Done: $OUT"
