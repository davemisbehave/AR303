# AR303
`arch.sh` is a small **zsh** utility for **archiving** and **unarchiving** using **tar** and **xz** *streamed through pipes* — so you get a `.tar.xz` without ever creating an intermediate `.tar` on disk.

It also integrates **pv** for progress output.

## WARNING
This is another exercise to learn scripting. Do not rely on this software for anything serious. Use software written by someone who knows what they're doing if you need something more reliable and robust.

---

## Features

- Create `.tar.xz` archives from files, folders (and “packages”) via streaming
- Extract `.tar.xz` archives via streaming
- File permissions (etc.) are preserved
- Progress bars (pv) with optional total-size estimates
- Optional post-create integrity test
- Optionally tunable xz dictionary size and thread count
- “Fast” mode to skip potentially slow size scans
- “Silent” mode that suppresses stdout (errors still still go to stderr)

---

## Requirements

This script is written for **macOS only**.

Dependencies (not pre-installed with macOS):

- **xz** (compression software)  
  Install: `brew install xz`
- **pv** (progress viewer)  
  Install: `brew install pv`
- **brew** (Homebrew)**(*)**  
  Install: [See Homebrew website](https://brew.sh)

**(*)** Technically not necessary to run the script, but likely to be the tool used to install `xz` and `pv` with.

---

## Installation

0. Install xz and pv
```sh
brew install xz pv
```
1. Put `arch.sh` somewhere in your PATH (or keep it in a project folder).
2. Make it executable:

```sh
chmod +x arch.sh
```

---

## Usage

### Archive
With user prompt (lower-case `-a` or `--archive`)
```sh
./arch.sh -a <input_path>
```
Skip the user prompt (upper-case `-A` or `--Archive`)
```sh
./arch.sh -A <input_path>
```

### Unarchive
With user confirmation prompt (lower-case `-u` or `--unarchive`)
```sh
./arch.sh -u <archive.tar.xz>
```
Skip the user confirmation prompt (upper-case `-U` or `--Unarchive`)
```sh
./arch.sh -U <archive.tar.xz>
```

### Output destination
-	`-o <dir>` sets the destination directory (for both archive and unarchive).  
-	`-O <file>` sets the output file name (archive only). If it includes a path, that path is used.  
- You can not specify both `-o`/`--output` and `-O`/`-Output` at the same time.
  - If you want a custom output file name _and_ directory for archiving, use only the `-O`/`-Output` option.
- If no output is specified with either `-o`/`--output` or `-O`/`-Output`:
  - The current working directory is used as the output folder.
  - If archiving, the resulting archive will have the name of the file/folder being archived with `.tar.xz` appended.

---

## Options

### Operation
This is required. Pick exactly one.
- `-a`/`--archive`: Archive input_path → *.tar.xz (asks for confirmation)
- `-A`/`--Archive`: Same as archive, **but no confirmation**

### Output control
You can not specify both `-o`/`--output` and `-O`/`-Output` at the same time.
If omitted, the current working directory is used.
- `-o <dir>`, `--output <dir>`: Destination directory.
- `-O <name-or-path>`, `--Output <name-or-path>` (_archive only_): Output archive file name.
- `-p, --prior` (_archive only_): When overwriting existing archives, delete the pre-existing archive prior to creating the new archive. If omitted, the pre-existing archive will only be deleted _after_ the new one has been created.

### Miscallaneous options
- `-f`/`--fast`: Skip determining source/destination sizes (useful for huge directories).
- `-b`/`--binary`: Use binary units (KiB/MiB/GiB). Default is decimal (KB/MB/GB).
- `-s`/`--silent`: Silences stdout output (errors still go to stderr). Also implies `--fast`.
- `-i`/`--integrity`: After archiving, run an integrity check of the created archive (can be slow for large archives).

### Encryption
**ENCRYPTION IS CURRENTLY NOT WORKING**

Header data is always encrypted too if encryption is specified.
**Warning:** The `-E`/`--Encrypt` option is problematic from a securty standpoint, and is therefore highly discouraged.
- `-e`/`--encrypt`: **Not implemented yet (exits with an error).** Ask user for password interactively before en-/decrypting.
- `-E <password>`/`--Encrypt <password>`: Use password specified in the following argument (`<password>`) for en-/decryption. See security warning above.

### Compression tuning
- `-d <MiB>`/`--dictionary <MiB>`: xz dictionary size in MiB (default: 256).
- `-t <threads|auto>`/`--threads <threads|auto>`: Thread count for xz.

---

## Examples
### Archive a folder (no prompt), and verify the resulting archive
```sh
./arch.sh -Ai MyFolder
```
### Archive a file with a 128 MB dictionary
```sh
./arch.sh -a MyFile.txt -d 128
```
### Archive and write to a specific directory with a specific name
```sh
./arch.sh --archive file.txt -O ~/Archives/file.txt.tar.xz
```
### Unarchive into the current directory using binary units
```sh
./arch.sh -ub backup.tar.xz
```
### Unarchive into a specific directory and skip size scanning
```sh
./arch.sh -uf backup.tar.xz -o ./output
```
