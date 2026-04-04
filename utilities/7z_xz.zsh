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

check_directory_existence() {
    if [[ -e "$1" ]]; then
        if [[ "$(object_type "$1")" != "directory" ]]; then
            err "Specified %s not a directory (%s).\nExiting." "$2" "$1"
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
    check_file_sizes="none"
}

prepare_y() {
    confirmation_needed="false"
}

prepare_k() {
    keep_7z_archive="true"
}

prepare_arch_verbosity() {
    if [[ "$1" != "normal" && "$1" != "verbose" && "$1" != "progress" && "$1" != "silent" ]]; then
        exit_invalid_vebosity "$1"
    else
        # Set verbosity according to argument
        arch_verbosity="$1"
    fi
}

## Variables
source_specified="false"
scratch_specified="false"
destination_specified="false"
options_specified="false"
keep_7z_archive="false"
arch_verbosity="normal"
arch_verbosity_specified="false"
arch_size_check_specified="false"
compare="false"
operation="convert"
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
                    
                    if ! check_directory_existence "$scratch_directory" "scratch directory"; then
                        err "Scratch directory %s does not exist.\nExiting." "$scratch_directory"
                        exit 1
                    fi
                else
                    not_specified_err "scratch directory" "$arg"
                    exit 1
                fi
            else
                specified_multiple_err "Scratch directory"
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
                    
                    check_directory_existence "$destination_dir" "destination directory"
                else
                    not_specified_err "destination folder" "$arg"
                    exit 1
                fi
            else
                specified_multiple_err "Destination"
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
                    not_specified_err "options" "$arg"
                    exit 1
                fi
            else
                specified_multiple_err "Options"
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
                            err "Invalid argument detected: %s in %s.\nExitng." "$simple_arg" "$arg"
                            exit 1
                            ;;
                    esac
                done
            else
                if [[ $source_specified == "true" ]]; then
                    err "Multiple sources specified. Exiting."
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

if [[ $check_file_sizes == "none" && $compare == "true" ]]; then
    err "-c and -f options both selected. Exiting."
    exit 1
fi

check_dependency "7zz" "pv" "xz" || exit 1

if [[ $options_specified == "true" ]]; then
    for (( i=1; i<=$#script_options; i++ )); do
        case $script_options[$i] in
            -h|--help)
                show_arch_help
                ;;
            -a|--archive|-A|--Archive|-u|--unarchive|-U|--Unarchive|-e|--encrypt|-E|--Encrypt|-o|--output|-O|--Output)
                err "%s specified in -O options (%s).\nExiting." "${script_options[$i]}" "$script_options"
                exit 1
                ;;
            -d|--dictionary)
                # Skip next argument (dictionary size in MiB)
                (( i++ ))
                ;;
            -t|--threads)
                # Skip next argument (number of threads)
                (( i++ ))
                ;;
            -s|--size)
                # Skip next argument (size calculation parameter)
                (( i++ ))
                arch_size_check_specified="true"
                ;;
            -b|--binary|-i|--integrity|-f|--fast|-p|--prior)
                ;;  # Allow and ignore
            -v|--verbosity)
                if [[ $arch_verbosity_specified == "true" ]]; then
                    err "-v/--verbosity specified multiple times in -O/--Options options. Exiting."
                    exit 1
                fi
                prepare_arch_verbosity "${script_options[$(( i + 1 ))]}"
                arch_verbosity_specified="true"
                (( i++ ))
                ;;
            -*)
                simple_arguments=( ${(s::)${script_options[$i]:1}} )
                for simple_arg in "${simple_arguments[@]}"; do
                    case $simple_arg in
                        h)
                            show_arch_help
                            ;;
                        a|A|u|U|e)
                            err "'%s' specified in argument cluster %s, found in -O options (${script_options[@]}).\nExiting." "$simple_arg" "${script_options[$i]}"
                            exit 1
                            ;;
                        b|i|f|p)
                            ;;  # Allow and ignore
                        *)
                            err "Invalid argument detected: '%s' in argument cluster %s, found in -O options (%s).\nExitng." "$simple_arg" "${script_options[$i]}" "${script_options[@]}"
                            exit 1
                            ;;
                    esac
                done
                ;;
            *)
                err "Invalid argument detected: '%s' in -O options (%s).\nExitng." "${script_options[$i]}" "${script_options[@]}"
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
if [[ $check_file_sizes == "all" ]]; then
    printf "Determining Source Size..."
    pre_source_size_check_time=$EPOCHREALTIME
    source_size_byte=$(get_size $source_path)
    post_source_size_check_time=$EPOCHREALTIME
    source_size=$(to_human $source_size_byte)
    tput cr; tput el
    printf "\rSource Size:\t$source_size / $source_size_byte bytes\n"
fi
if [[ $keep_7z_archive == "true" ]]; then
    printf "Source archive %s will be kept after conversion.\n" "${source_path:t}"
else
    print -Pnru1 -- "%F{yellow}Warning:%f"
    printf " Source archive %s will be deleted after conversion.\n" "${source_path:t}"
fi

if [[ $confirmation_needed == "true" ]]; then
    read "?Confirm with 'y': " confirmation
    [[ $confirmation == "y" ]] || {
        echo "User confirmation negative. Exiting."
        exit 1
    }
fi

# Display starting time
echo "\nStart:\t\t$(date)"

# Record start time (epoch seconds)
start_time=$EPOCHREALTIME

# Check source archive readability
zip_options=(l)
printf "Checking source archive readability..."
if ! 7zz "${zip_options[@]}" "$source_path" > /dev/null 2>&1; then
    tput cr; tput el
    printf("\r")
    err "Archive %s could not be read. Exiting.\n" "${source_path:t}"
    exit 1
fi
tput cr; tput el

# Set 7zz options for unarchiving
zip_options=(x -so -mmt=on)

# Set pv options for unarchiving
pv_options=()
[[ $size_format == "decimal" ]] && pv_options+=(-k)
pv_options+=(-N "${source_path:t}")
if [[ $check_file_sizes == "all" ]]; then
    pv_options+=(-s "$source_size_byte" "$unarchive_pv_options_with_size")
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
    show_delete "temporary directory" "$tmp_dir"
    exit 1
}

trap cancel_unarchiving INT TERM HUP

pre_unarchive_time=$EPOCHREALTIME

# Unpack 7z archive into temp dir in scratch directory
7zz "${zip_options[@]}" "$source_path" | pv "${pv_options[@]}" | tar --acls --xattrs -C "$tmp_dir" -xf -
pipe_st=( "${pipestatus[@]}" )

post_unarchive_time=$EPOCHREALTIME

trap - INT TERM HUP

if ! check_pipeline "${pipe_st[@]}"; then
    echo "Exiting."
    show_delete "temporary directory" "$tmp_dir"
    exit 1
fi

extracted_item="${${${source_path:t}:r}:r}"
script_options+=(-O "$destination_path")
[[ $arch_verbosity_specified == "false" ]] && script_options+=(-v progress)
[[ $check_file_sizes == "none" && $arch_size_check_specified == "false" ]] && script_options+=(-s none)

pre_unarchived_size_check=$EPOCHREALTIME

if [[ $check_file_sizes == "all" ]]; then
    printf "Determining unarchived size..."
    unarchived_size_byte=$(get_size "$tmp_dir")
    unarchived_size=$(to_human $unarchived_size_byte)
    tput cr; tput el
fi

post_unarchived_size_check=$EPOCHREALTIME

echo "Creating ${destination_path:t}"

cancel_archiving() {
    trap - INT TERM HUP
    show_delete "temporary directory" "$tmp_dir"
    exit 1
}

trap cancel_archiving INT TERM HUP

pre_archive_time=$EPOCHREALTIME

# Re-pack data using xz
if ! ../arch.zsh -A "$tmp_dir/$extracted_item" "${script_options[@]}"; then
    show_delete "temporary directory" "$tmp_dir"
    exit 1
fi

post_archive_time=$EPOCHREALTIME

trap - INT TERM HUP

show_delete "temporary directory" "$tmp_dir"

if [[ $check_file_sizes == "all" ]]; then
    printf "Determining destination size..."
    pre_destination_size_check_time=$EPOCHREALTIME
    destination_size_byte=$(get_size $destination_path)
    post_destination_size_check_time=$EPOCHREALTIME
    destination_size=$(to_human $destination_size_byte)
    tput cr; tput el
fi

if [[ $keep_7z_archive == "false" ]]; then
    show_delete "pre-existing ${source_path:t}" "$source_path"
    tput cr; tput el
fi

# Display finishing time
echo "Finish:\t\t$(date)"

# Record end time (epoch seconds)
end_time=$EPOCHREALTIME

# (if specified) Show file size comparison between unarchived data and xz-archive
if [[ $check_file_sizes == "all" ]]; then
    printf '\n'
    compare_sizes "$extracted_item" $unarchived_size_byte "${destination_path:t}" $destination_size_byte
fi

# (if specified) Show file size comparison between 7z-archive and xz-archive
if [[ $compare == "true" ]]; then
    printf '\n'
    compare_sizes "${source_path:t}" $source_size_byte "${destination_path:t}" $destination_size_byte
fi

printf '\n'
time_descriptions=()
time_values=()
time_rates=()

if [[ -v pre_source_size_check_time ]]; then
    time_descriptions+=("Source size check")
    time_values+=("$(print_elapsed_time $pre_source_size_check_time $post_source_size_check_time)")
    time_rates+=("NULL")
fi

time_descriptions+=("Unarchive")
time_values+=("$(print_elapsed_time $pre_unarchive_time $post_unarchive_time)")
if [[ -v source_size_byte ]]; then
    time_rates+=("$(print_data_rate $pre_unarchive_time $post_unarchive_time $source_size_byte)")
else
    time_rates+=("NULL")
fi

if [[ -v source_size_byte ]]; then
    time_descriptions+=("Unarchived size check")
    time_values+=("$(print_elapsed_time $pre_unarchived_size_check $post_unarchived_size_check)")
    time_rates+=("NULL")
fi

time_descriptions+=("Re-archive")
time_values+=("$(print_elapsed_time $pre_archive_time $post_archive_time)")
if [[ -v unarchived_size_byte ]]; then
    time_rates+=("$(print_data_rate $pre_archive_time $post_archive_time $unarchived_size_byte)")
else
    time_rates+=("NULL")
fi

if [[ -v pre_destination_size_check_time ]]; then
    time_descriptions+=("Re-archived size check")
    time_values+=("$(print_elapsed_time $pre_destination_size_check_time $post_destination_size_check_time)")
    time_rates+=("NULL")
fi

time_descriptions+=("Total")
[[ -v pre_source_size_check_time ]] && (( start_time -= ( post_source_size_check_time - pre_source_size_check_time ) ))
time_values+=("$(print_elapsed_time $start_time $end_time)")
time_rates+=("NULL")

longest_description=$(longest_strl "${time_descriptions[@]}")
longest_values=$(longest_strl "${time_values[@]}")
longest_rates=$(longest_strl "${(@)time_rates:#NULL}")

for (( i=1; i<=$#time_descriptions; i++ )); do
    printf "%-${longest_description}s: " "${time_descriptions[$i]}"
    printf "%+${longest_values}s" "${time_values[$i]}"
    if [[ $time_rates[$i] != "NULL" ]]; then
        printf " @ %+${longest_rates}s" "${time_rates[$i]}"
    fi
    printf '\n'
done
