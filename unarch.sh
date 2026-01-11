#!/usr/bin/env zsh

set -uo pipefail

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

printf "Source:\t\t\t%s\n" "$SOURCE_PATH"
printf "Destination:\t\t%s\n" "$DESTINATION_DIR"
printf "Determining Source Size..."
SOURCE_SIZE=$(du -sh "$SOURCE_PATH" | cut -f1)
SOURCE_SIZE_BYTE=$(du -sk "$SOURCE_PATH" | awk '{print $1 * 1024}')
tput cr && tput el
printf "\rSource Size:\t\t$SOURCE_SIZE / $SOURCE_SIZE_BYTE bytes\n"
mkdir -p "$DESTINATION_DIR"
printf "Decompressing..."
7zz x -so "$SOURCE_PATH" | tar --acls --xattrs -C "$DESTINATION_DIR" -xf -
tput cr && tput el
printf "\rDetermining Destination Size..."
DESTINATION_SIZE=$(du -sh "$DESTINATION_DIR" | cut -f1)
DESTINATION_SIZE_BYTE=$(du -sk "$DESTINATION_DIR" | awk '{print $1 * 1024}')
PERCENTAGE=$(( (DESTINATION_SIZE_BYTE * 100.0) / SOURCE_SIZE_BYTE ))
tput cr && tput el
printf "\rDestination Size:\t$DESTINATION_SIZE / $DESTINATION_SIZE_BYTE bytes (%.1f%%)\n" "$PERCENTAGE"

echo "klolthxbye"
