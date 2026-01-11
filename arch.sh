#!/usr/bin/env zsh

set -uo pipefail

to_human() {
	if (( "$1" < 0 )); then
		local ABS_SIZE_BYTES=$(( "$1" * -1 ))
		printf "-"
	else
		local ABS_SIZE_BYTES="$1"
	fi
    echo $ABS_SIZE_BYTES | awk '{
        split("B KB MB GB TB", unit);
        i=1;
        while($1>=1024 && i<5) { $1/=1024; i++ }
        printf "%.1f %s", $1, unit[i]
    }'
}

SOURCE_PATH="$1"

if [[ ! -e "$SOURCE_PATH" ]]; then
    echo "$SOURCE_PATH does not exist. Exiting."
    exit 1
fi

if (( $# >= 2 )); then
    if [[ -n "$2" ]]; then
		DESTINATION_DIR="$2"
	else
		DESTINATION_DIR="$PWD"
	fi
else
	DESTINATION_DIR="$PWD"
fi
DESTINATION_DIR=${DESTINATION_DIR:a}

printf "Source:\t\t%s\n" "$SOURCE_PATH"
DESTINATION_FILE="${DESTINATION_DIR:a}/${SOURCE_PATH:t}.tar.7z"
printf "Destination:\t%s\n" "$DESTINATION_FILE"
printf "Determining Source Size..."
SOURCE_SIZE=$(du -sh "$SOURCE_PATH" | cut -f1)
SOURCE_SIZE_BYTE=$(du -sk "$SOURCE_PATH" | awk '{print $1 * 1024}')
tput cr && tput el
printf "\rSource Size:\t$SOURCE_SIZE / $SOURCE_SIZE_BYTE bytes\n"
read "?Confirm with 'y': " CONFIRMATION
[[ $CONFIRMATION == "y" ]] || {
    echo "Exiting."
    exit 1
}

tar --acls --xattrs -C "${SOURCE_PATH:h}" -cf - "${SOURCE_PATH:t}" 2>/dev/null | 7zz a -t7z -si -mx=9 -m0=lzma2 -md=256m -mmt=on -bsp1 "$DESTINATION_FILE"

printf "Determining Archive Size..."
ARCHIVE_SIZE=$(du -sh "$DESTINATION_FILE" | cut -f1)
ARCHIVE_SIZE_BYTE=$(du -sk "$DESTINATION_FILE" | awk '{print $1 * 1024}')
PERCENTAGE=$(( (ARCHIVE_SIZE_BYTE * 100.0) / SOURCE_SIZE_BYTE ))
tput cr && tput el
printf "\rArchive Size:\t$ARCHIVE_SIZE / $ARCHIVE_SIZE_BYTE bytes (%.1f%%)\n" "$PERCENTAGE"
SIZE_DIFFERENCE_BYTE=$(( ARCHIVE_SIZE_BYTE - SOURCE_SIZE_BYTE ))
SIZE_DIFFERENCE=$(to_human $SIZE_DIFFERENCE_BYTE)

printf "Difference:\t$SIZE_DIFFERENCE / $SIZE_DIFFERENCE_BYTE bytes\n"

echo "klolthxbye"
