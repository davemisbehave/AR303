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

OPERATION="none"
SOURCE_SPECIFIED="false"
DESTINATION_SPECIFIED="false"

while (( $# > 0 )); do
    ARG="$1"

    case $ARG in
		-h|--help)
			tput bold; echo "Usage:"; tput sgr0
			echo '\t'"$0 [-h|--help] [-a|--archive || -u/--unarchive] [-d|--destination <destination>]"
            
            tput bold; echo '\n'"Description:"; tput sgr0
			echo '\t'"This script archives and compresses, or unarchives and decompresses files and folders using tar and 7zip."

			tput bold; echo '\n'"Options:"; tput sgr0
			echo '\t'"[-h  | --help]		Show this help message and exit."

			tput bold; echo '\n'"Examples:"; tput sgr0
			
			echo '\t'"$0"
			echo '\t'"$0 --help"
			echo '\t'"More examples coming soon..."
			exit 1
            ;;
		-a|--archive)
			if [[ $OPERATION == "none" ]]; then
				OPERATION="archive"
			else
				echo "-a/--archive and -u/--unarchive options both selected. Exiting."
				exit 1
			fi
			;;
		-u|--unarchive)
			if [[ $OPERATION == "none" ]]; then
				OPERATION="unarchive"
			else
				echo "-a/--archive and -u/--unarchive options both selected. Exiting."
				exit 1
			fi
			;;
		-d|--destination)
            if [[ $DESTINATION_SPECIFIED == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (destination path)
					DESTINATION_DIR="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag destination as specified
                    DESTINATION_SPECIFIED="true"
                else
                    echo "No destination specified for -d/--destination option. Exiting."
                    exit 1
				fi
			else
				echo "-d/--destination option specified multiple times. Exiting."
			fi
			;;
		*)
			if [[ $ARG == -* ]]; then
				echo "Error: Invalid argument detected: $ARG"
				exit 1
			fi
			if [[ $SOURCE_SPECIFIED == "true" ]]; then
				echo "Error: Multiple sources specified. Exiting."
				exit 1
			fi
			SOURCE_PATH="$1"
			SOURCE_SPECIFIED="true"
			;;
	esac

	# Move to the next argument
	shift
done

if [[ $OPERATION == "none" ]]; then
	echo "No operation was specified. Use -a/--archive or -u/--unarchive. Run ./$0 -h for help."
	echo "Exiting Script."
fi

if [[ ! -e "$SOURCE_PATH" ]]; then
    echo "$SOURCE_PATH does not exist. Exiting."
    exit 1
fi

if [[ $DESTINATION_SPECIFIED == "false" ]]; then
	DESTINATION_DIR="$PWD"
fi

DESTINATION_DIR=${DESTINATION_DIR:a}
if [[ $OPERATION == "archive" ]]; then
	echo "Archive ${SOURCE_PATH:t}"
else
	echo "Unarchive ${SOURCE_PATH:t}"
fi
printf "Source:\t\t%s\n" "$SOURCE_PATH"
if [[ $OPERATION == "archive" ]]; then
	DESTINATION_PATH="${DESTINATION_DIR:a}/${SOURCE_PATH:t}.tar.7z"
else
	DESTINATION_PATH="${DESTINATION_DIR:a}"	# Add trailing '/'?
fi
printf "Destination:\t%s\n" "$DESTINATION_PATH"
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
mkdir -p "${DESTINATION_DIR:a}"
if [[ $OPERATION == "archive" ]]; then
	tar --acls --xattrs -C "${SOURCE_PATH:h}" -cf - "${SOURCE_PATH:t}" 2>/dev/null | 7zz a -t7z -si -mx=9 -m0=lzma2 -md=256m -mmt=on -bsp1 "$DESTINATION_PATH"
	printf "Determining archive size..."
else
	printf "Decompressing..."
	7zz x -so "$SOURCE_PATH" | tar --acls --xattrs -C "$DESTINATION_PATH" -xf -
	tput cr && tput el
	printf "Determining destination size..."
fi
DESTINATION_SIZE_BYTE=$(du -sk "$DESTINATION_PATH" | awk '{print $1 * 1024}')
DESTINATION_SIZE=$(to_human $DESTINATION_SIZE_BYTE)
PERCENTAGE=$(( (DESTINATION_SIZE_BYTE * 100.0) / SOURCE_SIZE_BYTE ))
tput cr && tput el
if [[ $OPERATION == "archive" ]]; then
	printf "\rArchive Size:\t"
else
	printf "\rDestination Size:\t"
fi
printf "$DESTINATION_SIZE / $DESTINATION_SIZE_BYTE bytes (%.1f%%)\n" "$PERCENTAGE"
SIZE_DIFFERENCE_BYTE=$(( DESTINATION_SIZE_BYTE - SOURCE_SIZE_BYTE ))
SIZE_DIFFERENCE=$(to_human $SIZE_DIFFERENCE_BYTE)

printf "Difference:\t$SIZE_DIFFERENCE / $SIZE_DIFFERENCE_BYTE bytes\n"

echo "klolthxbye"
