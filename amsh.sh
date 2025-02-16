#!/usr/bin/env bash

CONFIG_FILE="./config/amsh_fstab.conf"

# Associative array mapping mountpoint -> "source fs_type lifetime"
declare -A MOUNT_INFO
# Associative array mapping mountpoint -> timestamp (mount or last access time)
declare -A MOUNT_TIMES

# 1. Read the config file and populate MOUNT_INFO
while read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    src_fs=$(echo "$line" | awk '{print $1}')
    mp=$(echo "$line" | awk '{print $2}')
    fs_type=$(echo "$line" | awk '{print $3}')
    lifetime=$(echo "$line" | awk '{print $4}')

    MOUNT_INFO["$mp"]="$src_fs $fs_type $lifetime"
done < <(/bin/grep -v '^[[:space:]]*#' "$CONFIG_FILE" 2>/dev/null)

# 2. Detect if a path corresponds to a configured mountpoint
function detect_mountpoint_in_path() {
    local path="$1"
    # Convert relative paths to absolute
    if [[ "$path" != /* ]]; then
        path="$PWD/$path"
    fi

    for mp in "${!MOUNT_INFO[@]}"; do
        # If the path is exactly the mountpoint or within it
        if [[ "$path" == "$mp" || "$path" == "$mp/"* ]]; then
            echo "$mp"
            return
        fi
    done
}

# 3. Check if a given mountpoint is already mounted
function is_mounted() {
    local mp="$1"
    mount | grep -q " on $mp "
}

# 4. Ensure a mountpoint is mounted; update timestamp
function ensure_mounted() {
    local mp="$1"
    local info="${MOUNT_INFO["$mp"]}"
    local src_fs=$(echo "$info" | awk '{print $1}')
    local fs_type=$(echo "$info" | awk '{print $2}')
    local lifetime=$(echo "$info" | awk '{print $3}')

    if ! is_mounted "$mp"; then
        echo "[amsh] Mounting $mp (FS: $fs_type, Source: $src_fs)"
        sudo mount -t "$fs_type" "$src_fs" "$mp" || return 1
    fi

    # Update timestamp
    MOUNT_TIMES["$mp"]=$(date +%s)
}

# 5. Check if a mountpoint is in use (processes have files open there)
function mountpoint_in_use() {
    local mp="$1"
    lsof +D "$mp" &>/dev/null
    [[ $? -eq 0 ]] && return 0 || return 1
}

# 6. After each command, check if any mountpoints have exceeded their lifetime
#    and, if not in use, unmount them
function check_unmounts() {
    local now=$(date +%s)

    for mp in "${!MOUNT_INFO[@]}"; do
        if is_mounted "$mp"; then
            local info="${MOUNT_INFO["$mp"]}"
            local lifetime=$(echo "$info" | awk '{print $3}')
            local last_access="${MOUNT_TIMES["$mp"]}"

            # Check if lifetime has passed
            if (( now - last_access > lifetime )); then
                # Check if it's still in use
                if ! mountpoint_in_use "$mp"; then
                    echo "[amsh] Unmounting $mp (lifetime expired, not in use)"
                    sudo umount "$mp"
                fi
            fi
        fi
    done
}

# 7. Internal "cd" command
function amsh_cd() {
    local dest="$1"
    [[ -z "$dest" ]] && dest="$HOME"  # If no argument, go to HOME

    local mp=$(detect_mountpoint_in_path "$dest")
    if [[ -n "$mp" ]]; then
        ensure_mounted "$mp" || {
            echo "[amsh] Error mounting $mp"
            return 1
        }
    fi

    builtin cd "$dest" || return 1

    if [[ -n "$mp" ]]; then
        MOUNT_TIMES["$mp"]=$(date +%s)
    fi
}

# 8. Execute an external command:
#    - For each argument that might be a path, ensure mount is done
function amsh_exec() {
    local args=("$@")
    
    for arg in "${args[@]}"; do
        if [[ "$arg" == */* ]]; then
            local mp=$(detect_mountpoint_in_path "$arg")
            if [[ -n "$mp" ]]; then
                ensure_mounted "$mp" || {
                    echo "[amsh] Error mounting $mp"
                    return 1
                }
                MOUNT_TIMES["$mp"]=$(date +%s)
            fi
        fi
    done

    # Join arguments and run via sh -c
    local joined_cmd
    joined_cmd="$(printf " %q" "${args[@]}")"
    /bin/sh -c "${joined_cmd}"
}

# 9. Main loop: show prompt, read commands, execute them
function main_loop() {
    while true; do
        echo -n "amsh> "
        IFS= read -r line || { echo; break; }

        local tokens=($line)
        [[ ${#tokens[@]} -eq 0 ]] && continue

        local cmd="${tokens[0]}"
        case "$cmd" in
            exit)
                break
                ;;
            cd)
                amsh_cd "${tokens[1]}"
                ;;
            *)
                amsh_exec "${tokens[@]}"
                ;;
        esac

        # Perform unmount checks
        check_unmounts
    done
}

main_loop
exit 0