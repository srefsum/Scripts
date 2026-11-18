#!/bin/sh


add_json_field() {
    local json_struct="$1"
    local field_key="$2"
    local field_val="$3"

    printf "%s\n" "$json_struct" |awk -v key="$field_key" -v val="$field_val" '
    {
        lines[NR] = $0
    }
    END {
        for (i = 1; i < NR; i++) {
            line = lines[i]
            if (i == NR - 1 && line !~ /,$/) {
                line = line ","
            }
            print line
        }

        if (val ~ /^[0-9]+(\.[0-9]+)?$/ || val == "true" || val == "false" || val == "null") {
            printf "    \"%s\": %s\n", key, val
        } else {
            printf "    \"%s\": \"%s\"\n", key, val
        }

        print lines[NR]
    }'
}


remove_json_field() {
    local json_struct="$1"
    local field_key="$2"

    printf '%s\n' "$json_struct" | awk -v target="$field_key" '
    BEGIN {
        pat = "^[[:space:]]*\"" target "\"[[:space:]]*:"
    }
    {
        lines[NR] = $0
    }
    END {
        target_start = 0
        target_end = 0

        # 1. Find the starting line of the target field
        for (i = 1; i <= NR; i++) {
            if (!target_start && lines[i] ~ pat) {
                target_start = i
                target_end = i
                break
            }
        }

        if (target_start > 0) {
            open_braces = 0
            open_brackets = 0

            # 2. Track braces/brackets to find where the field value ends (handles multi-line objects/arrays)
            for (i = target_start; i <= NR; i++) {
                line = lines[i]
                for (j = 1; j <= length(line); j++) {
                    c = substr(line, j, 1)
                    if (c == "{") open_braces++
                    else if (c == "}") open_braces--
                    else if (c == "[") open_brackets++
                    else if (c == "]") open_brackets--
                }
                if (open_braces <= 0 && open_brackets <= 0) {
                    target_end = i
                    break
                }
            }

            # 3. Rebuild the array excluding the target lines
            k = 0
            for (i = 1; i <= NR; i++) {
                if (i >= target_start && i <= target_end) {
                    continue
                }
                k++
                keep[k] = lines[i]
            }

            # 4. Print lines and remove any illegal trailing commas before closing braces/brackets
            for (i = 1; i <= k; i++) {
                line = keep[i]
                if (i < k && keep[i+1] ~ /^[[:space:]]*[\}\]]/) {
                    sub(/,[[:space:]]*$/, "", line)
                }
                print line
            }
        } else {
            # Field not found, print original JSON
            for (i = 1; i <= NR; i++) {
                print lines[i]
            }
        }
    }'
}


embed_json_field() {
    local json1="$1"
    local json2="$2"
    local field_key="$3"

    # Pass json2 via the environment to safely handle multi-line strings without escaping issues
    export JSON2="$json2"
        printf '%s\n' "$json1" | awk -v key="$field_key" '
    {
        lines[NR] = $0
    }
    END {
        # 1. Print all lines of json1 up to the second-to-last, adding a comma if missing
        for (i = 1; i < NR; i++) {
            line = lines[i]
            if (i == NR - 1 && line !~ /,$/) {
                line = line ","
            }
            print line
        }

        # 2. Print the new field key and opening brace for the nested object
        printf "    \"%s\": {\n", key

        # 3. Parse json2 lines, strip outer braces if present, and indent them
        n = split(ENVIRON["JSON2"], j2_lines, "\n")
        start = 1
        end = n

        # Clean up trailing empty lines
        while (end > 0 && j2_lines[end] == "") end--
        while (start <= end && j2_lines[start] ~ /^[[:space:]]*$/) start++

        # Strip outer braces from json2 if it is a full object
        if (start <= end && j2_lines[start] ~ /^[[:space:]]*\{/) {
            sub(/^[[:space:]]*\{/, "", j2_lines[start])
        }
        if (end >= start && j2_lines[end] ~ /\}[[:space:]]*$/) {
            sub(/\}[[:space:]]*$/, "", j2_lines[end])
        }

        # Print the inner lines with nested indentation
        for (j = start; j <= end; j++) {
            if (j2_lines[j] !~ /^[[:space:]]*$/) {
                print "        " j2_lines[j]
            }
        }

        # 4. Close the embedded object and print json1 final closing brace
        print "    }"
        print lines[NR]
    }'
}


compact_json() {
    local json_struct="$1"

    printf '%s\n' "$json_struct" | awk '
    {
        body = body "\n" $0
    }
    END {
        len = length(body)
        out = ""
        in_str = 0
        escape = 0

        for (i = 1; i <= len; i++) {
            c = substr(body, i, 1)

            if (in_str) {
                if (escape) {
                    escape = 0
                } else if (c == "\\") {
                    escape = 1
                } else if (c == "\"") {
                    in_str = 0
                }
                out = out c
            } else {
                if (c == "\"") {
                    in_str = 1
                    out = out c
                } else if (c ~ /[[:space:]]/) {
                    # Skip whitespace/newlines outside of strings
                    continue
                } else {
                    out = out c
                }
            }
        }
        print out
    }'
}

expand_json() {
    local json_struct="$1"

    printf '%s\n' "$json_struct" | awk '
    {
        body = body "\n" $0
    }
    END {
        len = length(body)
        out = ""
        in_str = 0
        escape = 0
        indent_level = 0
        indent_str = "    " # 4 spaces per indentation level

        for (i = 1; i <= len; i++) {
            c = substr(body, i, 1)

            if (in_str) {
                if (escape) {
                    escape = 0
                } else if (c == "\\") {
                    escape = 1
                } else if (c == "\"") {
                    in_str = 0
                }
                out = out c
            } else {
                if (c == "\"") {
                    in_str = 1
                    out = out c
                } else if (c ~ /[[:space:]]/) {
                    # Skip existing whitespace outside of strings
                    continue
                } else if (c == "{" || c == "[") {
                    out = out c "\n"
                    indent_level++
                    for (k = 0; k < indent_level; k++) out = out indent_str
                } else if (c == "}" || c == "]") {
                    out = out "\n"
                    indent_level--
                    for (k = 0; k < indent_level; k++) out = out indent_str
                    out = out c
                } else if (c == ",") {
                    out = out c "\n"
                    for (k = 0; k < indent_level; k++) out = out indent_str
                } else if (c == ":") {
                    out = out c " "
                } else {
                    out = out c
                }
            }
        }
        print out
    }'
}



CurrentStruct='{
    "test": "long",
    "value": 4,
    "color0": "green"
}'

NewStruct='{
    "test1": "long",
    "value1": 4,
    "color01": "green"
}'


UpdatedStruct=$(add_json_field "$CurrentStruct" "newValuE" "myval")
UpdatedStruct=$(add_json_field "$UpdatedStruct" "this" 34)
UpdatedStruct=$(embed_json_field "$UpdatedStruct"  "$NewStruct" "that")
CurrentStruct=$(embed_json_field "$UpdatedStruct"  "$NewStruct" "this")
CompactStruct=$(compact_json "$CurrentStruct")
NewExpanded=$(expand_json "$CompactStruct")

printf "%s\n" "$CurrentStruct"
printf "%s\n" "$CompactStruct"
printf "%s\n" "$NewExpanded"

NewExpandedRemoved=$(remove_json_field "$NewExpanded" "that")
NewExpandedRemoved=$(remove_json_field "$NewExpandedRemoved" "this")
NewExpandedRemoved=$(remove_json_field "$NewExpandedRemoved" "this")

printf "%s\n" "$NewExpandedRemoved"
