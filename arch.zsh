#!/usr/bin/env zsh

script_dir="${0:A:h}"
source "$script_dir/lib/ar-lib.zsh"

emulate -L zsh
setopt nounset
setopt pipefail

show_help() {
  cat << 'EOF'
NAME
    arch.sh — archive or unarchive .tar.xz files

SYNOPSIS
    arch.sh [-a | -u] [-o destination] input_path
    arch.sh -h | --help

DESCRIPTION
    arch.sh archives or unarchives files using tar and xz
    piped together, avoiding the creation of intermediate .tar
    files.

    The input_path specifies either the file, folder, or package
    to be archived, or the .tar.xz archive to be unarchived.

    Options may be specified in any order.

OPTIONS
    -h, --help
        Display this help and exit. All other arguments
        are ignored.

    -a, --archive, -A, --Archive
        Archive input_path into a .tar.xz file.
        Skip user confirmation if -A or --Archive is specified.

    -u, --unarchive, -U, --Unarchive
        Unarchive input_path, which must be a .tar.xz file.
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
 
     -p, --prior
        When overwriting existing archives, delete the pre-existing
        archive prior to creating the new archive.
        
        If omitted, the pre-existing archive will only be deleted
        after the new one has been created.
 
    -s, --silent
        Disable all output to stdout. File size checks are also
        skipped if this option is specified (as they would not
        be visible anyways).
        
        Error messages are still written to stderr.

    -e, --encrypt
        CURRENTLY NOT IMPLEMENTED
    
        Use SHA-256 to encrypt the archive. The user will be asked
        to enter the password during runtime.
        
    -E password, --Encrypt password
        CURRENTLY NOT IMPLEMENTED
    
        Use SHA-256 to encrypt the archive using the password
        specified in the next argument. This method is highly
        insecure and not reccommended.
        
        i.e. -E p55w0rd or --Encrypt pa55w0rd

    -d size, --dictionary size
        Set a custom dictionary size (in MiB) for compression.
        
        If not specified, a dictionary size of 256MiB will be used.
  
    -t threads, --threads threads
        Set a custom number of threads for compression.
        This must be an integer greater than 1.
        
        If not specified, the automatic setting will be used.

    -o destination, --output destination
        Specify the destination directory.

        When archiving, the resulting .tar.xz file is written
        to this directory.

        When unarchiving, the archive contents are extracted
        into this directory.

        If not specified, the current working directory is used.
        
    -O file_name, --Output file_name
        Specify the output file name for archiving.

        The resulting .tar.xz file is written
        to this directory.
        
        This option only applies to archiving. The program will
        exit with an error if specified for an unarchiving operation.

        If nothing is specified, the resulting archive will have the
        same name as the source file or folder, but with a ".tar.xz"
        postfix.

OPERANDS
    input_path
        Path to the file, folder, or package to archive, or
        the .tar.xz file to unarchive.

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
    dictionary size of 128MiB:
        arch.sh -a MyFile.txt -d 128

    Archive a file to a specific directory with a specific name:
        arch.sh --archive file.txt -O ~/Archives/foofile.txt.tar.xz

    Unarchive into the current directory and show file sizes in binary
    format:
        arch.sh -ub backup.tar.xz

    Unarchive into a specific directory and skip file size checks:
        arch.sh -uf backup.tar.xz -o ./output

EOF
}

check_archive_integrity() {
    xz -t -- "$1" > /dev/null
}

restore_stdout_progress() {
    # Temporarily restore output to stdout if only progress should be shown
    exec >&3
}

silence_stdout() {
    # Silence output to stdout if only progress should be shown
    exec > /dev/null
}

not_yet_implemented() {
    echo "Error: $1 not yet implemented. Exiting." >&2
    exit 1
}

prepare_a() {
    [[ $1 == "A" || $1 == "-A" || $1 == "--Archive" ]] && confirmation_needed="false"
    if [[ $operation == "none" ]]; then
        operation="archive"
    else
        echo "Archive and unarchive options both selected. Exiting." >&2
        exit 1
    fi
}

prepare_u() {
    [[ $1 == "U" || $1 == "-U" || $1 == "--Unarchive" ]] && confirmation_needed="false"
    if [[ $operation == "none" ]]; then
        operation="unarchive"
    else
        echo "Archive and unarchive options both selected. Exiting." >&2
        exit 1
    fi
}

prepare_e() {
    not_yet_implemented "-e/--encrypt option"
    encryption_specified="true"
    password_specified="false"
}

prepare_i() {
    perform_integrity_check="true"
}

prepare_f() {
    if [[ $check_file_sizes == "true" ]]; then
        check_file_sizes="false"
    else
        echo "Error: -F and -f options both selected. Exiting." >&2
        exit 1
    fi
}

prepare_F() {
    if [[ $check_file_sizes == "true" ]]; then
        check_file_sizes="source"
    else
        echo "Error: -F and -f options both selected. Exiting." >&2
        exit 1
    fi
}

prepare_p() {
    delete_before_compressing="true"
}

prepare_verbosity() {
    # Set verbosity according to argument
    verbosity="$1"
    
    case $verbosity in
        normal)     # No preparation necessary
            ;;
        progress)
            # Save original stdout (FD 1) into FD 3
            exec 3>&1
            # Silence stdout
            silence_stdout
            prepare_F
            ;;
        silent)
            # Silence stdout
            silence_stdout
            # Prevent file sizes from being calculated (they won't be shown in silent mode anyways)
            prepare_f
            ;;
        verbose)    # No preparation necessary
            ;;
        *)
            exit_invalid_vebosity "$verbosity"
            ;;
    esac
}

### BEGINNING OF SCRIPT ####

operation="none"
source_specified="false"
verbosity_specified="false"
source_paths=()
destination_specified="false"
dictionary_size=256
dictionary_size_specified="false"
encryption_specified="false"
password_specified="false"
threads_specified="false"
perform_integrity_check="false"
delete_before_compressing="false"
script_options=()

typeset -a pipe_status

while (( $# > 0 )); do
    arg="$1"

    case $arg in
		-h|--help)
			show_help
            exit 0
            ;;
		-a|--archive|-A|--Archive)
            prepare_a $arg
            script_options+=("$arg")
			;;
		-u|--unarchive|-U|--Unarchive)
            prepare_u $arg
            script_options+=("$arg")
			;;
        -b|--binary)
            prepare_b
            script_options+=("$arg")
            ;;
        -i|--integrity)
            prepare_i
            script_options+=("$arg")
            ;;
		-f|--fast)
            prepare_f
            script_options+=("$arg")
			;;
        -F|--Fast)
            prepare_F
            script_options+=("$arg")
            ;;
        -p|--prior)
            prepare_p
            script_options+=("$arg")
            ;;
		-e|--encrypt)
            prepare_e
            script_options+=("$arg")
			;;
		-E|--Encrypt)
            not_yet_implemented "-E/--Encrypt option"
            script_options+=("$arg")
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
            script_options+=("$arg")
            if [[ $dictionary_size_specified == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (dictionary size in MiB)
					dictionary_size="$2"
                    if [[ ! "$dictionary_size" =~ ^[1-9][0-9]*$ ]]; then
                        printf "Error: %s is not a valid dictionary size. Exiting.\n" $dictionary_size >&2
                        exit 1
                    fi
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
            script_options+=("$arg")
            if [[ $threads_specified == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (number of threads)
                    threads="$2"
                    if [[ ! "$threads" =~ ^[1-9][0-9]*$ ]]; then
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
            script_options+=("$arg")
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
            script_options+=("$arg")
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
        -v|--verbosity)
            script_options+=("$arg")
            if [[ $verbosity_specified == "false" ]]; then
                if (( $# > 1 )); then
                    # Prepare specified verbosity level
                    prepare_verbosity "$2"
                    # Skip the next argument in the next iteration
                    shift
                    # Flag verbosity as specified
                    verbosity_specified="true"
                else
                    echo "No verbosity level specified for -v/--verbosity option. Exiting." >&2
                    exit 1
                fi
            else
                echo "Verbosity specified multiple times. Exiting." >&2
                exit 1
            fi
            ;;
        -*)
            simple_arguments=( ${(s::)${arg:1}} )
            for simple_arg in "${simple_arguments[@]}"; do
                case $simple_arg in
                    h)
                        show_help
                        exit 0
                        ;;
                    a|A)
                        prepare_a $simple_arg
                        script_options+=("-$simple_arg")
                        ;;
                    u|U)
                        prepare_u $simple_arg
                        script_options+=("-$simple_arg")
                        ;;
                    b)
                        prepare_b
                        script_options+=("-$simple_arg")
                        ;;
                    i)
                        prepare_i
                        script_options+=("-$simple_arg")
                        ;;
                    f)
                        prepare_f
                        script_options+=("-$simple_arg")
                        ;;
                    F)
                        prepare_F
                        script_options+=("-$simple_arg")
                        ;;
                    p)
                        prepare_p
                        script_options+=("-$simple_arg")
                        ;;
                    e)
                        prepare_e
                        script_options+=("-$simple_arg")
                        ;;
                    *)
                        echo "Error: Invalid argument detected: $simple_arg in $arg.\nExitng." >&2
                        exit 1
                        ;;
                esac
            done
            ;;
		*)
            source_paths+=("$1")
            source_specified="true"
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

if [[ $operation != "archive" && $delete_before_compressing == "true" ]]; then
    echo "-p/--prior option only applies to archiving. Exiting." >&2
    exit 1
fi

check_dependency "xz" "pv" || exit 1

for (( item=1; item<=$#source_paths; item++ )); do
    if [[ ! -e "$source_paths[$item]" ]]; then
        echo "$source_paths[$item] does not exist. Exiting." >&2
        exit 1
    fi
done

[[ $destination_specified == "false" || $destination_specified == "file" ]] && destination_dir="$PWD"

# Sanitize destination_dir (remove trailing '/')
destination_dir=${destination_dir:a}

# Set source description. Use item name if one item, or "N source items" for multiple
if [[ $#source_paths == 1 ]]; then
    source_description="${source_paths[1]:t}"
else
    source_description="${#source_paths} source items"
fi

tput bold
if [[ $operation == "archive" ]]; then
    if [[ $destination_specified == "folder" || $destination_specified == "false" ]]; then
        if [[ $#source_paths == 1 ]]; then
            destination_file="${source_paths:t}.tar.xz"
        else
            destination_file="archive.tar.xz"
        fi
    fi
	destination_path="${destination_dir:a}/$destination_file"
    printf "Archive $source_description to ${destination_path:t}\n"
else    # operation: unarchive
    printf "Unarchive $source_description to ${destination_dir:t}\n"
fi
tput sgr0

if [[ $#source_paths > 1 && $verbosity == "verbose" ]]; then
    for (( item=1; item<=$#source_paths; item++ )); do
        printf "\t${source_paths[$item]}\n"
    done
fi

[[ $verbosity == "verbose" ]] && echo "Options:\t${script_options[@]}"

[[ $dictionary_size_specified == "true" ]] && printf "Dictionary:\t%d MiB\n" $dictionary_size
if [[ $threads_specified == "true" ]]; then
    if [[ $threads == "on" ]]; then
        printf "Threads:\tautomatic\n"
    else
        printf "Threads:\t%d\n" $threads
    fi
fi

printf "Source:\t\t"
if [[ $#source_paths == 1 ]]; then
    printf "${source_paths[1]}\n"
else
    printf "$source_description\n"
fi

if [[ $operation == "archive" ]]; then
    printf "Destination:\t%s\n" "$destination_path"
else
    printf "Destination:\t%s/\n" "$destination_dir"
fi

if [[ $check_file_sizes == "true" || $check_file_sizes == "source" ]]; then
    [[ $verbosity == "progress" ]] && restore_stdout_progress
	printf "Determining Source Size..."
    typeset -i total_source_size_byte=0
    source_size_byte=()
    for (( item=1; item<=$#source_paths; item++ )); do
        source_size_byte[$item]=$(get_size "$source_paths[$item]")
        (( total_source_size_byte += $source_size_byte[$item] ))
    done
	source_size=$(to_human $total_source_size_byte)
	tput cr; tput el
    [[ $verbosity == "progress" ]] && silence_stdout
	printf "\rSource Size:\t$source_size / $total_source_size_byte bytes\n"
fi
if [[ $operation == "archive" && -e $destination_path ]]; then
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
		echo "Warning: ${destination_dir:t} exists and is not a folder (is $destination_type). Exiting." >&2
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

if [[ $operation == "archive" ]]; then
    mkdir -p "${destination_dir:a}"
else
    mkdir -p "$destination_dir"
fi
# Record start time (epoch seconds)
start_epoch=$(date +%s)

if [[ $operation == "archive" ]]; then
    xz_options=(
        --lzma2=dict="${dictionary_size}MiB"
        --quiet
    )
    [[ $threads_specified == "true" ]] && xz_options+=(--threads="$threads")
    tar_options=(--acls --xattrs)
    pv_options=()
    [[ $size_format == "decimal" ]] && pv_options+=(-k) # This needs to be specified before all other options
    if [[ $check_file_sizes == "true" || $check_file_sizes == "source" ]]; then
        pv_options+=("$pv_options_WITH_SIZE" -s "$total_source_size_byte")
    else
        pv_options+=("$pv_options_without_size")
    fi
    pv_options+=(-N "$source_description")
    [[ "$verbosity" == "silent" ]] && pv_options+=(-q)
    
    [[ "$verbosity" == "progress" ]] && restore_stdout_progress
    
    if [[ $delete_before_compressing == "true" && -e $destination_path ]]; then
        show_delete "pre-existing ${destination_path:t}" "$destination_path"
        tput cr; tput el
    fi
    
    tmp="${destination_path}.part.$$"
    
    tar_names=()
    for source_path in "${source_paths[@]}"; do
        local item_name="${source_path:t}"
        [[ $item_name == -* ]] && item_name="./$item_name"   # protects names like "-weird"
        tar_names+=(-C "${source_path:h}" "$item_name")
    done
    
    cancel_archiving() {
        trap - INT TERM HUP
        
        # Kill the pipeline processes (children of this shell), but NOT this shell.
        pkill -TERM -P $$ 2>/dev/null
        # give them a moment; then be firm if needed
        sleep 0.2
        pkill -KILL -P $$ 2>/dev/null
        
        show_delete "temporary directory" "$tmp"
        exit 1
    }

    trap cancel_archiving INT TERM HUP

    tar "${tar_options[@]}" -cf - "${tar_names[@]}" 2>/dev/null \
    | pv "${pv_options[@]}" \
    | xz "${xz_options[@]}" >| "$tmp"
    
    pipe_status=( "${pipestatus[@]}" )

    trap - INT TERM HUP
    
    if ! check_pipeline "${pipe_status[@]}"; then
        echo "Exiting."
        [[ -e "$tmp" ]] && show_delete "temporary directory" "$tmp"
        exit 1
    fi
    
    mv -f -- "$tmp" "$destination_path"
    
    if [[ $perform_integrity_check == "true" ]]; then
        tput cr; tput el
        echo "Performing archive integrity check..."
        
        # Check archive integrity
        if ! check_archive_integrity "$destination_path"; then
            printf "\rArchive ${destination_path:t} integrity could not be verified. Exiting.\n" >&2
            exit 1
        fi
        
        # Clear current line and return carriage
        tput cr; tput el
        # Move one line up, clear and return carriage
        tput cuu1; tput cr; tput el
    fi
else    # Unarchive
    if [[ $perform_integrity_check == "true" ]]; then
        [[ $verbosity == "progress" ]] && restore_stdout_progress
        printf "Checking archive readability..."
        for (( item=1; item<=$#source_paths; item++ )); do
            if ! check_archive_integrity "$source_paths[$item]"; then
                tput cr; tput el
                printf "\rArchive ${$source_paths[$item]:t} could not be read. Exiting.\n" >&2
                exit 1
            fi
        done
    fi

	tput cr; tput el
 
    # Set xz options for unarchiving
    xz_options=(-dc)
    [[ $threads_specified == "true" ]] && xz_options+=(-T"$threads")
    
    # Set pv options for unarchiving
    pv_options=()
    [[ $size_format == "decimal" ]] && pv_options+=(-k)
    if [[ $check_file_sizes == "true" || $check_file_sizes == "source" ]]; then
        pv_options+=("$pv_options_WITH_SIZE")
    else
        pv_options+=("$pv_options_without_size")
    fi
    [[ $verbosity == "silent" ]] && pv_options+=(-q)
    
    cancel_unarchiving() {
        trap - INT TERM HUP
        
        # Remove temporary list of output files
        [[ -e "$list_tmp" ]] && rm -f -- "$list_tmp"
        # Kill the pipeline processes (children of this shell), but NOT this shell.
        pkill -TERM -P $$ 2>/dev/null
        # give them a moment; then be firm if needed
        sleep 0.2
        pkill -KILL -P $$ 2>/dev/null
        exit 1
    }
    
    # Start an empty array to store the extracted file names
    extracted_list=()

    trap cancel_unarchiving INT TERM HUP
    
    for (( item=1; item<=$#source_paths; item++ )); do
        # Create temporary file for tar to write output files names to
        if ! list_tmp=$(mktemp); then
            echo "Error: could not create temporary file list_tmp. Exiting." &>2
            exit 1
        fi
        pv_size=()
        [[ ( $verbosity == "normal" || $verbosity == "verbose" ) && $check_file_sizes != "false" ]] \
        && pv_size+=(-s "$source_size_byte[$item]")
        # Unarchive
        pv "${pv_options[@]}" "$pv_size[@]" -N "${source_paths[$item]:t}" < "$source_paths[$item]" \
        | xz "${xz_options[@]}" \
        | tar --acls --xattrs -C "$destination_dir" -xvf - 2>"$list_tmp"
        
        if ! check_pipeline "${pipestatus[@]}"; then
            rm -f -- "$list_tmp"
            # Clean up temp dirs?
            echo "Exiting." >&2
            exit 1
        fi
        extracted_list+=("${(@f)$(<"$list_tmp")}")
        rm -f -- "$list_tmp"
    done
    trap - INT TERM HUP
    extracted_list=("${(@)extracted_list/#x /}")                # remove "x "
    extracted_list=("${(@)extracted_list/#.\//}")               # remove leading "./"
    extracted_list=("${(@)extracted_list/#/$destination_dir/}") # prepend destination
fi

[[ $verbosity == "progress" ]] && silence_stdout

if [[ $check_file_sizes == "true" && $verbosity != "progress" ]]; then
    if [[ $operation == "archive" ]]; then
        tput cr; tput el
        printf "\rDetermining archive size..."
        destination_size_byte=$(get_size "$destination_path")
    else
        tput cr; tput el
        printf "\rDetermining destination size..."
        destination_size_byte=0
        for (( item=1; item<=$#extracted_list; item++ )); do
            [[ $(object_type "$extracted_list[$item]") != "directory" ]] && (( destination_size_byte += $(get_size "$extracted_list[$item]") ))
        done
    fi
    
    destination_size=$(to_human $destination_size_byte)
    tput cr; tput el
fi

# Display finishing time
echo "Finish:\t\t$(date)"

# Record end time (epoch seconds)
end_epoch=$(date +%s)

# Show size difference between source and archive
if [[ $check_file_sizes == "true" && $verbosity != "progress" ]]; then
    if [[ $operation == "archive" ]]; then
        destination_description="${destination_path:t}"
    else
        if [[ $#extracted_list == 1 ]]; then
            destination_description=${extracted_list[1]:t}
        else
            destination_description="${#extracted_list} extracted items"
        fi
    fi
    printf "\n"
    compare_sizes "$source_description" $total_source_size_byte "$destination_description" $destination_size_byte
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
printf "\nElapsed time:\t"
if (( days > 0 )); then
    printf "${days}d ${hours}h ${minutes}m ${seconds}s\n"
elif (( hours > 0 )); then
    printf "${hours}h ${minutes}m ${seconds}s\n"
elif (( minutes > 0 )); then
    printf "${minutes}m ${seconds}s\n"
else
    printf "${seconds}s\n"
fi
