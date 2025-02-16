# Automounter-Shell

A simple Bash script that implements a custom shell with **automount** and **auto-unmount** functionality. Whenever the user accesses a directory specified in a configuration file, the script mounts it automatically if not already mounted. After a configurable **lifetime** and no active usage, the script will unmount it.

## Features

- **Custom prompt**: `amsh>`  
- **Internal `cd` command** that:
  - Detects if the target directory is a special “mountpoint” from the config file.  
  - Executes `mount` (or other mount commands like `sshfs`, `tmpfs`, etc.) if needed.  
- **External commands** are invoked via `sh -c`; the shell detects any paths that might need automount.  
- **Auto-unmount** after `lifetime` seconds, if no process is using that directory (checked via `lsof +D`).

## Project Structure

- **amsh.sh**  
  The main script:
  1. Reads the config file (`amsh_fstab.conf`).
  2. Displays the `amsh>` prompt.
  3. Implements the logic for auto-mount and auto-unmount.
- **amsh_fstab.conf**  
  Defines the special directories:
  ```plaintext
  <source> <mountpoint> <filesystem_type> <lifetime_in_seconds>
