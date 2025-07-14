#!/bin/sh

# 2025-07-13 - André Chalella
#
# This reads all .nft files in a given directory and
# idempotently applies or removes their nftables rules.
# To be used as a systemd service (start/reload/stop).
#
# Basic idea: for each file, extract the table names and
#   - remove the tables (without error if they don't exist)
#   - if 'start' or 'reload', apply the file with `nft -f`
#
# We also record the created tables in a temporary file,
# so we don't forget to clean them on reload|stop even if the
# .nft files are changed.
#
# Caveat: be careful to use unique table names in the .nft
# files, or else we'll delete tables used by others.

set -eu

NFT=/usr/sbin/nft
SUFFIX=.idempotent-nftables

info() {
    >&2 echo "$@"
}

die() {
    [ $# -eq 0 ] || info "$@"
    exit 1
}

[ -x "$NFT" ] || die "Cannot execute $NFT"

basename=$(basename "$0")
usage() {
    info "Usage: $basename <start|reload|stop|test> [directory]"
    info "  [directory] must contain the nftables files with the .nft suffix"
    info "  'test' mode: just outputs table names"
    die
}

[ $# -eq 1 ] || [ $# -eq 2 ] || usage
case $1 in
    start|reload|stop|test) ;;
    *) usage ;;
esac

if [ $# -eq 2 ]; then
    [ -d "$2" ] || usage
    dir=$2
else
    dir=$(dirname "$0")
    [ -d "$dir" ] || usage

    # Using $0 is problematic, so let's do a quick sanity check
    [ 1 = "$(find "$dir" -type f -name "$basename" | head -n 1 | wc -l)" ] || \
        die "Couldn't reliably determine directory from \$0 = $0"
fi

# Extracts the table(s) mentioned by a file. Returns in the format "family|table"
get_tables() {
    [ $# -eq 1 ] && [ -f "$1" ] || die "Function takes one file"
    grep '^table ' "$1" | while IFS=\  read -r _ two three four _; do
        if [ "$four" = \{ ]; then
            echo "$two|$three"
        elif [ "$three" = \{ ]; then
            echo "ip|$two"
        else
            die "Unrecognized table definition in file $1"
        fi
    done
    unset _ two three four
}

# Ensures the table is cleared, regardless if it exists, without errors
# Note: nftables 1.0.7 has `nft destroy table` which doesn't error if table
# doesn't exist, but that version is not commonplace yet (2025).
del_table() {
    [ $# -eq 2 ] || die "Function takes family (like ip) and table name"
    $NFT add table "$1" "$2"
    $NFT delete table "$1" "$2"
}

# Cleans tables of last run, if a file in $TMPDIR is found.
# We go carefully, because this has the potential to erase unrelated data.
tmpdir=${TMPDIR-/tmp}
if [ "$1" != test ] && [ -n "${SUFFIX-}" ] && [ -d "$tmpdir" ]; then
    find "$tmpdir" -maxdepth 1 -type f -name "*$SUFFIX" | while IFS= read -r file; do
        while IFS=\  read -r family table _; do
            if [ -z "$table" ] || [ -n "$_" ]; then
                die "Strange line found in $file"
            else
                del_table "$family" "$table"
            fi
            unset family table _
        done < "$file"
        rm -- "$file"
        unset file
    done
fi

if [ "$1" = start ] || [ "$1" = reload ]; then
    start_or_reload=1
else
    start_or_reload=
fi
tmp=$(mktemp --suffix="$SUFFIX")
ret=

# Loop through each .nft in dir
nfts=$(find "$dir" -type f -name '*.nft')
while IFS= read -r file; do
    for table in $(get_tables "$file"); do
        # Split family|table
        IFS=\| read -r family table <<EOF
$table
EOF
        if [ "$1" = test ]; then
            echo "$(basename "$file"): $family $table"
        else
            del_table "$family" "$table"
            [ -z $start_or_reload ] || echo "$family $table" >> "$tmp"
        fi

        unset family table
    done

    if [ -n "$start_or_reload" ]; then
        if ! $NFT -f "$file"; then
            # we must remember if there was a failure to exit accordingly
            ret=1
        fi
    fi

    unset file
done <<EOF
$nfts
EOF

# Clean the temp file if empty
[ -s "$tmp" ] || rm -- "$tmp"

# Exit with error code if nft -f had errors
[ -z "$ret" ] || exit 1
