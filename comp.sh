#!/bin/zsh
set -euo pipefail

# Usage: objcmp.zsh /abs/path/to/obj1 /abs/path/to/obj2
O1="${1:?need arg1 path}"
O2="${2:?need arg2 path}"

normpath() { local p="$1"; [[ "$p" != "/" ]] && p="${p%/}"; print -r -- "$p"; }
O1="$(normpath "$O1")"
O2="$(normpath "$O2")"

err() { print -u2 -- "$*"; }

if [[ ! -e "$O1" || ! -e "$O2" ]]; then
  err "ERROR: one of the paths does not exist."
  exit 2
fi

type_of() {
  local p="$1"
  if [[ -d "$p" ]]; then print -r -- "dir"
  elif [[ -f "$p" ]]; then print -r -- "file"
  elif [[ -L "$p" ]]; then print -r -- "symlink"
  else print -r -- "other"
  fi
}
T1="$(type_of "$O1")"
T2="$(type_of "$O2")"

if [[ "$T1" != "$T2" ]]; then
  print -- "TYPE mismatch: $T1 vs $T2"
  exit 1
fi

sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }

# Full xattrs dump for one path (names + values). Empty if none.
xattrs_dump() {
  local p="$1"
  if xattr -l "$p" >/dev/null 2>&1; then
    xattr -l "$p" 2>/dev/null
  fi
}

# Strong “single digest” for a directory/package (includes ACLs + xattrs where supported by bsdtar)
dir_tar_digest() {
  local p="$1"
  local parent="${p:h}" base="${p:t}"
  ( cd "$parent" && bsdtar --acls --xattrs -cpf - "$base" 2>/dev/null \
    | shasum -a 256 | awk '{print $1}' )
}

# Per-entry metadata manifest (captures mtime/ctime/perms/owner/flags/etc.)
# Fields: path|type|mode|uid|gid|size|mtime|ctime|flags|inode
dir_stat_manifest() {
  local root="$1"
  ( cd "$root" && \
    find . -xdev -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 stat -f '%N|%HT|%Sp|%u|%g|%z|%m|%c|%f|%i' 2>/dev/null )
}

# Per-entry xattrs dump in stable order (only entries that have xattrs)
dir_xattrs_dump() {
  local root="$1"
  ( cd "$root" && \
    find . -xdev -print0 \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' rel; do
        if xattr -l "$rel" >/dev/null 2>&1; then
          print -r -- "### $rel"
          xattr -l "$rel" 2>/dev/null
        fi
      done )
}

tmpfile() { mktemp -t objcmp.XXXXXX; }

printed_any=no
print_section() {
  local title="$1"
  if [[ "$printed_any" == "no" ]]; then
    printed_any=yes
  else
    print ""
  fi
  print -- "$title"
}

# ---------------- compare ----------------

if [[ "$T1" == "file" ]]; then
  h1="$(sha256_file "$O1")"
  h2="$(sha256_file "$O2")"
  if [[ "$h1" != "$h2" ]]; then
    print_section "CONTENT mismatch:"
    print -- "  $O1  sha256=$h1"
    print -- "  $O2  sha256=$h2"
  fi

  x1="$(tmpfile)"; x2="$(tmpfile)"
  xattrs_dump "$O1" >"$x1"
  xattrs_dump "$O2" >"$x2"
  if ! diff -u "$x1" "$x2" >/dev/null; then
    print_section "XATTR mismatch:"
    diff -u "$x1" "$x2" || true
  fi
  rm -f "$x1" "$x2"

elif [[ "$T1" == "dir" ]]; then
  # 0) Quick strong digest signal (if different, we *know* something differs)
  d1="$(dir_tar_digest "$O1" || true)"
  d2="$(dir_tar_digest "$O2" || true)"
  if [[ -n "$d1" && -n "$d2" && "$d1" != "$d2" ]]; then
    print_section "TREE digest mismatch (bsdtar stream incl. ACLs/xattrs/metadata):"
    print -- "  $O1  digest=$d1"
    print -- "  $O2  digest=$d2"
  fi

  # 1) Metadata differences (mtimes/ctimes/perms/owner/flags/etc.)
  m1="$(tmpfile)"; m2="$(tmpfile)"
  dir_stat_manifest "$O1" >"$m1"
  dir_stat_manifest "$O2" >"$m2"
  if ! diff -u "$m1" "$m2" >/dev/null; then
    print_section "METADATA mismatch (stat manifest diff):"
    diff -u "$m1" "$m2" || true
  fi
  rm -f "$m1" "$m2"

  # 2) Extended attributes differences across the whole tree
  xd1="$(tmpfile)"; xd2="$(tmpfile)"
  dir_xattrs_dump "$O1" >"$xd1"
  dir_xattrs_dump "$O2" >"$xd2"
  if ! diff -u "$xd1" "$xd2" >/dev/null; then
    print_section "XATTR mismatch (tree xattr diff):"
    diff -u "$xd1" "$xd2" || true
  fi
  rm -f "$xd1" "$xd2"

else
  # Symlink/other
  if [[ -L "$O1" ]]; then
    l1="$(readlink "$O1" || true)"
    l2="$(readlink "$O2" || true)"
    if [[ "$l1" != "$l2" ]]; then
      print_section "SYMLINK TARGET mismatch:"
      print -- "  $O1 -> $l1"
      print -- "  $O2 -> $l2"
    fi
  fi

  s1="$(stat -f '%N|%HT|%Sp|%u|%g|%z|%m|%c|%f|%i' "$O1" 2>/dev/null || true)"
  s2="$(stat -f '%N|%HT|%Sp|%u|%g|%z|%m|%c|%f|%i' "$O2" 2>/dev/null || true)"
  if [[ "$s1" != "$s2" ]]; then
    print_section "STAT mismatch:"
    print -- "  $s1"
    print -- "  $s2"
  fi

  x1="$(tmpfile)"; x2="$(tmpfile)"
  xattrs_dump "$O1" >"$x1"
  xattrs_dump "$O2" >"$x2"
  if ! diff -u "$x1" "$x2" >/dev/null; then
    print_section "XATTR mismatch:"
    diff -u "$x1" "$x2" || true
  fi
  rm -f "$x1" "$x2"
fi

# If nothing printed, they're identical (as far as these checks go).
if [[ "$printed_any" == "no" ]]; then
  exit 0
else
  exit 1
fi
