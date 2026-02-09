#!/usr/bin/env zsh

set -uo pipefail

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

    -a, --archive, -A, --Archive
        Archive input_path into a .tar.7z file.
        Skip user confirmation if -A or --Archive is specified.

    -u, --unarchive, -U, --Unarchive
        Unarchive input_path, which must be a .tar.7z file.
        Skip user confirmation if -U or --Unarchive is specified.

    -b, --binary
        Display and interpret suffixes as multiples of 1024 (i.e.
        MiB, GiB, etc.).
        
        If not specified, the default of 1000 (i.e. MB, GB, etc.)
        will be used.
        
    -i, --integrity
        Perform integrity check after creating an archive.
        
        The check can take a long time for large archives.

    -f, --fast
        Skip source and destination size determination.
        
        The check can take a long time for large directories with
        a lot of files in them.
        
    -s, --silent
        Disable all output to stdout. File size checks are also
        skipped if this option is specified (as they would not
        be visible anyways).
        
        Error messages are still written to stderr.

    -e, --encrypt
        Use SHA-256 to encrypt the archive. The user will be asked
        to enter the password during runtime.
        
    -E password, --Encrypt password
        Use SHA-256 to encrypt the archive using the password
        specified in the next argument. This method is highly
        insecure and not reccommended.
        
        i.e. -E p55w0rd or --Encrypt pa55w0rd

    -d size, --dictionary size
        Set a custom dictionary size (in MB) for compression.
        
        If not specified, a dictionary size of 256MB will be used.
  
    -t threads, --threads threads
        Set a custom number of threads for compression.
        This must be a number greater than 1, or can be
        either "auto" or "on" for an automatic setting.
        
        If not specified, the automatic setting will be used.

    -o destination, --output destination
        Specify the destination directory.

        When archiving, the resulting .tar.7z file is written
        to this directory.

        When unarchiving, the archive contents are extracted
        into this directory.

        If not specified, the current working directory is used.
        
    -O file_name, --Output file_name
        Specify the output file name for archiving.

        The resulting .tar.7z file is written
        to this directory.
        
        This option only applies to archiving. The program will
        exit with an error if specified for an unarchiving operation.

        If nothing is specified, the resulting archive will have the
        same name as the source file or folder, but with a ".tar.7z"
        postfix.

OPERANDS
    input_path
        Path to the file, folder, or package to archive, or
        the .tar.7z file to unarchive.

NOTES
    Exactly one of -a/--archive, -A/-Archive, -u/--unarchive or
    -U/--Unarchive must be specified.

    The destination directory is optional and defaults to the
    current working directory.

EXAMPLES
    Archive a folder into the current directory without asking the user
    to confirm, and perform an integrity check of the resulting archive:
        arch.sh -Ai MyFolder
        
    Archive a file into the current directory with a custom compression
    dictionary size of 128MB:
        arch.sh -a MyFile.txt -d 128

    Archive a file to a specific directory with a specific name:
        arch.sh --archive file.txt -O ~/Archives/foofile.txt.tar.7z

    Unarchive into the current directory and show file sizes in binary
    format:
        arch.sh -ub backup.tar.7z

    Unarchive into a specific directory and skip file size checks:
        arch.sh -uf backup.tar.7z -o ./output

EOF
}

to_human() {
    if (( "$1" < 0 )); then
        local ABS_SIZE_BYTES=$(( "$1" * -1 ))
        printf "-"
    else
        local ABS_SIZE_BYTES="$1"
    fi
    
    if [[ $SIZE_FORMAT == "binary" ]]; then
        echo $ABS_SIZE_BYTES | awk '{
            split("B KiB MiB GiB TiB", unit);
            i=1;
            while($1>=1024 && i<5) { $1/=1024; i++ }
            printf "%.1f %s", $1, unit[i]
        }'
    else
        echo $ABS_SIZE_BYTES | awk '{
            split("B KB MB GB TB", unit);
            i=1;
            while($1>=1000 && i<5) { $1/=1000; i++ }
            printf "%.1f %s", $1, unit[i]
        }'
    fi
}

get_size() {
    local TARGET="$1"
    
    if [ -f "$TARGET" ]; then
        # If it's a file, just get its size
        stat -f%z "$TARGET"
    elif [ -d "$TARGET" ]; then
        # If it's a directory, sum the size of all files inside recursively
        # -type f: looks only for files (ignoring directory metadata size)
        # -print0 / -0: handles filenames with spaces correctly
        find "$TARGET" -type f -print0 | xargs -0 stat -f%z | awk '{s+=$1} END {print s+0}'
    else
        echo "Error: $TARGET is not a valid file or directory" >&2
        return 1
    fi
    return 0
}

object_type() {
	if [[ ! -e "$1" && ! -L "$1" ]]; then
		echo "nonexistent"	# Object does not exist
	elif [[ -L "$1" ]]; then
		echo "symlink"		# Symlink
	elif [[ -d "$1" ]]; then
		echo "directory"	# Folder (Directory)
	elif [[ -f "$1" ]]; then
		echo "file"			# File
	elif [[ -S "$1" ]]; then
		echo "socket"		# Socket
	elif [[ -p "$1" ]]; then
		echo "pipe"			# Named pipe (FIFO)
	elif [[ -b "$1" ]]; then
		echo "block"		# Block device
	elif [[ -c "$1" ]]; then
		echo "character"	# Character device
	else
		echo "unknown"
	fi
}

check_7zz() {
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
	if [[ $1 -eq 1 ]]; then
		echo "Warning (some files differ, were busy, or couldn't be read, but the archive was still created)"
	elif [[ $1 -eq 2 ]]; then
		echo "Fatal Error (e.g., directory not found, disk full)"
	else
		echo "Unknown"
	fi
}

# Usage: check_pipeline_tar_pv_7zz "${pipestatus[@]}"
check_pipeline_tar_pv_7zz() {
    local STATUSES=("$@")
    local EXIT_CODE=0

	if [[ ${STATUSES[1]} -ne 0 ]]; then
		printf "\rError: Command tar in pipeline failed with exit code ${STATUSES[1]}: $(check_tar ${STATUSES[1]})\n" >&2
		EXIT_CODE=1
	fi

	if [[ ${STATUSES[2]} -ne 0 ]]; then
		printf "\rError: Command pv in pipeline failed with exit code ${STATUSES[2]}\n" >&2
		EXIT_CODE=1
	fi
 
    if [[ ${STATUSES[3]} -ne 0 ]]; then
        printf "\rError: Command 7zz in pipeline failed with exit code ${STATUSES[2]}: $(check_7zz ${STATUSES[3]})\n" >&2
        EXIT_CODE=1
    fi

    return $EXIT_CODE
}

# Usage: check_pipeline_7zz_pv_tar "${pipestatus[@]}"
check_pipeline_7zz_pv_tar() {
    local STATUSES=("$@")
    local EXIT_CODE=0

	if [[ ${STATUSES[1]} -ne 0 ]]; then
		echo "Error: Command 7zz in pipeline failed with exit code ${STATUSES[1]}: $(check_7zz ${STATUSES[1]})\n" >&2
		EXIT_CODE=1
	fi

    if [[ ${STATUSES[2]} -ne 0 ]]; then
        echo "Error: Command pv in pipeline failed with exit code ${STATUSES[2]}\n" >&2
        EXIT_CODE=1
    fi

	if [[ ${STATUSES[3]} -ne 0 ]]; then
		echo "Error: Command tar in pipeline failed with exit code ${STATUSES[3]}: $(check_tar ${STATUSES[3]})\n" >&2
		EXIT_CODE=1
	fi

    return $EXIT_CODE
}

check_pipeline_tar_7zz() {
    local STATUSES=("$@")
    local EXIT_CODE=0

    if [[ ${STATUSES[1]} -ne 0 ]]; then
        echo "Error: Command tar in pipeline failed with exit code ${STATUSES[1]}: $(check_tar ${STATUSES[1]})\n" >&2
        EXIT_CODE=1
    fi

    if [[ ${STATUSES[2]} -ne 0 ]]; then
        echo "Error: Command 7zz in pipeline failed with exit code ${STATUSES[2]}: $(check_7zz ${STATUSES[2]})\n" >&2
        EXIT_CODE=1
    fi

    return $EXIT_CODE
}

tar_pv_7zz_with_two_phase_progress() {
    local TMPDIR FIFO PID7zz ST7zz
    local -a ST_PACK STATUSES
    local TAR_OPTIONS
    local -a PV_ARCHIVE_OPTIONS

    TMPDIR="$(mktemp -d -t tar7zz)" || return 1
    FIFO="$TMPDIR/stream.FIFO"
    mkfifo "$FIFO" || { rmdir "$TMPDIR" 2>/dev/null; return 1; }

    # Cleanup on exit / ctrl-c
    cleanup() {
        local ec=$?
        [[ -n "${PID7zz:-}" ]] && kill -0 "$PID7zz" 2>/dev/null && kill "$PID7zz" 2>/dev/null
        rm -f "$FIFO" 2>/dev/null
        rmdir "$TMPDIR" 2>/dev/null
        return $ec
    }
    trap cleanup INT TERM HUP EXIT
    
    if [[ $CHECK_FILE_SIZES == "true" ]]; then
        [[ $SIZE_FORMAT == "decimal" ]] && PV_ARCHIVE_OPTIONS+=(-k)
        PV_ARCHIVE_OPTIONS+=(-s "$SOURCE_SIZE_BYTE" -ptebar)
    else
        PV_ARCHIVE_OPTIONS+=(-trab)
    fi
    PV_ARCHIVE_OPTIONS+=(-N "${SOURCE_PATH:t}")
    
    [[ "$SILENT" == "true" ]] && PV_ARCHIVE_OPTIONS+=(-q)

    # Start 7zz consuming from FIFO in the background
    7zz "${ZIP_OPTIONS[@]}" "$DESTINATION_PATH" <"$FIFO" &
    PID7zz=$!

    # Phase 1: tar -> pv -> FIFO (foreground, so we can read $pipestatus)
    tar --acls --xattrs -C "${SOURCE_PATH:h}" -cf - "${SOURCE_PATH:t}" 2>/dev/null \
    | pv "${PV_ARCHIVE_OPTIONS[@]}"\
    >"$FIFO"

    ST_PACK=("${pipestatus[@]}")  # (tar, pv)

    # Phase 2: spinner while 7zz is still compressing/writing
    if kill -0 "$PID7zz" 2>/dev/null; then
        local frames=('|' '/' '-' '\')
        local i=1
        while kill -0 "$PID7zz" 2>/dev/null; do
            printf "\rFinishing compression… %s" "${frames[i]}"
            i=$(( i % ${#frames} + 1 ))
            sleep 0.12
        done
        tput cr; tput el
    fi

    wait "$PID7zz"
    ST7zz=$?

    STATUSES=("${ST_PACK[@]}" "$ST7zz")

    trap - INT TERM HUP EXIT
    cleanup >/dev/null 2>&1 || true

    check_pipeline_tar_pv_7zz "${STATUSES[@]}"
}

tar_7zz() {
    tar --acls --xattrs -C "${SOURCE_PATH:h}" -cf - "${SOURCE_PATH:t}" 2>/dev/null | 7zz "${ZIP_OPTIONS[@]}" "$DESTINATION_PATH"
    if ! check_pipeline_tar_7zz "${pipestatus[@]}"; then
        echo "Exiting." >&2
        exit 1
    fi
}

prepare_a() {
    [[ $1 == "A" || $1 == "-A" || $1 == "-Archive" ]] && CONFIRMATION_NEEDED="false"
    if [[ $OPERATION == "none" ]]; then
        OPERATION="archive"
    else
        echo "Archive and unarchive options both selected. Exiting." >&2
        exit 1
    fi
}

prepare_u() {
    if [[ $1 == "U" || $1 == "-U" || $1 == "-Unarchive" ]] && CONFIRMATION_NEEDED="false"
    if [[ $OPERATION == "none" ]]; then
        OPERATION="unarchive"
    else
        echo "Archive and unarchive options both selected. Exiting." >&2
        exit 1
    fi
}

prepare_b() {
    SIZE_FORMAT="binary"
}

prepare_e() {
    echo "Error: -e/--encrypt option not yet implemented. Exiting." >&2
    exit 1
    ENCRYPTION_SPECIFIED="true"
    PASSWORD_SPECIFIED="false"
}

prepare_i() {
    PERFORM_INTEGRITY_CHECK="true"
}

prepare_f() {
    CHECK_FILE_SIZES="false"
}

prepare_s() {
    exec > /dev/null
    SILENT="true"
    prepare_f
}

### BEGINNING OF SCRIPT ####

# Ensure 7zz exists
if ! command -v 7zz >/dev/null 2>&1; then
	tput bold; echo "7zz not installed." >&2; tput sgr0
	echo "Install with: brew install sevenzip" >&2
	exit 1
fi

# Ensure pv exists
if ! command -v pv >/dev/null 2>&1; then
    tput bold; echo "pv not installed." >&2; tput sgr0
    echo "Install with: brew install pv" >&2
    exit 1
fi

OPERATION="none"
SOURCE_SPECIFIED="false"
DESTINATION_SPECIFIED="false"
CONFIRMATION_NEEDED="true"
DICTIONARY_SIZE=256
DICTIONARY_SIZE_SPECIFIED="false"
CHECK_FILE_SIZES="true"
ENCRYPTION_SPECIFIED="false"
PASSWORD_SPECIFIED="false"
THREADS="on"
THREADS_SPECIFIED="false"
PERFORM_INTEGRITY_CHECK="false"
SILENT="false"
SIZE_FORMAT="decimal"

while (( $# > 0 )); do
    ARG="$1"

    case $ARG in
		-h|--help)
			show_help
            exit 0
            ;;
		-a|--archive|-A|--Archive)
            prepare_a $ARG
			;;
		-u|--unarchive|-U|-Unarchive)
            prepare_u $ARG
			;;
        -b|--binary)
            prepare_b
            ;;
        -i|--integrity)
            prepare_i
            ;;
		-f|--fast)
            prepare_f
			;;
        -s|--silent)
            prepare_s
            ;;
		-e|--encrypt)
            prepare_e
			;;
		-E|--Encrypt)
            if [[ $ENCRYPTION_SPECIFIED == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (password)
					ARCHIVE_PASSWORD="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag encryption as specified
					ENCRYPTION_SPECIFIED="true"
					# Flag password as specified
					PASSWORD_SPECIFIED="true"
                else
                    echo "No password specified for -E/--Encrypt option. Exiting." >&2
                    exit 1
				fi
			else
				echo "Encryption specified multiple times. Exiting." >&2
				exit 1
			fi
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
                    echo "No dictionary size specified for -d/--dictionary option. Exiting." >&2
                    exit 1
				fi
			else
				echo "-d/--dictionary option specified multiple times. Exiting." >&2
				exit 1
			fi
			;;
        -t|--threads)
            if [[ $THREADS_SPECIFIED == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (number of threads)
                    THREADS="$2"
                    if [[ "$THREADS" == "auto" ]]; then
                        THREADS="on"
                    elif [[ ! ( "$THREADS" == "on" || ( "$THREADS" =~ ^[0-9]+$ && "$THREADS" -ge 1 ) ) ]]; then
                        printf "Error: %s is not a valid amount of threads. Exiting.\n" $THREADS >&2
                        exit 1
                    fi
                    # Skip the next argument in the next iteration
                    shift
                    # Flag number of threads as specified
                    THREADS_SPECIFIED="true"
                else
                    echo "No amount of threads specified for -t/--threads option. Exiting." >&2
                    exit 1
                fi
            else
                echo "-t/--threads option specified multiple times. Exiting." >&2
                exit 1
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
                    DESTINATION_SPECIFIED="folder"
                else
                    echo "No destination folder specified for -o/--output option. Exiting." >&2
                    exit 1
				fi
			else
				echo "Destination specified multiple times. Exiting." >&2
				exit 1
			fi
			;;
        -O|--Output)
            if [[ $DESTINATION_SPECIFIED == "false" ]]; then
                if (( $# > 1 )); then
                    if [[ "$2" == */* ]]; then
                        DESTINATION_DIR="${2:h}"
                        DESTINATION_FILE="${2:t}"
                        # Flag destination as file with path
                        DESTINATION_SPECIFIED="path_and_file"
                    else
                        DESTINATION_FILE="$2"
                        # Flag destination as just a file (without path)
                        DESTINATION_SPECIFIED="file"
                    fi
                    
                    # Skip the next argument in the next iteration
                    shift
                else
                    echo "No destination file specified for -O/--Output option. Exiting." >&2
                    exit 1
                fi
            else
                echo "Destination specified multiple times. Exiting." >&2
                exit 1
            fi
            ;;
		*)
			if [[ $ARG == -* ]]; then
                SIMPLE_ARGUMENTS=( ${(s::)${ARG:1}} )
                for SIMPLE_ARG in "${SIMPLE_ARGUMENTS[@]}"; do
                    case $SIMPLE_ARG in
                        h)
                            show_help
                            exit 0
                            ;;
                        a|A)
                            prepare_a $SIMPLE_ARG
                            ;;
                        u|U)
                            prepare_u $SIMPLE_ARG
                            ;;
                        b)
                            prepare_b
                            ;;
                        i)
                            prepare_i
                            ;;
                        f)
                            prepare_f
                            ;;
                        e)
                            prepare_e
                            ;;
                        s)
                            prepare_s
                            ;;
                        *)
                            echo "Error: Invalid argument detected: $SIMPLE_ARG in $ARG.\nExitng." >&2
                            exit 1
                            ;;
                    esac
                done
			else
                if [[ $SOURCE_SPECIFIED == "true" ]]; then
                    echo "Error: Multiple sources specified. Exiting." >&2
                    exit 1
                fi
                SOURCE_PATH="$1"
                SOURCE_SPECIFIED="true"
            fi
			;;
	esac

	# Move to the next argument
	shift
done

if [[ $OPERATION == "none" ]]; then
	echo "No operation was specified. Use -a/--archive or -u/--unarchive. Run $0 -h for help." >&2
	echo "Exiting." >&2
	exit 1
fi

if [[ $OPERATION == "unarchive" && ( $DESTINATION_SPECIFIED == "file" || $DESTINATION_SPECIFIED == "path_and_file" ) ]]; then
    echo "Output file name cannot be specified with -O/--Output for an unarchiving operation." >&2
    echo "Try using the -o/-output option to specify a folder to unarchive to." >&2
    echo "Exiting." >&2
    exit 1
fi

if [[ ! -e "$SOURCE_PATH" ]]; then
    echo "$SOURCE_PATH does not exist. Exiting." >&2
    exit 1
fi

[[ $DESTINATION_SPECIFIED == "false" || $DESTINATION_SPECIFIED == "file" ]] && DESTINATION_DIR="$PWD"

# Sanitize DESTINATION_DIR (remove trailing '/')
DESTINATION_DIR=${DESTINATION_DIR:a}
tput bold
if [[ $OPERATION == "archive" ]]; then
    [[ $DESTINATION_SPECIFIED == "folder" || $DESTINATION_SPECIFIED == "false" ]] && DESTINATION_FILE="${SOURCE_PATH:t}.tar.7z"
	DESTINATION_PATH="${DESTINATION_DIR:a}/$DESTINATION_FILE"
	printf "Archive ${SOURCE_PATH:t} to ${DESTINATION_PATH:t}\n"
else
    DESTINATION_PATH="${DESTINATION_DIR:a}/${${${SOURCE_PATH:t}%.tar.7z}%.7z}"
	printf "Unarchive ${SOURCE_PATH:t} to ${DESTINATION_DIR:t}\n"
fi
tput sgr0
[[ $DICTIONARY_SIZE_SPECIFIED == "true" ]] && printf "Dictionary:\t%d MB\n" $DICTIONARY_SIZE
if [[ $THREADS_SPECIFIED == "true" ]]; then
    if [[ "$THREADS" == "on" ]]; then
        printf "Threads:\tautomatic\n"
    else
        printf "Threads:\t%d\n" $THREADS
    fi
fi
printf "Source:\t\t%s\n" "$SOURCE_PATH"

if [[ $OPERATION == "archive" ]]; then
    printf "Destination:\t%s\n" "$DESTINATION_PATH"
else
    printf "Destination:\t%s\n" "$DESTINATION_DIR"
fi

if [[ $CHECK_FILE_SIZES == "true" ]]; then
	printf "Determining Source Size..."
	SOURCE_SIZE_BYTE=$(get_size $SOURCE_PATH)
	SOURCE_SIZE=$(to_human $SOURCE_SIZE_BYTE)
	tput cr; tput el
	printf "\rSource Size:\t$SOURCE_SIZE / $SOURCE_SIZE_BYTE bytes\n"
fi
if [[ -e $DESTINATION_PATH && $OPERATION == "archive" ]]; then
	DESTINATION_TYPE="$(object_type $DESTINATION_PATH)"
	if [[ $DESTINATION_TYPE == "file" ]]; then
		echo "Warning: ${DESTINATION_PATH:t} exists and will be overwritten."
	else
		echo "Warning: ${DESTINATION_PATH:t} exists and is not a file ($DESTINATION_TYPE). Exiting." >&2
		exit 1
	fi
fi
if [[ -e $DESTINATION_DIR && $OPERATION == "unarchive" ]]; then
	DESTINATION_TYPE="$(object_type $DESTINATION_DIR)"
	if [[ $DESTINATION_TYPE != "directory" ]]; then
		echo "Warning: ${DESTINATION_DIR:t} exists and is not a folder ($DESTINATION_TYPE). Exiting." >&2
		exit 1
	fi
fi

if [[ $ENCRYPTION_SPECIFIED == "true" && $PASSWORD_SPECIFIED == "false" && ! -t 0 && ! -e /dev/tty ]]; then
  echo "Warning: No TTY available for secure password prompt."
fi

if [[ $CONFIRMATION_NEEDED == "true" ]]; then
	read "?Confirm with 'y': " CONFIRMATION
	[[ $CONFIRMATION == "y" ]] || {
		echo "User confirmation negative. Exiting." >&2
		exit 1
	}
fi

echo "\nStarting time:\t$(date)"

if [[ -e $DESTINATION_PATH && $OPERATION == "archive" ]]; then
	printf "Deleting pre-existing ${DESTINATION_PATH:t}..."
	rm $DESTINATION_PATH
	tput cr; tput el
fi
mkdir -p "${DESTINATION_DIR:a}"
# Record start time (epoch seconds)
START_EPOCH=$(date +%s)

if [[ $OPERATION == "archive" ]]; then
    # Set 7zz options for compression
    ZIP_OPTIONS=(a -t7z -si -mx=9 -m0=lzma2 -md="${DICTIONARY_SIZE}m" -mmt="$THREADS" -bso0 -bsp0)
	if [[ $ENCRYPTION_SPECIFIED == "true" ]]; then
        ZIP_OPTIONS+=("-mhe=on")
		[[ $PASSWORD_SPECIFIED == "true" && -n "$ARCHIVE_PASSWORD" ]] && ZIP_OPTIONS+=("-p${ARCHIVE_PASSWORD}")
	fi
    # Archive
    if ! tar_pv_7zz_with_two_phase_progress; then
        echo "Exiting."
        exit 1
    fi
    
    if [[ $PERFORM_INTEGRITY_CHECK == "true" ]]; then
        # Set 7zz options for integrity check
        ZIP_OPTIONS=(t -bso0 -bsp1)
        if [[ $ENCRYPTION_SPECIFIED == "true" && $PASSWORD_SPECIFIED == "true" && -n "$ARCHIVE_PASSWORD" ]]; then
            ZIP_OPTIONS+=("-p${ARCHIVE_PASSWORD}")
        fi
        
        tput cr; tput el
        echo "Performing archive integrity check..."
        
        # Check archive integrity
        if ! 7zz "${ZIP_OPTIONS[@]}" "$DESTINATION_PATH" > /dev/null; then
            printf "\rArchive ${DESTINATION_PATH:t} integrity could not be verified. Exiting.\n" >&2
            exit 1
        fi
        # Clear current line and return carriage
        tput cr; tput el
        # Move one line up, clear and return carriage
        tput cuu1; tput cr; tput el
    fi
else
    # Set 7zz options for arhive readability check
    ZIP_OPTIONS=(l)
    if [[ $ENCRYPTION_SPECIFIED == "true" && $PASSWORD_SPECIFIED == "true" && -n "$ARCHIVE_PASSWORD" ]]; then
        ZIP_OPTIONS+=("-p${ARCHIVE_PASSWORD}")
    fi

	printf "Checking archive readability..."
	if ! 7zz "${ZIP_OPTIONS[@]}" "$SOURCE_PATH" > /dev/null 2>&1; then
		tput cr; tput el
		printf "\rArchive ${$SOURCE_PATH:t} could not be read. Exiting.\n" >&2
		exit 1
	fi
	tput cr; tput el
 
    # Set 7zz options for unarchiving
    ZIP_OPTIONS=(x -so -mmt="$THREADS")
    if [[ $ENCRYPTION_SPECIFIED == "true" && $PASSWORD_SPECIFIED == "true" && -n "$ARCHIVE_PASSWORD" ]]; then
        ZIP_OPTIONS+=("-p${ARCHIVE_PASSWORD}")
    fi
    
    # Set pv options for unarchiving
    PV_UNARCHIVE_OPTIONS=()
    [[ $SIZE_FORMAT == "decimal" ]] && PV_UNARCHIVE_OPTIONS+=(-k)
    PV_UNARCHIVE_OPTIONS+=(-s "$SOURCE_SIZE_BYTE" -N "${SOURCE_PATH:t}")
    
    # Unarchive
	7zz "${ZIP_OPTIONS[@]}" "$SOURCE_PATH" | pv "${PV_UNARCHIVE_OPTIONS[@]}" | tar --acls --xattrs -C "$DESTINATION_DIR" -xf -
	if ! check_pipeline_7zz_pv_tar "${pipestatus[@]}"; then
		echo "Exiting." >&2
		exit 1
	fi
fi

printf "\n"

if [[ $CHECK_FILE_SIZES == "true" ]]; then
    if [[ $OPERATION == "archive" ]]; then
        #tput cr; tput el
        printf "\rDetermining archive size..."
    else
        #tput cr; tput el
        printf "\rDetermining destination size..."
    fi
    
    DESTINATION_SIZE_BYTE=$(get_size $DESTINATION_PATH)
    DESTINATION_SIZE=$(to_human $DESTINATION_SIZE_BYTE)
    PERCENTAGE=$(( (DESTINATION_SIZE_BYTE * 100.0) / SOURCE_SIZE_BYTE ))
    
    if [[ $OPERATION == "archive" ]]; then
        tput cr; tput el
        printf "\rArchive Size:\t"
    else
        tput cr; tput el
        printf "\rDestin. Size:\t"
    fi
    printf "$DESTINATION_SIZE / $DESTINATION_SIZE_BYTE bytes (%.1f%%)\n" "$PERCENTAGE"
    
    SIZE_DIFFERENCE_BYTE=$(( DESTINATION_SIZE_BYTE - SOURCE_SIZE_BYTE ))
    SIZE_DIFFERENCE=$(to_human $SIZE_DIFFERENCE_BYTE)
    printf "Difference:\t$SIZE_DIFFERENCE / $SIZE_DIFFERENCE_BYTE bytes\n"
fi

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
