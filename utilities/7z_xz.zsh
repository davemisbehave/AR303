#!/usr/bin/env zsh

script_dir="${0:A:h}"
source "${script_dir}/../lib/ar-lib.zsh"

setopt pipefail

show_help() {
    echo "I like turtles."
}

show_arch_help() {
    ./arch.zsh -h
    exit 1
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
