#!/usr/bin/env zsh

set -uo pipefail

SOURCE_PATH="$1"

if [[ ! -e "$SOURCE_PATH" ]]; then
    echo "$SOURCE_PATH does not exist. Exiting."
    exit 1
fi

DESTINATION_DIR="$2"

printf "Source:\t\t%s\n" "$SOURCE_PATH"
DESTINATION_FILE="${DESTINATION_DIR:a}/${SOURCE_PATH:t}.tar.7z"
echo "Determining Source Size..."
SOURCE_SIZE=$(du -sh "$SOURCE_PATH" | cut -f1)
SOURCE_SIZE_BYTE=$(du -sk "$SOURCE_PATH" | awk '{print $1 * 1024}')
echo "Source Size: $SOURCE_SIZE / $SOURCE_SIZE_BYTE bytes"
printf "Destination:\t%s\n" "$DESTINATION_FILE"
read "?Confirm with 'y': " CONFIRMATION
[[ $CONFIRMATION == "y" ]] || {
    echo "Exiting."
    exit 1
}

tar --acls --xattrs -C "${SOURCE_PATH:h}" -cf - "${SOURCE_PATH:t}" 2>/dev/null | 7zz a -t7z -si -mx=9 -m0=lzma2 -md=256m -mmt=on -bsp1 "$DESTINATION_FILE"

echo "Determining Archive Size..."
ARCHIVE_SIZE=$(du -sh "$DESTINATION_FILE" | cut -f1)
ARCHIVE_SIZE_BYTE=$(du -sk "$DESTINATION_FILE" | awk '{print $1 * 1024}')
echo "Archive Size: $ARCHIVE_SIZE / $ARCHIVE_SIZE_BYTE bytes"

PERCENTAGE=$(( (ARCHIVE_SIZE_BYTE * 100.0) / SOURCE_SIZE_BYTE ))
printf "%.1f%%\n" "$PERCENTAGE"

echo "klolthxbye"
