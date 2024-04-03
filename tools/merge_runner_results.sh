#!/bin/bash

# Merge runner-result.json files into one runner-result.json

merged_json="./merged_runner_results.json"

echo "{ \"results\": [" > "$merged_json"

find . -type f -name "*.json" | while read -r json_file; do
    if [ "$json_file" != "$merged_json" ]; then
        if [ -s "$json_file" ]; then
            echo "- json file = $json_file"
            jq -c '.results[]' "$json_file" |  sed 's/^\[/\n  [/; $ ! s/$/,/' >> "$merged_json"
            echo "," >> "$merged_json"
        fi
    fi
done

sed -i '$s/,$//' "$merged_json"
echo -e "\n]}" >> "$merged_json"

echo "Merged results saved in $merged_json"

