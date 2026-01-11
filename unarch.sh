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

printf "Source:\t\t\t%s\n" "$SOURCE_PATH"
printf "Destination:\t\t%s\n" "$DESTINATION_DIR"
printf "Determining Source Size..."
SOURCE_SIZE_BYTE=$(du -sk "$SOURCE_PATH" | awk '{print $1 * 1024}')
SOURCE_SIZE=$(to_human $SOURCE_SIZE_BYTE)
tput cr && tput el
printf "\rSource Size:\t\t$SOURCE_SIZE / $SOURCE_SIZE_BYTE bytes\n"
mkdir -p "$DESTINATION_DIR"
printf "Decompressing..."
7zz x -so "$SOURCE_PATH" | tar --acls --xattrs -C "$DESTINATION_DIR" -xf -
tput cr && tput el
printf "\rDetermining Destination Size..."
DESTINATION_SIZE_BYTE=$(du -sk "$DESTINATION_DIR" | awk '{print $1 * 1024}')
DESTINATION_SIZE=$(to_human $DESTINATION_SIZE_BYTE)
PERCENTAGE=$(( (DESTINATION_SIZE_BYTE * 100.0) / SOURCE_SIZE_BYTE ))
tput cr && tput el
printf "\rDestination Size:\t$DESTINATION_SIZE / $DESTINATION_SIZE_BYTE bytes (%.1f%%)\n" "$PERCENTAGE"
SIZE_DIFFERENCE_BYTE=$(( DESTINATION_SIZE_BYTE - SOURCE_SIZE_BYTE ))
SIZE_DIFFERENCE=$(to_human $SIZE_DIFFERENCE_BYTE)
printf "Difference:\t\t$SIZE_DIFFERENCE / $SIZE_DIFFERENCE_BYTE bytes\n"

echo "klolthxbye"
