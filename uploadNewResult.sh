#!/bin/bash

##########################################################################################
# Script Name: uploadNewWPTResult.sh
# Description: This script uploads new WPT (Web Platform Tests) results to the repository.
# Author: Gyuyoung Kim
# Date: 2024-04-25
# Version: 1.0
##########################################################################################

print_error() {
  echo "Error: $1" >&2
  exit 1
}

show_usage() {
  echo "usage: uploadNewWPTResult.sh [result file]"
  echo "  e.g) ./uploadNewWPTResult.sh ../wpt-runner-results/result_b847b1030f779d681c955f397a6e36bf6808cd41_1.3.4.json"
  echo ""
  echo "usage: uploadNewWPTResult.sh [option]"
  echo "options:"
  echo "  --show-revisions                                Show short revisions of WPT tested in all other browsers"
  echo "  --get-full-revision-from [short revision]       Get a full revision corresponding to the given short revision"
  exit 1
}

if [ $# -eq 0 ]; then
  print_error "No argument. You can check the usages by '--help' option."
fi

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  show_usage
fi


# Check if arguments are valid.

valid_args=(" .json" "--show-revisions" "--get-full-revision-from")
is_valid_arg=false
if [[ "$1" == *.json ]]; then
  is_valid_arg=true
elif [[ "$1" == "--show-revisions" || "$1" == "--get-full-revision-from" ]]; then
  is_valid_arg=true
fi

if ! $is_valid_arg; then
  print_error "Unsupported argument. Please check the usages by '--help' option."
fi


# Support '--show-revisions' and '--get-full-revision-from' arguments.

if [ "$1" == "--show-revisions" ]
then
  sha_url="https://wpt.fyi/api/shas?label=master&max-count=100&from=2024-03-21T00%3A00&product=chrome%5Bexperimental%5D&product=firefox%5Bexperimental%5D&product=safari%5Bexperimental%5D&product=chrome_android&aligned"
  sha_list=$(curl -s "$sha_url")
  echo "$sha_list"
  exit 1
fi

if [ "$1" == "--get-full-revision-from" ]
then
  if [ -z "$2" ]; then
    echo "Error: This option needs a short revision in the second argument. You can find short revisions through '--show-revisions' option"
    echo "Usage: ./uploadNewWPTResult.sh --get-full-revision-from [short revision]"
    exit 1
  fi

  chrome_run_data=$(curl -s "https://wpt.fyi/api/run?sha=$2&label=experimental&aligned&product=chrome")
  full_revision_hash=$(echo "${chrome_run_data}" | jq -r '.full_revision_hash')

  echo "Full revision hash: ${full_revision_hash}"
  echo "Suggested a result file name for this revision: result_${full_revision_hash}_1.3.4.json"
  exit 1
fi

file_name=$(basename "$1")
IFS='_' read -r result wpt_revision browser_version <<< "$file_name"

runs_file="runs.json"
products=("chrome" "chrome_android" "firefox" "safari")
short_wpt_revision="${wpt_revision:0:10}" 
summary_file_name=huawei_browser-$short_wpt_revision-summary_v2.json.gz
result_url="https://raw.githubusercontent.com/Gyuyoung/wpt-results-for-dashboard/main/summary-results/$summary_file_name"
browser_version="${browser_version%.json}"

echo "  - The result filename: $file_name"
echo "  - wpt full revision: $wpt_revision"
echo "  - browser version: $browser_version"
echo "  - result_url: $result_url"


# Check if the wpt dashboard has WPT results for the given wpt revision.

echo "> Check if wpt dashboard has WPT results for $short_wpt_revision WPT commit on chrome, chrome_android, firefox, and safari."

error_found=false

for product in "${products[@]}"; do
  api_url="https://wpt.fyi/api/shas?label=experimental&aligned&product=$product"

  json_data=$(curl -s "$api_url")
  contains_revision=$(echo "$json_data" | jq '.[] | select(index("'$short_wpt_revision'"))')

  if [ -z "$contains_revision" ]; then
      echo "  '$short_wpt_revision' commit was not tested by $product wpt.fyi."
      error_found=true
  fi
done

if [ "$error_found" = true ]; then
  echo "> Exit uploading a new WPT result. Please check the WPT commit revision again."
  exit 1
else
  echo "> The wpt dashboard tested the WPT $short_wpt_revision commit on the all browsers."
fi


# Update the other default browsers data.

echo "> Update Chrome, Chrome Android, Firefox, and Safari browser's WPT results for $short_wpt_revision commit."
base_api_url="https://wpt.fyi/api/run?sha=$short_wpt_revision&label=experimental&aligned&product="

for product in "${products[@]}"; do
  old_info=$(cat "$runs_file")
  api_url="$base_api_url$product"
  new_info=$(curl -s "$api_url")
  trimmed_data=$(echo "$old_info" | sed 's/^\[\|\]$//g')
  updated_info="[
  $new_info,$trimmed_data
]"

  echo "$updated_info" > "$runs_file"
  echo "  runs.json is updated by $product information."
done


# Update the Huawei browser json data fields.

echo "> Update Huawei browser's WPT result for $short_wpt_revision commit."

old_info=$(cat runs.json)
SEED=$(date +%s)
LC_ALL=C
new_id=$(echo "$SEED" | sha256sum | tr -dc '1-9' | head -c 15)
first_digit=$(echo "$SEED" | sha256sum | tr -dc '1-9' | head -c 1)
new_id="${first_digit}${new_id}"

chrome_run_data=$(curl -s "https://wpt.fyi/api/run?sha=$short_wpt_revision&label=experimental&aligned&product=chrome")
time_created=$(echo "${chrome_run_data}" | jq -r '.created_at')
time_start=$(echo "${chrome_run_data}" | jq -r '.time_start')
time_end=$(echo "${chrome_run_data}" | jq -r '.time_end')

huawei_browser_info=$(cat <<EOF
{"id":$new_id,"browser_name":"huawei_browser","browser_version":"$browser_version","os_name":"openharmony","os_version":"3.2.3","revision":"$short_wpt_revision","full_revision_hash":"$wpt_revision","results_url":"$result_url","created_at":"$time_created","time_start":"$time_start","time_end":"$time_end","raw_results_url":"$result_url","labels":["experimental","master","huawei_browser"]}
EOF
)

trimmed_data=$(echo "$old_info" | sed 's/^\[\|\]$//g')
updated_info="[
  $huawei_browser_info,$trimmed_data
]"

echo "$updated_info" > "$runs_file"


# Convert the WPT result generated by the WPT runner to the summary format processed by the wpt dashboard tool.

echo "> Convert the runner WPT result to the summary format for the wpt dashboard tool."

WPT_FYI_PATH=$HOME/github/wpt.fyi-feasibility
$WPT_FYI_PATH/results-processor/wptreport.py --summary $summary_file_name $1
gunzip $summary_file_name
mv ${summary_file_name%.gz} $summary_file_name
mv $summary_file_name ./summary-results


# Push the new WPT result to the repository.

echo "> Push the new WPT result to the repository."

git add ./summary-results/$summary_file_name runs.json
git commit -m "Add a new wpt result on $short_wpt_revision"
git push origin main:main -f

