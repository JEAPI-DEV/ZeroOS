#!/bin/bash
# generic_symbols.sh
# Usage: ./generate_symbols.sh <kernel_binary> <output_zig_file>

KERNEL_BIN=$1
OUTPUT_FILE=$2

if [ -z "$KERNEL_BIN" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 <kernel_binary> <output_zig_file>"
    exit 1
fi

echo "Generating symbols from $KERNEL_BIN to $OUTPUT_FILE..."

# Parse nm output
# Format: <address> <type> <name>
# We filter for T (text) and t (static text) symbols mainly.
# We explicitly sort by address.
nm -n "$KERNEL_BIN" | grep -i " [t] " | awk '{print $1 " " $3}' > "$OUTPUT_FILE"

echo "Done."
