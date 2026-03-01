#!/usr/bin/env zsh

setopt pipefail

show_help() {
    echo "I like turtles."
}

show_arch_help() {
    ./arch.zsh -h
    exit 1
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
            if(i==1) { printf "%d %s", $1, unit[i] }
            else { printf "%.1f %s", $1, unit[i] }
        }'
    else
        echo $abs_size_bytes | awk '{
            split("B KB MB GB TB", unit);
            i=1;
            while($1>=1000 && i<5) { $1/=1000; i++ }
            if(i==1) { printf "%d %s", $1, unit[i] }
            else { printf "%.1f %s", $1, unit[i] }
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

is_less_than_kB() {

    if [[ $size_format == "binary" ]]; then
        local kB_in_bytes=1024
    else
        local kB_in_bytes=1000
    fi
    
    if (( $1 < $kB_in_bytes )); then
        echo "true"
    else
        echo "false"
    fi
}

compare_sizes() {
    # First item (A)
    local name_A="$1"
    local bytes_A="$2"
    local human_A="$(to_human $bytes_A)"
    # Second item (B)
    local name_B="$3"
    local bytes_B="$4"
    local human_B="$(to_human $bytes_B)"
    # Difference
    local difference_bytes=$(( bytes_B - bytes_A ))
    
    local difference_human="$(to_human $difference_bytes)"
    # Absolute of difference
    if (( "$difference_bytes" < 0 )); then
        local abs_difference_bytes=$(( "$difference_bytes" * -1 ))
    else
        local abs_difference_bytes="$difference_bytes"
    fi
    local abs_difference_human="$(to_human $abs_difference_bytes)"
    
    local byte_unit_spaces="  "
    
    # Print names
    echo "$name_A vs. $name_B"
    
    # Find the lengths of the longest name, size (in bytes) and size (in human readable form)
    local item_names=( "$name_A" "$name_B" )
    local item_sizes=( "$bytes_A" "$bytes_B" )
    local item_human=( "$human_A" "$human_B" )
    local longest_item_name_length=0
    local longest_size_length=0
    local longest_human_length=0
    for (( n=1; n<=$#item_names; n++ )); do
        (( ${#item_names[$n]} > longest_item_name_length )) && longest_item_name_length=${#item_names[$n]}
        (( ${#item_sizes[$n]} > longest_size_length )) && longest_size_length=${#item_sizes[$n]}
        (( ${#item_human[$n]} > longest_human_length )) && longest_human_length=${#item_human[$n]}
    done
    
    # Check if the byte length might be longer than 7 characters in binary mode. This is for alignment.
    # 7 being the length of the shortest possible humand readable form larger or equal to 1KB/KiB, like "1.0 MiB"
    if [[ $size_format == "binary" && $longest_human_length == 7 ]]; then
        for (( n=1; n<=$#item_sizes; n++ )); do
            if (( $item_sizes[$n] >= 1000 )); then
                longest_human_length=8
                byte_unit_spaces="$byte_unit_spaces "
                break
            fi
        done
    fi
    
    for (( n=1; n<=$#item_names; n++ )); do
        if [[ $(is_less_than_kB "${item_sizes[n]}") == "true" ]]; then
            if [[ $size_format == "binary" ]]; then
                (( ${item_sizes[n]} < 1000 )) && byte_unit_spaces="$byte_unit_spaces "
                byte_size_length=$((longest_human_length - 4))
            else
                byte_size_length=$((longest_human_length - 3))
            fi
            human_size=$(printf "%+${byte_size_length}s%sB" "${item_sizes[n]}" "$byte_unit_spaces")
        else
            human_size=$(printf "%+${longest_human_length}s" "${item_human[n]}")
        fi
        printf "%-${longest_item_name_length}s : %s (%+${longest_size_length}s bytes)\n" "${item_names[n]}" "$human_size" "${item_sizes[n]}"
    done
 
    # Print comparison / difference
    printf "$name_B is "
    if (( $difference_bytes == 0 )); then
        printf "the same size as $name_A\n"
    elif (( $difference_bytes < 0 )); then
        printf "$abs_difference_human smaller (-"
    else
        printf "$abs_difference_human larger (+"
    fi
    (( $difference_bytes != 0 )) && printf "%.1f%%)\n" $(( ( 100.0 * abs_difference_bytes ) / bytes_A ))
}

object_type() {
    if [[ ! -e "$1" && ! -L "$1" ]]; then
        echo "nonexistent"    # Object does not exist
    elif [[ -L "$1" ]]; then
        echo "symlink"        # Symlink
    elif [[ -d "$1" ]]; then
        echo "directory"    # Folder (Directory)
    elif [[ -f "$1" ]]; then
        echo "file"            # File
    elif [[ -S "$1" ]]; then
        echo "socket"        # Socket
    elif [[ -p "$1" ]]; then
        echo "pipe"            # Named pipe (FIFO)
    elif [[ -b "$1" ]]; then
        echo "block"        # Block device
    elif [[ -c "$1" ]]; then
        echo "character"    # Character device
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
        *)
            echo "Unknown pipe command: $cmd"
            ;;
    esac
}

# Usage: check_pipeline "${pipestatus[@]}"
check_pipeline() {
    local statuses=("$@")
    local exit_code=0
    local commands=(7zz pv tar)
    local pipe_command
    
    for pipe_command in {1..$#commands}
    do
        if [[ ${statuses[$pipe_command]} -ne 0 ]]; then
            printf "\rError: Command ${commands[$pipe_command]} in pipeline failed with exit code ${statuses[$pipe_command]}: $(check_command ${commands[$pipe_command]} ${statuses[$pipe_command]})\n" >&2
            exit_code=1
        fi
    done

    return $exit_code
}

check_directory() {
    if [[ -e "$1" ]]; then
        if [[ "$(object_type "$1")" != "directory" ]]; then
            echo "Error: Specified $2 not a directory ($1).\nExiting." >&2
            exit 1
        fi
    else
        # Return 1 if directory does not exist
        return 1
    fi
    # Return 0 if the directory exists and is a directory
    return 0
}

prepare_b() {
    size_format="binary"
}

prepare_c() {
    compare="true"
}

prepare_f() {
    check_file_sizes="false"
}

prepare_y() {
    confirmation_needed="false"
}

prepare_k() {
    keep_7z_archive="true"
}

prepare_arch_s() {
    arch_silent="true"
}

# Ensure 7zz exists
if ! command -v 7zz >/dev/null 2>&1; then
    tput bold; echo "7zz not installed." >&2; tput sgr0
    echo "Install with: brew install 7zz" >&2
    exit 1
fi

## Constants
pv_options_WITH_SIZE="-ptbar"
pv_options_without_size="-trab"

## Variables
source_specified="false"
scratch_specified="false"
destination_specified="false"
options_specified="false"
confirmation_needed="true"
keep_7z_archive="false"
size_format="decimal"
check_file_sizes="true"
arch_silent="false"
compare="false"
script_options=()

while (( $# > 0 )); do
    arg="$1"

    case $arg in
        -h|--help)
            show_help
            exit 0
            ;;
        -b|--binary)
            prepare_b
            ;;
        -c|--compare)
            prepare_c
            ;;
        -f|--fast)
            prepare_f
            ;;
        -k|--keep)
            prepare_k
            ;;
        -y|--yes)
            prepare_y
            ;;
        -s|--scratch)
            if [[ $scratch_specified == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (scratch directory)
                    scratch_directory="$2"
                    # Skip the next argument in the next iteration
                    shift
                    # Flag scratch as specified
                    scratch_specified="true"
                    
                    if ! check_directory "$scratch_directory" "scratch directory"; then
                        echo "Error: scratch directory $scratch_directory does not exist.\nExiting." >&2
                        exit 1
                    fi
                else
                    echo "No scratch directory specified for -s/--scratch option. Exiting." >&2
                    exit 1
                fi
            else
                echo "Scratch directory specified multiple times. Exiting." >&2
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
                    destination_specified="true"
                    
                    check_directory "$destination_dir" "destination directory"
                else
                    echo "No destination folder specified for -o/--output option. Exiting." >&2
                    exit 1
                fi
            else
                echo "Destination specified multiple times. Exiting." >&2
                exit 1
            fi
            ;;
        -O|--Options)
            if [[ $options_specified == "false" ]]; then
                if (( $# > 1 )); then
                    # Store next argument (options)
                    script_options="$2"
                    # Convert to array
                    script_options=(${(z)script_options})
                    # Skip the next argument in the next iteration
                    shift
                    # Flag options as specified
                    options_specified="true"
                else
                    echo "No options specified for -o/--options option. Exiting." >&2
                    exit 1
                fi
            else
                echo "Options specified multiple times. Exiting." >&2
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
                        b)
                            prepare_b
                            ;;
                        c)
                            prepare_c
                            ;;
                        f)
                            prepare_f
                            ;;
                        k)
                            prepare_k
                            ;;
                        y)
                            prepare_y
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

if [[ $check_file_sizes == "false" && $compare == "true" ]]; then
    echo "Error: -c and -f options both selected. Exiting." >&2
    exit 1
fi

if [[ $options_specified == "true" ]]; then
    for (( i=1; i<=$#script_options; i++ ))
    do
        case $script_options[$i] in
            -h|--help)
                show_arch_help
                ;;
            -a|--archive|-A|--Archive|-u|--unarchive|-U|--Unarchive|-e|--encrypt|-E|--Encrypt|-o|--output|-O|--Output)
                echo "Error: $script_options[$i] specified in -O options ($script_options).\nExiting." >&2
                exit 1
                ;;
            -s|--silent)
                prepare_arch_s
                ;;
            -d|--dictionary)
                # Skip next argument (dictionary size in MiB)
                (( i++ ))
                ;;
            -t|--threads)
                # Skip next argument (number of threads)
                (( i++ ))
                ;;
            -b|--binary|-i|--integrity|-f|--fast|-p|--prior|-P|--Progress)
                # Allow and ignore
                ;;
            -*)
                simple_arguments=( ${(s::)${script_options[$i]:1}} )
                for simple_arg in "${simple_arguments[@]}"; do
                    case $simple_arg in
                        h)
                            show_arch_help
                            ;;
                        a|A|u|U|e)
                            echo "Error: '$simple_arg' specified in argument cluster $script_options[$i], found in -O options (${script_options[@]}).\nExiting." >&2
                            exit 1
                            ;;
                        s)
                            prepare_arch_s
                            ;;
                        b|i|f|p|P)
                            # Allow and ignore
                            ;;
                        *)
                            echo "Error: Invalid argument detected: '$simple_arg' in argument cluster $script_options[$i], found in -O options (${script_options[@]}).\nExitng." >&2
                            exit 1
                            ;;
                    esac
                done
                ;;
            *)
                echo "Error: Invalid argument detected: '$script_options[$i]' in -O options (${script_options[@]}).\nExitng." >&2
                exit 1
                ;;
        esac
    done
fi

# Use the dir the input file is located in as the output dir if no output dir was explicitly specified
[[ $destination_specified == "false" ]] && destination_dir=${source_path:h}

# Use the destination directory as the scratch dir if no scratch dir was explicitly specified
[[ $scratch_specified == "false" ]] && scratch_directory="$destination_dir"

# Sanitize destination_dir (remove trailing '/')
destination_dir=${destination_dir:a}

# Sanitize scratch_directory (remove trailing '/')
scratch_directory=${scratch_directory:a}

destination_path="${destination_dir:P}/${${source_path:t}:r}.xz"
tput bold
echo "Converting ${source_path:t} to ${destination_path:t}"
tput sgr0
echo "Source:\t\t$source_path"
echo "Scratch:\t$scratch_directory"
echo "Destination:\t$destination_path"
[[ $options_specified == "true" ]] && echo "Options:\t$script_options"
if [[ $check_file_sizes == "true" ]]; then
    printf "Determining Source Size..."
    source_size_byte=$(get_size $source_path)
    source_size=$(to_human $source_size_byte)
    tput cr; tput el
    printf "\rSource Size:\t$source_size / $source_size_byte bytes\n"
fi
if [[ $keep_7z_archive == "true" ]]; then
    echo "🔒 Source archive ${source_path:t} will be kept after conversion."
else
    tput bold
    printf "🗑️ Source archive ${source_path:t} will be deleted after conversion.\n"
    tput sgr0
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

# Record start time (epoch seconds)
start_epoch=$(date +%s)

# Check source archive readability
zip_options=(l)
printf "Checking source archive readability..."
if ! 7zz "${zip_options[@]}" "$source_path" > /dev/null 2>&1; then
    tput cr; tput el
    printf "\rArchive ${source_path:t} could not be read. Exiting.\n" >&2
    exit 1
fi
tput cr; tput el

# Set 7zz options for unarchiving
zip_options=(x -so -mmt=on)

# Set pv options for unarchiving
pv_options=()
[[ $size_format == "decimal" ]] && pv_options+=(-k)
pv_options+=(-N "${source_path:t}")
if [[ $check_file_sizes == "true" ]]; then
    pv_options+=(-s "$source_size_byte" "$pv_options_WITH_SIZE")
else
    pv_options+=("$pv_options_without_size")
fi

# Create temporary directory in scratch dir
tmp_dir="$scratch_directory/temp$$"
mkdir -p "$tmp_dir"

echo "Extracting ${source_path:t}"

cancel_unarchiving() {
    trap - INT TERM HUP
    
    # Kill the pipeline processes (children of this shell), but NOT this shell.
    pkill -TERM -P $$ 2>/dev/null
    # give them a moment; then be firm if needed
    sleep 0.2
    pkill -KILL -P $$ 2>/dev/null
    rm -rf "$tmp_dir"
    exit 1
}

trap cancel_archiving INT TERM HUP

# Unpack 7z archive into temp dir in scratch directory
7zz "${zip_options[@]}" "$source_path" | pv "${pv_options[@]}" | tar --acls --xattrs -C "$tmp_dir" -xf -
pipe_st=( "${pipestatus[@]}" )

trap - INT TERM HUP

if ! check_pipeline "${pipe_st[@]}"; then
    echo "Exiting."
    rm -rf "$tmp_dir"
    exit 1
fi

extracted_item="${${${source_path:t}:r}:r}"
script_options+=(-O "$destination_path")
if [[ $arch_silent == "false" ]]; then
    [[ $check_file_sizes == "false" ]] && script_options+=(-f)
    script_options+=(-P)
fi

if [[ $check_file_sizes == "true" ]]; then
    printf "Determining unarchived size..."
    unarchived_size_byte=$(get_size "$tmp_dir")
    unarchived_size=$(to_human $unarchived_size_byte)
    tput cr; tput el
fi

echo "Creating ${destination_path:t}"

# Re-pack data using xz
../arch.zsh -A "$tmp_dir/$extracted_item" "${script_options[@]}"

printf "Deleting temporary directory..."
rm -rf "$tmp_dir"
tput cr; tput el

if [[ $check_file_sizes == "true" ]]; then
    printf "Determining destination size..."
    destination_size_byte=$(get_size $destination_path)
    destination_size=$(to_human $destination_size_byte)
    tput cr; tput el
fi

if [[ $keep_7z_archive == "false" ]]; then
    printf "Deleting pre-existing ${source_path:t}..."
    rm $source_path
    tput cr; tput el
fi

# Display finishing time
echo "Finish:\t\t$(date)"

# Record end time (epoch seconds)
end_epoch=$(date +%s)

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

# (if specified) Show file size comparison between unarchived data and xz-archive
if [[ $check_file_sizes == "true" ]]; then
    printf "\n"
    compare_sizes "$extracted_item" $unarchived_size_byte "${destination_path:t}" $destination_size_byte
fi

# (if specified) Show file size comparison between 7z-archive and xz-archive
if [[ $compare == "true" ]]; then
    printf "\n"
    compare_sizes "${destination_path:t}" $destination_size_byte "${source_path:t}" $source_size_byte
fi

echo "\nomgklolthxbye"
