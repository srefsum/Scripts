#!/bin/sh

# Check if directory argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <directory_path>" >&2
    exit 1
fi

DIR="$1"

# Check if the directory exists
if [ ! -d "$DIR" ]; then
    echo "Error: Directory '$DIR' does not exist." >&2
    exit 1
fi

printf "{\n"
first=1

# Iterate through files in the directory
for file in "$DIR"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        
        # Read file content and strip trailing newlines/carriage returns
        content=$(cat "$file" 2>/dev/null | tr -d '\r' | tr -d '\n')
        
        # Handle comma separation for JSON fields
        if [ "$first" -eq 1 ]; then
            first=0
        else
            printf ",\n"
        fi
        
        if [ -z "$content" ]; then
             content="none"
        fi 
        # Check if the content is a valid number (counter). 
        # If numeric, output without quotes; otherwise, treat as a string.
        case "$content" in
            ''|*[!0-9]*)
                printf '  "%s": "%s"' "$filename" "$content"
                ;;
            *)
                printf '  "%s": %s' "$filename" "$content"
                ;;
        esac
    fi
done

printf "\n}\n"
