#!/usr/bin/env zsh

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
            if(i==1) {printf "%d %s", $1, unit[i]}
            else {printf "%.1f %s", $1, unit[i]}
        }'
    else
        echo $abs_size_bytes | awk '{
            split("B KB MB GB TB", unit);
            i=1;
            while($1>=1000 && i<5) { $1/=1000; i++ }
            if(i==1) {printf "%d %s", $1, unit[i]}
            else {printf "%.1f %s", $1, unit[i]}
        }'
    fi
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
    local n
    
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

prepare_b() {
    size_format="binary"
}
