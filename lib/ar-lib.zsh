#!/usr/bin/env zsh

## Variables
verbosity="normal"
confirmation_needed="true"
size_format="decimal"
check_file_sizes="true"

## Constants
pv_options_WITH_SIZE="-F %N %b %t %r %a |%{bar-shaded}| %{progress-amount-only} %e"
pv_options_without_size="-trab"

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

to_human() {
    local abs_size_bytes

    if (( $1 < 0 )); then
        abs_size_bytes=$(( -1 * $1 ))
        printf "-"
    else
        abs_size_bytes=$1
    fi

    local base units
    if [[ $size_format == "binary" ]]; then
        base=1024
        units="B KiB MiB GiB TiB"
    else
        base=1000
        units="B KB MB GB TB"
    fi

    awk -v base="$base" -v units="$units" -v value="$abs_size_bytes" '
        BEGIN {
            split(units, unit);
            i = 1;
            while (value >= base && i < 5) {
                value /= base;
                i++;
            }
            if (i == 1) printf "%d %s", value, unit[i];
            else printf "%.1f %s", value, unit[i];
        }
    '
}

compare_sizes() {
    # First item (A)
    local name_A="$1"
    local bytes_A="$2"
    local human_A="$(to_human $bytes_A)"
    human_A=(${(z)human_A})
    # Second item (B)
    local name_B="$3"
    local bytes_B="$4"
    local human_B="$(to_human $bytes_B)"
    human_B=(${(z)human_B})
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
    abs_difference_human=(${(z)abs_difference_human})
    
    # Print names
    echo "$name_A vs. $name_B"
    
    # Find the lengths of the longest name, size (in bytes) and size (in human readable form)
    local item_names=( "$name_A" "$name_B" )
    local item_sizes=( "$bytes_A" "$bytes_B" )
    local item_human_number=( "${human_A[1]}" "${human_B[1]}" )
    local item_human_unit=( "${human_A[2]}" "${human_B[2]}" )
    local longest_item_name_length=0
    local longest_size_length=0
    local longest_human_number=0
    local longest_human_unit=0
    local n
    for (( n=1; n<=$#item_names; n++ )); do
        (( ${#item_names[$n]} > longest_item_name_length )) && longest_item_name_length=${#item_names[$n]}
        (( ${#item_sizes[$n]} > longest_size_length )) && longest_size_length=${#item_sizes[$n]}
        (( ${#item_human_number[$n]} > longest_human_number )) && longest_human_number=${#item_human_number[$n]}
        (( ${#item_human_unit[$n]} > longest_human_unit )) && longest_human_unit=${#item_human_unit[$n]}
    done
    (( ${#abs_difference_human[1]} > longest_human_number )) && longest_human_number=${#abs_difference_human[1]}
    (( ${#abs_difference_human[2]} > longest_human_unit )) && longest_human_unit=${#abs_difference_human[2]}
    
    for (( n=1; n<=$#item_names; n++ )); do
        printf "%-${longest_item_name_length}s : %+${longest_human_number}s %+${longest_human_unit}s (%+${longest_size_length}s bytes)\n" "${item_names[$n]}" "${item_human_number[$n]}" "${item_human_unit[$n]}" "${item_sizes[$n]}"
    done
 
    # Print comparison / difference
    printf "%-${longest_item_name_length}s : " "$name_B"
    if (( $difference_bytes == 0 )); then
        printf "the same size as $name_A\n"
    else
        printf "%+${longest_human_number}s %+${longest_human_unit}s " "${abs_difference_human[1]}" "${abs_difference_human[2]}"
        if (( $difference_bytes < 0 )); then
            printf "smaller (-"
        else
            printf "larger (+"
        fi
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

command_exists() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0    # command does exist
    else
        return 1    # command does not exist
    fi
}

run_brew() {
    if [[ $verbosity == "verbose" ]]; then
        brew "$@"
    else
        brew "$@" > /dev/null 2>&1
    fi
}

check_dependency() {
    local commands=$#
    local not_installed=()
    local brew_package=()
    local brew_available=()
    local no_brew=()
    local confirm
    local n
    
    for (( n=1; n<=$commands; n++ )); do
        if ! command_exists "$argv[$n]"; then
            case $argv[$n] in
                7zz)
                    brew_package+=(sevenzip)
                    not_installed+=(7zz)
                    brew_available+=(7zz)
                    ;;
                pv)
                    brew_package+=(pv)
                    not_installed+=(pv)
                    brew_available+=(pv)
                    ;;
                xz)
                    brew_package+=(xz)
                    not_installed+=(xz)
                    brew_available+=(xz)
                    ;;
                *)
                    echo "Error: check_dependency encountered an unknown command ($argv[$n]).\nExiting." >&2
                    exit 1
                    ;;
            esac
        fi
    done
    
    [[ $#not_installed == 0 ]] && return 0

    printf "The following executables are not installed: %s\n" "${not_installed[*]}"
    local ret_val=0
    if [[ $#brew_package > 0 ]]; then
        if command_exists brew; then
            if [[ $confirmation_needed == "true" ]]; then
                printf "Install executables (%s) with Homebrew?\n" "${brew_available[*]}"
                read "?Confirm with 'y': " confirm
                [[ $confirm == "y" ]] || return 1
            fi
            printf "Updating Homebrew..."
            [[ $verbosity == "verbose" ]] && printf "\n"
            run_brew update || { echo "Failed to update Homebrew." >&2; return 1 }
            for (( n=1; n<=$#brew_package; n++ )); do
                tput cr; tput el
                printf "Installing executable %s (package %s)..." "${brew_available[$n]}" "${brew_package[$n]}"
                [[ $verbosity == "verbose" ]] && printf "\n"
                run_brew install ${brew_package[$n]} || { printf "Failed to install package %s for executable %s.\n" "${brew_package[$n]}" "${brew_available[$n]}" >&2; return 1 }
            done
            tput cr; tput el
        else
            printf "The following executables need Homebrew in order to be installed: %s\n" "${brew_available[*]}"
            ret_val=1
        fi
    fi
    (( ${#no_brew} > 0 )) && { printf "The following executables must be installed manually: %s\n" "${no_brew[*]}" >&2; ret_val=1 }
    return $ret_val
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
            echo "Unknown pipe command: $cmd"
            ;;
    esac
}

# Usage: check_pipeline "${pipestatus[@]}"
check_pipeline() {
    local statuses=("$@")
    local exit_code=0
    local commands=()
    local pipe_command

    case $operation in
        archive)
            commands+="tar"
            commands+="pv"
            commands+="xz"
            ;;
        unarchive)
            commands+="pv"
            commands+="xz"
            commands+="tar"
            ;;
        convert)
            commands+="7zz"
            commands+="pv"
            commands+="tar"
            ;;
        *)
            echo "Error: Invalid operation: $operation" >&2
            return 1
            ;;
    esac
    
    for pipe_command in {1..$#commands}
    do
        if [[ ${statuses[$pipe_command]} -ne 0 ]]; then
            printf "\rError: Command ${commands[$pipe_command]} in pipeline failed with exit code ${statuses[$pipe_command]}: $(check_command ${commands[$pipe_command]} ${statuses[$pipe_command]})\n" >&2
            exit_code=1
        fi
    done

    return $exit_code
}

exit_invalid_vebosity() {
    echo "Error: Invalid verbosity ($1). Exiting" >&2
    exit 1
}

prepare_b() {
    size_format="binary"
}

show_delete() {
    printf "Deleting %s..." "$1"
    rm -rf -- "$2"
    tput cr; tput el
}
