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
        local abs_size_bytes=$(( "$1" * -1 ))
        printf "-"
    else
        local abs_size_bytes="$1"
    fi
    
    if [[ $size_format == "binary" ]]; then
        echo $abs_size_bytes | awk '{
            split("B KiB MiB GiB TiB", unit);
            i=1;
            while($1>=1024 && i<5) { $1/=1024; i++ }
            printf "%.1f %s", $1, unit[i]
        }'
    else
        echo $abs_size_bytes | awk '{
            split("B KB MB GB TB", unit);
            i=1;
            while($1>=1000 && i<5) { $1/=1000; i++ }
            printf "%.1f %s", $1, unit[i]
        }'
    fi
}

get_size() {
    local target="$1"
    
    if [ -f "$target" ]; then
        # If it's a file, just get its size
        stat -f%z "$target"
    elif [ -d "$target" ]; then
        # If it's a directory, sum the size of all files inside recursively
        # -type f: looks only for files (ignoring directory metadata size)
        # -print0 / -0: handles filenames with spaces correctly
        find "$target" -type f -print0 | xargs -0 stat -f%z | awk '{s+=$1} END {print s+0}'
    else
        echo "Error: $target is not a valid file or directory" >&2
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

check_command() {
    local cmd="$1"
    local ret_val="$2"
    
    case $cmd in
        7zz)
            case $ret_val in
                0)
                    echo "No error (Success)"
                    ;;
                1)
                    echo "Warning (non-fatal error)"    ## For example, files were locked by another application during compression
                    ;;
                2)
                    echo "Fatal error"  # Check disk space or file permissions
                    ;;
                7)
                    echo "Command line error"   # Bad parameters
                    ;;
                8)
                    echo "Not enough memory"
                    ;;
                255)
                    echo "User stopped the process" # [ctrl]+[c] or similar
                    ;;
                *)
                    echo "Unknown"
                    ;;
            esac
            ;;
        pv)
            case $ret_val in
                0)
                    echo "No error (Success)"
                    ;;
                2)
                    echo "One or more files could not be accessed, stat(2)ed, or opened"
                    ;;
                4)
                    echo "An input file was the same as the output file"
                    ;;
                8)
                    echo "Internal error with closing a file or moving to the next file"
                    ;;
                16)
                    echo "There was an error while transferring data from one or more input files"
                    ;;
                32)
                    echo "A signal was caught that caused an early exit"
                    ;;
                64)
                    echo "Memory allocation failed"
                    ;;
                *)
                    echo "Unknown"
                    ;;
            esac
            ;;
        tar)
            case $ret_val in
                0)
                    echo "No error (Success)"
                    ;;
                1)
                    echo "Warning (some files differ, were busy, or couldn't be read, but the archive was still created)"
                    ;;
                2)
                    echo "Fatal Error (e.g., directory not found, disk full)"
                    ;;
                *)
                    echo "Unknown"
                    ;;
            esac
            ;;
        xz)
            case $ret_val in
                0)
                    echo "No error (Success)"
                    ;;
                1)
                    echo "Error"
                    ;;
                2)
                    echo "Warning"
                    ;;
                *)
                    echo "Unknown"
                    ;;
            esac
            ;;
        *)
            echo "Unknown command ($cmd)"
            ;;
    esac
}

# Usage: check_pipeline "${pipestatus[@]}"
check_pipeline() {
    local statuses=("$@")
    local exit_code=0
    local commands=()
    local command

    case $operation in
        archive)
            commands+="tar"
            commands+="pv"
            case $compression_software in
                xz)
                    commands+="xz"
                    ;;
                7zz)
                    commands+="7zz"
                    ;;
                *)
                    echo "Error: Invalid compression software: $compression_software" >&2
                    return 1
                    ;;
            esac
            ;;
        unarchive)
            case $compression_software in
                xz)
                    commands+="xz"
                    ;;
                7zz)
                    commands+="7zz"
                    ;;
                *)
                    echo "Error: Invalid compression software: $compression_software" >&2
                    return 1
                    ;;
            esac
            commands+="pv"
            commands+="tar"
            ;;
        *)
            echo "Error: Invalid operation: $operation" >&2
            return 1
            ;;
    esac
    
    for command in {1..$#commands}
    do
        if [[ ${statuses[$command]} -ne 0 ]]; then
            printf "\rError: Command ${commands[$command]} in pipeline failed with exit code ${statuses[$command]}: $(check_command ${commands[$command]} ${statuses[$command]})\n" >&2
            exit_code=1
        fi
    done

    return $exit_code
}

tar_pv_7zz_with_two_phase_progress() {
    emulate -L zsh
    setopt localtraps

    local tmpdir fifo PID7zz ST7zz
    local interrupted=0 packing=0
    local -a st_pack statuses st_pack_on_int
    local tar_options=(--acls --xattrs -C)

    tmpdir="$(mktemp -d -t tar7zz)" || return 1
    fifo="$tmpdir/stream.fifo"
    mkfifo "$fifo" || { rmdir "$tmpdir" 2>/dev/null; return 1; }

    cleanup() {
        local ec=$?
        [[ -n "${PID7zz:-}" ]] && kill -0 "$PID7zz" 2>/dev/null && kill "$PID7zz" 2>/dev/null
        rm -f "$fifo" 2>/dev/null
        rmdir "$tmpdir" 2>/dev/null
        return $ec
    }

    on_int() {
        interrupted=1
        # Only meaningful during the tar|pv pipeline. Otherwise $pipestatus is 1-element garbage
        if (( packing )); then
            st_pack_on_int=("${pipestatus[@]}")   # (tar, pv)
        fi
        [[ -n "${PID7zz:-}" ]] && kill -INT "$PID7zz" 2>/dev/null
        return 130
    }

    trap on_int INT
    trap cleanup TERM HUP EXIT

    pv_options=()
    [[ $size_format == "decimal" ]] && pv_options+=(-k)
    pv_options+=(-N "${source_path:t}" -s "$source_size_byte" "$pv_options_WITH_SIZE")
    [[ "$silent" == "true" ]] && pv_options+=(-q)

    7zz "${zip_options[@]}" "$destination_path" <"$fifo" &
    PID7zz=$!

    # Phase 1: tar -> pv -> FIFO
    packing=1
    { tar "${tar_options[@]}" "${source_path:h}" -cf - "${source_path:t}" 2>/dev/null | pv "${pv_options[@]}"; } > "$fifo"
    packing=0

    # Capture (tar,pv) reliably even if INT trap ran
    if (( interrupted )) && (( ${#st_pack_on_int[@]} == 2 )); then
        st_pack=("${st_pack_on_int[@]}")
    else
        st_pack=("${pipestatus[@]}")
    fi

    # Phase 2: spinner while 7zz is still compressing/writing
    if kill -0 "$PID7zz" 2>/dev/null; then
    local frames=('|' '/' '-' '\') i=1
    while kill -0 "$PID7zz" 2>/dev/null; do
        printf "\rFinishing compression… %s" "${frames[i]}" >&2
        i=$(( i % ${#frames} + 1 ))
        sleep 0.12
    done
    printf "\r" >&2
    tput el >&2
    fi

    wait "$PID7zz"
    ST7zz=$?

    statuses=("${st_pack[@]}" "$ST7zz")

    trap - INT TERM HUP EXIT
    cleanup >/dev/null 2>&1 || true

    check_pipeline "${statuses[@]}"
}

prepare_a() {
    [[ $1 == "A" || $1 == "-A" || $1 == "-Archive" ]] && confirmation_needed="false"
    if [[ $operation == "none" ]]; then
        operation="archive"
    else
        echo "Archive and unarchive options both selected. Exiting." >&2
        exit 1
    fi
}

prepare_u() {
    if [[ $1 == "U" || $1 == "-U" || $1 == "-Unarchive" ]] && confirmation_needed="false"
    if [[ $operation == "none" ]]; then
        operation="unarchive"
    else
        echo "Archive and unarchive options both selected. Exiting." >&2
        exit 1
    fi
}

prepare_b() {
    size_format="binary"
}

prepare_e() {
    echo "Error: -e/--encrypt option not yet implemented. Exiting." >&2
    exit 1
    encryption_specified="true"
    password_specified="false"
}

prepare_i() {
    perform_integrity_check="true"
}

prepare_f() {
    check_file_sizes="false"
}

prepare_s() {
    exec > /dev/null
    silent="true"
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

operation="none"
source_specified="false"
destination_specified="false"
confirmation_needed="true"
dictionary_size=256
dictionary_size_specified="false"
check_file_sizes="true"
encryption_specified="false"
password_specified="false"
threads="on"
threads_specified="false"
perform_integrity_check="false"
silent="false"
size_format="decimal"
pv_options_WITH_SIZE="-ptebar"
pv_options_without_size="-trab"
compression_software="7zz"

while (( $# > 0 )); do
    arg="$1"

    case $arg in
		-h|--help)
			show_help
            exit 0
            ;;
		-a|--archive|-A|--Archive)
            prepare_a $arg
			;;
		-u|--unarchive|-U|-Unarchive)
            prepare_u $arg
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
            if [[ $encryption_specified == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (password)
					archive_password="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag encryption as specified
					encryption_specified="true"
					# Flag password as specified
					password_specified="true"
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
            if [[ $dictionary_size_specified == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (dictionary size)
					dictionary_size="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag dictionary size as specified
					dictionary_size_specified="true"
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
            if [[ $threads_specified == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (number of threads)
                    threads="$2"
                    if [[ "$threads" == "auto" ]]; then
                        threads="on"
                    elif [[ ! ( "$threads" == "on" || ( "$threads" =~ ^[0-9]+$ && "$threads" -ge 1 ) ) ]]; then
                        printf "Error: %s is not a valid amount of threads. Exiting.\n" $threads >&2
                        exit 1
                    fi
                    # Skip the next argument in the next iteration
                    shift
                    # Flag number of threads as specified
                    threads_specified="true"
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
            if [[ $destination_specified == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (destination path)
					destination_dir="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag destination as specified
                    destination_specified="folder"
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
            if [[ $destination_specified == "false" ]]; then
                if (( $# > 1 )); then
                    if [[ "$2" == */* ]]; then
                        destination_dir="${2:h}"
                        destination_file="${2:t}"
                        # Flag destination as file with path
                        destination_specified="path_and_file"
                    else
                        destination_file="$2"
                        # Flag destination as just a file (without path)
                        destination_specified="file"
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
			if [[ $arg == -* ]]; then
                simple_arguments=( ${(s::)${arg:1}} )
                for simple_arg in "${simple_arguments[@]}"; do
                    case $simple_arg in
                        h)
                            show_help
                            exit 0
                            ;;
                        a|A)
                            prepare_a $simple_arg
                            ;;
                        u|U)
                            prepare_u $simple_arg
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
                            echo "Error: Invalid argument detected: $simple_arg in $arg.\nExitng." >&2
                            exit 1
                            ;;
                    esac
                done
			else
                if [[ $source_specified == "true" ]]; then
                    echo "Error: Multiple sources specified. Exiting." >&2
                    exit 1
                fi
                source_path="$1"
                source_specified="true"
            fi
			;;
	esac

	# Move to the next argument
	shift
done

if [[ $operation == "none" ]]; then
	echo "No operation was specified. Use -a/--archive or -u/--unarchive. Run $0 -h for help." >&2
	echo "Exiting." >&2
	exit 1
fi

if [[ $operation == "unarchive" && ( $destination_specified == "file" || $destination_specified == "path_and_file" ) ]]; then
    echo "Output file name cannot be specified with -O/--Output for an unarchiving operation." >&2
    echo "Try using the -o/-output option to specify a folder to unarchive to." >&2
    echo "Exiting." >&2
    exit 1
fi

if [[ ! -e "$source_path" ]]; then
    echo "$source_path does not exist. Exiting." >&2
    exit 1
fi

[[ $destination_specified == "false" || $destination_specified == "file" ]] && destination_dir="$PWD"

# Sanitize destination_dir (remove trailing '/')
destination_dir=${destination_dir:a}
tput bold
if [[ $operation == "archive" ]]; then
    [[ $destination_specified == "folder" || $destination_specified == "false" ]] && destination_file="${source_path:t}.tar.7z"
	destination_path="${destination_dir:a}/$destination_file"
	printf "Archive ${source_path:t} to ${destination_path:t}\n"
else
    destination_path="${destination_dir:a}/${${${source_path:t}%.tar.7z}%.7z}"
	printf "Unarchive ${source_path:t} to ${destination_dir:t}\n"
fi
tput sgr0
[[ $dictionary_size_specified == "true" ]] && printf "Dictionary:\t%d MB\n" $dictionary_size
if [[ $threads_specified == "true" ]]; then
    if [[ "$threads" == "on" ]]; then
        printf "Threads:\tautomatic\n"
    else
        printf "Threads:\t%d\n" $threads
    fi
fi
printf "Source:\t\t%s\n" "$source_path"

if [[ $operation == "archive" ]]; then
    printf "Destination:\t%s\n" "$destination_path"
else
    printf "Destination:\t%s\n" "$destination_dir"
fi

if [[ $check_file_sizes == "true" ]]; then
	printf "Determining Source Size..."
	source_size_byte=$(get_size $source_path)
	source_size=$(to_human $source_size_byte)
	tput cr; tput el
	printf "\rSource Size:\t$source_size / $source_size_byte bytes\n"
fi
if [[ -e $destination_path && $operation == "archive" ]]; then
	destination_type="$(object_type $destination_path)"
	if [[ $destination_type == "file" ]]; then
		echo "Warning: ${destination_path:t} exists and will be overwritten."
	else
		echo "Warning: ${destination_path:t} exists and is not a file ($destination_type). Exiting." >&2
		exit 1
	fi
fi
if [[ -e $destination_dir && $operation == "unarchive" ]]; then
	destination_type="$(object_type $destination_dir)"
	if [[ $destination_type != "directory" ]]; then
		echo "Warning: ${destination_dir:t} exists and is not a folder ($destination_type). Exiting." >&2
		exit 1
	fi
fi

if [[ $encryption_specified == "true" && $password_specified == "false" && ! -t 0 && ! -e /dev/tty ]]; then
  echo "Warning: No TTY available for secure password prompt."
fi

if [[ $confirmation_needed == "true" ]]; then
	read "?Confirm with 'y': " confirmation
	[[ $confirmation == "y" ]] || {
		echo "User confirmation negative. Exiting." >&2
		exit 1
	}
fi

# Display starting time
echo "\nStart:\t\t$(date)"

if [[ -e $destination_path && $operation == "archive" ]]; then
	printf "Deleting pre-existing ${destination_path:t}..."
	rm $destination_path
	tput cr; tput el
fi
mkdir -p "${destination_dir:a}"
# Record start time (epoch seconds)
start_epoch=$(date +%s)

if [[ $operation == "archive" ]]; then
    # Set 7zz options for compression
    zip_options=(a -t7z -si -mx=9 -m0=lzma2 -md="${dictionary_size}m" -mmt="$threads" -bso0 -bsp0)
	if [[ $encryption_specified == "true" ]]; then
        zip_options+=("-mhe=on")
		[[ $password_specified == "true" && -n "$archive_password" ]] && zip_options+=("-p${archive_password}")
	fi
    # Archive
    if ! tar_pv_7zz_with_two_phase_progress; then
        echo "Exiting."
        exit 1
    fi
    
    if [[ $perform_integrity_check == "true" ]]; then
        # Set 7zz options for integrity check
        zip_options=(t -bso0 -bsp1)
        if [[ $encryption_specified == "true" && $password_specified == "true" && -n "$archive_password" ]]; then
            zip_options+=("-p${archive_password}")
        fi
        
        tput cr; tput el
        echo "Performing archive integrity check..."
        
        # Check archive integrity
        if ! 7zz "${zip_options[@]}" "$destination_path" > /dev/null; then
            printf "\rArchive ${destination_path:t} integrity could not be verified. Exiting.\n" >&2
            exit 1
        fi
        # Clear current line and return carriage
        tput cr; tput el
        # Move one line up, clear and return carriage
        tput cuu1; tput cr; tput el
    fi
else
    # Set 7zz options for arhive readability check
    zip_options=(l)
    if [[ $encryption_specified == "true" && $password_specified == "true" && -n "$archive_password" ]]; then
        zip_options+=("-p${archive_password}")
    fi

	printf "Checking archive readability..."
	if ! 7zz "${zip_options[@]}" "$source_path" > /dev/null 2>&1; then
		tput cr; tput el
		printf "\rArchive ${$source_path:t} could not be read. Exiting.\n" >&2
		exit 1
	fi
	tput cr; tput el
 
    # Set 7zz options for unarchiving
    zip_options=(x -so -mmt="$threads")
    if [[ $encryption_specified == "true" && $password_specified == "true" && -n "$archive_password" ]]; then
        zip_options+=("-p${archive_password}")
    fi
    
    # Set pv options for unarchiving
    pv_options=()
    [[ $size_format == "decimal" ]] && pv_options+=(-k)
    pv_options+=(-N "${source_path:t}")
    if [[ $check_file_sizes == "true" ]]; then
        pv_options+=(-s "$source_size_byte" "$pv_options_WITH_SIZE")
    else
        pv_options+=("$pv_options_without_size")
    fi
    
    # Unarchive
	7zz "${zip_options[@]}" "$source_path" | pv "${pv_options[@]}" | tar --acls --xattrs -C "$destination_dir" -xf -
	if ! check_pipeline "${pipestatus[@]}"; then
		echo "Exiting." >&2
		exit 1
	fi
fi

if [[ $check_file_sizes == "true" ]]; then
    if [[ $operation == "archive" ]]; then
        #tput cr; tput el
        printf "\rDetermining archive size..."
    else
        #tput cr; tput el
        printf "\rDetermining destination size..."
    fi
    destination_size_byte=$(get_size $destination_path)
    destination_size=$(to_human $destination_size_byte)
    percentage=$(( (destination_size_byte * 100.0) / source_size_byte ))
    tput cr; tput el
fi

# Display finishing time
echo "Finish:\t\t$(date)\n"

# Record end time (epoch seconds)
end_epoch=$(date +%s)

if [[ $check_file_sizes == "true" ]]; then
    if [[ $operation == "archive" ]]; then
        printf "Archive Size:\t"
    else
        tput cr; tput el
        printf "Destin. Size:\t"
    fi
    printf "$destination_size / $destination_size_byte bytes\n"
    size_difference_byte=$(( destination_size_byte - source_size_byte ))
    size_difference=$(to_human $size_difference_byte)
    printf "Difference:\t$size_difference / $size_difference_byte bytes (%.1f%%)\n" "$percentage"
fi

# Calculate elapsed time
elapsed=$((end_epoch - start_epoch))
days=$((elapsed / 86400))
remainder=$((elapsed % 86400))
hours=$((remainder / 3600))
remainder=$((remainder % 3600))
minutes=$((remainder / 60))
seconds=$((remainder % 60))

# Print formatted duration
if (( days > 0 )); then
	printf "Elapsed time:\t${days}d ${hours}h ${minutes}m ${seconds}s\n"
elif (( hours > 0 )); then
	printf "Elapsed time:\t${hours}h ${minutes}m ${seconds}s\n"
elif (( minutes > 0 )); then
	printf "Elapsed time:\t${minutes}m ${seconds}s\n"
else
	printf "Elapsed time:\t${seconds}s\n"
fi

echo "klolthxbye"
