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

get_size() {
	local OBJECT_SIZE=$(du -sk "$1" | awk '{print $1 * 1024}')
	echo "$OBJECT_SIZE"
}

object_type() {
	if [[ ! -e "$1" && ! -L "$1" ]]; then
		echo "nonexistent"
	elif [[ -L "$1" ]]; then
		echo "symlink"
	elif [[ -d "$1" ]]; then
		echo "directory"
	elif [[ -f "$1" ]]; then
		echo "file"
	elif [[ -S "$1" ]]; then
		echo "socket"
	elif [[ -p "$1" ]]; then
		echo "named pipe"
	elif [[ -b "$1" ]]; then
		echo "block device"
	elif [[ -c "$1" ]]; then
		echo "character device"
	else
		echo "unknown"
	fi
}

check_7zz() {
	# Specific logic for 7zz
	if [[ $1 -eq 2 ]]; then
		echo "Fatal error (check disk space or file permissions)"
	elif [[ $1 -eq 8 ]]; then
		echo "Not enough memory"
	elif [[ $1 -eq 255 ]]; then
		echo "User stopped the process"
	else
		echo "Unknown"
	fi
}

check_tar() {
	# Specific logic for 7zz
	if [[ $1 -eq 1 ]]; then
		echo "Warning (some files differ, were busy, or couldn't be read, but the archive was still created)"
	elif [[ $1 -eq 2 ]]; then
		echo "Fatal Error (e.g., directory not found, disk full)"
	else
		echo "Unknown"
	fi
}

# Usage: check_pipeline "${pipestatus[@]}"
check_pipeline_tar_7zz() {
    local STATUSES=("$@")
    local EXIT_CODE=0

	if [[ ${STATUSES[1]} -ne 0 ]]; then
		printf "\rError: Command tar in pipeline failed with exit code ${STATUSES[1]}: $(check_tar ${STATUSES[1]})\n"
		EXIT_CODE=1
	fi

	if [[ ${STATUSES[2]} -ne 0 ]]; then
		printf "\rError: Command 7zz in pipeline failed with exit code ${STATUSES[2]}: $(check_7zz ${STATUSES[2]})\n"
		EXIT_CODE=1
	fi

    return $EXIT_CODE
}

check_pipeline_7zz_tar() {
    local STATUSES=("$@")
    local EXIT_CODE=0

	if [[ ${STATUSES[1]} -ne 0 ]]; then
		echo "Error: Command 7zz in pipeline failed with exit code ${STATUSES[1]}: $(check_7zz ${STATUSES[1]})\n"
		EXIT_CODE=1
	fi

	if [[ ${STATUSES[2]} -ne 0 ]]; then
		echo "Error: Command tar in pipeline failed with exit code ${STATUSES[2]}: $(check_tar ${STATUSES[2]})\n"
		EXIT_CODE=1
	fi

    return $EXIT_CODE
}

show_help() {
  cat << 'EOF'
NAME
	arch.sh — archive or unarchive .tar.7z files

SYNOPSIS
	arch.sh [-a | -u] [-o destination] input_path
	arch.sh -h | --help

DESCRIPTION
	arch.sh archives or unarchives files using tar and 7-Zip
	piped together, avoiding the creation of intermediate .tar
	files.

	The input_path specifies either the file, folder, or package
	to be archived, or the .tar.7z archive to be unarchived.

	Options may be specified in any order.

OPTIONS
	-h, --help
		Display this help and exit. All other arguments
		are ignored.

	-a, --archive
		Archive input_path into a .tar.7z file.

	-u, --unarchive
		Unarchive input_path, which must be a .tar.7z file.
		
	-y, --yes
		Skip user confirmation, live fast and dangerous.

	-d size, --dictionary size
		Set a custom dictionary size (in MB) for compression.
		
		If not specified, a dictionary size of 256MB will be used.

	-o destination, --output destination
		Specify the destination directory.

		When archiving, the resulting .tar.7z file is written
		to this directory.

		When unarchiving, the archive contents are extracted
		into this directory.

		If not specified, the current working directory is used.

OPERANDS
	input_path
		Path to the file, folder, or package to archive, or
		the .tar.7z file to unarchive.

NOTES
	Exactly one of a/--archive or -u/--unarchive must be specified.

	The destination directory is optional and defaults to the
	current working directory.

EXAMPLES
	Archive a folder into the current directory:
		arch.sh -a MyFolder
		
	Archive a file into the current directory with a custom compression
	dictionary size of 128MB:
		arch.sh -a MyFile.txt -d 128

	Archive a file to a specific directory:
		arch.sh --archive file.txt --output ~/Archives

	Unarchive into the current directory:
		arch.sh -u backup.tar.7z

	Unarchive into a specific directory:
		arch.sh -u backup.tar.7z -o ./output

EOF
}

# Ensure 7zz exists
if ! command -v 7zz >/dev/null 2>&1; then
	tput bold; echo "7zz not installed."; tput sgr0
	echo "Install with: brew install p7zip"
	exit 1
fi

OPERATION="none"
SOURCE_SPECIFIED="false"
DESTINATION_SPECIFIED="false"
CONFIRMATION_NEEDED="true"
DICTIONARY_SIZE=256
DICTIONARY_SIZE_SPECIFIED="false"

while (( $# > 0 )); do
    ARG="$1"

    case $ARG in
		-h|--help)
			show_help
			exit 0
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
		-y|--yes)
			CONFIRMATION_NEEDED="false"
			;;
		-d|--dictionary)
            if [[ $DICTIONARY_SIZE_SPECIFIED == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (dictionary size)
					DICTIONARY_SIZE="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag dictionary size as specified
					DICTIONARY_SIZE_SPECIFIED="true"
                else
                    echo "No dictionary size specified for -o/--output option. Exiting."
                    exit 1
				fi
			else
				echo "-d/--dictionary option specified multiple times. Exiting."
			fi
			;;
		-o|--output)
            if [[ $DESTINATION_SPECIFIED == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (destination path)
					DESTINATION_DIR="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag destination as specified
                    DESTINATION_SPECIFIED="true"
                else
                    echo "No destination specified for -o/--output option. Exiting."
                    exit 1
				fi
			else
				echo "-o/--output option specified multiple times. Exiting."
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
tput bold
if [[ $OPERATION == "archive" ]]; then
	echo "Archive ${SOURCE_PATH:t}"
else
	echo "Unarchive ${SOURCE_PATH:t}"
fi
tput sgr0
if [[ $DICTIONARY_SIZE_SPECIFIED == "true" ]]; then
	printf "Dictionary:\t%dm \n" $DICTIONARY_SIZE
fi
printf "Source:\t\t%s\n" "$SOURCE_PATH"
if [[ $OPERATION == "archive" ]]; then
	DESTINATION_PATH="${DESTINATION_DIR:a}/${SOURCE_PATH:t}.tar.7z"
else
	DESTINATION_PATH="${DESTINATION_DIR:a}"	# Add trailing '/'?
fi
printf "Destination:\t%s\n" "$DESTINATION_PATH"
printf "Determining Source Size..."
SOURCE_SIZE_BYTE=$(get_size $SOURCE_PATH)
SOURCE_SIZE=$(to_human $SOURCE_SIZE_BYTE)
tput cr && tput el
printf "\rSource Size:\t$SOURCE_SIZE / $SOURCE_SIZE_BYTE bytes\n"
if [[ -e $DESTINATION_PATH && $OPERATION == "archive" ]]; then
	DESTINATION_TYPE="$(object_type $DESTINATION_PATH)"
	if [[ $DESTINATION_TYPE == "file" ]]; then
		echo "Warning: ${DESTINATION_PATH:t} exists and will be overwritten."
	else
		echo "Warning: ${DESTINATION_PATH:t} exists and is not a file ($DESTINATION_TYPE). Exiting."
		exit 1
	fi
fi
if [[ -e $DESTINATION_PATH && $OPERATION == "unarchive" ]]; then
	DESTINATION_TYPE="$(object_type $DESTINATION_PATH)"
	if [[ $DESTINATION_TYPE != "directory" ]]; then
		echo "Warning: ${DESTINATION_PATH:t} exists and is not a folder ($DESTINATION_TYPE). Exiting."
		exit 1
	fi
fi

if [[ $CONFIRMATION_NEEDED == "true" ]]; then
	read "?Confirm with 'y': " CONFIRMATION
	[[ $CONFIRMATION == "y" ]] || {
		echo "Exiting."
		exit 1
	}
fi

if [[ -e $DESTINATION_PATH && $OPERATION == "archive" ]]; then
	printf "Deleting pre-existing ${DESTINATION_PATH:t}..."
	rm $DESTINATION_PATH
	tput cr && tput el
fi
mkdir -p "${DESTINATION_DIR:a}"
# Record start time (epoch seconds)
START_EPOCH=$(date +%s)

if [[ $OPERATION == "archive" ]]; then
	tar --acls --xattrs -C "${SOURCE_PATH:h}" -cf - "${SOURCE_PATH:t}" 2>/dev/null | 7zz a -t7z -si -mx=9 -m0=lzma2 -md="$DICTIONARY_SIZE"m -mmt=on -bso0 -bsp1 "$DESTINATION_PATH"
	if ! check_pipeline_tar_7zz "${pipestatus[@]}"; then
		echo "Exiting."
		exit 1
	fi
	printf "Determining archive size..."
else
	printf "Decompressing..."
	
	7zz x -so "$SOURCE_PATH" | tar --acls --xattrs -C "$DESTINATION_PATH" -xf -
	if ! check_pipeline_7zz_tar "${pipestatus[@]}"; then
		echo "Exiting."
		return 1
	fi
	printf "Determining destination size..."
fi

DESTINATION_SIZE_BYTE=$(get_size $DESTINATION_PATH)
DESTINATION_SIZE=$(to_human $DESTINATION_SIZE_BYTE)
PERCENTAGE=$(( (DESTINATION_SIZE_BYTE * 100.0) / SOURCE_SIZE_BYTE ))
tput cr && tput el
if [[ $OPERATION == "archive" ]]; then
	printf "\rArchive Size:\t"
else
	printf "\rDestin. Size:\t"
fi
printf "$DESTINATION_SIZE / $DESTINATION_SIZE_BYTE bytes (%.1f%%)\n" "$PERCENTAGE"
SIZE_DIFFERENCE_BYTE=$(( DESTINATION_SIZE_BYTE - SOURCE_SIZE_BYTE ))
SIZE_DIFFERENCE=$(to_human $SIZE_DIFFERENCE_BYTE)

printf "Difference:\t$SIZE_DIFFERENCE / $SIZE_DIFFERENCE_BYTE bytes\n"

# Record end time (epoch seconds)
END_EPOCH=$(date +%s)

# Calculate elapsed time
ELAPSED=$((END_EPOCH - START_EPOCH))
DAYS=$((ELAPSED / 86400))
REMAINDER=$((ELAPSED % 86400))
HOURS=$((REMAINDER / 3600))
REMAINDER=$((REMAINDER % 3600))
MINUTES=$((REMAINDER / 60))
SECONDS=$((REMAINDER % 60))

# Print formatted duration
if (( DAYS > 0 )); then
	printf "Elapsed time:\t${DAYS}d ${HOURS}h ${MINUTES}m ${SECONDS}s\n"
elif (( HOURS > 0 )); then
	printf "Elapsed time:\t${HOURS}h ${MINUTES}m ${SECONDS}s\n"
elif (( MINUTES > 0 )); then
	printf "Elapsed time:\t${MINUTES}m ${SECONDS}s\n"
else
	printf "Elapsed time:\t${SECONDS}s\n"
fi

echo "klolthxbye"
