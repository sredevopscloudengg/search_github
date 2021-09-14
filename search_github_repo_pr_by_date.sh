#!/bin/bash

# this program will search the github repo's for pull requests using a specific search criteria defined in the app.config file and will send a pr summary report to a user's email address
# app.config: this is a configuration file for this program that contains values for github token, api_endpoint, org, repo, start_date, end_date, user_email and etc.
# pr_states.txt: this is one of the input files that contains values pr states : (open, closed)
# pr_dates.txt: this is one of the input files that contains values pr date types : (created, updated)

#usage(without debug output) : <path_to_program>/search_github_repo_pr_by_date.sh <path_to_config>/app.config <path_to_input>/pr_states.txt <path_to_input>/pr_dates.txt
#example(same directory): ./search_github_repo_pr_by_date.sh app.config pr_states.txt pr_dates.txt
#example(different directory): /tmp/search_github_repo_pr_by_date.sh /tmp/app.config /tmp/pr_states.txt /tmp/pr_dates.txt

#usage(with debug output) : <path_to_program>/search_github_repo_pr_by_date.sh <path_to_config>/app.config <path_to_input>/pr_states.txt <path_to_input>/pr_dates.txt 2>&1 | tee <path_to_output>/program_output.log
#example(same directory): ./search_github_repo_pr_by_date.sh app.config pr_states.txt pr_dates.txt 2>&1 | tee program_output.log
#example(different directory): /tmp/search_github_repo_pr_by_date.sh /tmp/app.config /tmp/pr_states.txt /tmp/pr_dates.txt 2>&1 | tee /tmp/program_output.log

# debug: used for troubleshooting
# turn off by commenting out with #
set -x

# this function reads values from the configuration file: app.config that are used throught this program
process_app_config () {
  ghub_api_token=$(jq -r '.token' $GHUB_APP_CONFIG)
  ghub_api_search_endpoint=$(jq -r '.api_endpoint' $GHUB_APP_CONFIG)
  ghub_org_name=$(jq -r '.org' $GHUB_APP_CONFIG)
  ghub_repo_name=$(jq -r '.repo' $GHUB_APP_CONFIG)
  ghub_search_start_date=$(jq -r '.start_date' $GHUB_APP_CONFIG)
  ghub_search_end_date=$(jq -r '.end_date' $GHUB_APP_CONFIG)
  #ghub_search_string=$(jq -r '.search_string' $GHUB_APP_CONFIG)
  ghub_search_results_count=$(jq -r '.search_results_count' $GHUB_APP_CONFIG)
  user_email=$(jq -r '.email' $GHUB_APP_CONFIG)
  app_dir=$(jq -r '.dir' $GHUB_APP_CONFIG)
  app_default_dir=$(jq -r '.default_dir' $GHUB_APP_CONFIG)
}

# this function creates temp directories to store output files generated by this program
create_temp_dirs () {
  parent_dir=$app_dir
  current_date_ts=$(date '+%Y%m%d_%H%M%S')
  child_dir=$current_date_ts
  new_dir="/"$parent_dir"/"$child_dir
  mkdir $new_dir
  if [ -d $new_dir ]; then
    output_dir=$new_dir
  else
    output_dir=$app_default_dir
  fi
}

# this function creates an output file that contains consolidated output generated by this program used as an input for the mail program
build_consolidated_output_file () {
  local consolidated_format="consolidated_data.txt"
  local output_file=$current_date_ts"_"$consolidated_format
  search_consolidated_output=$output_dir"/"$output_file
  touch $search_consolidated_output
}

# this function creates multiple temporary output files used by the search function to write output
build_output_file () {
  local ghub_pr_state=$1
  local ghub_pr_date_type=$2
  local file_format=$3
  local output_file=$current_date_ts"_"$ghub_pr_state"_"$ghub_pr_date_type"_"$file_format
  echo $output_file
}

# this function builds a search string used by the GitHub Search API using the values defined in the app.config file
build_search_string () {
  local ghub_pr_state=$1
  local ghub_pr_date_type=$2
  local ghub_search_string="repo:$ghub_org_name/$ghub_repo_name+is:pr+state:$ghub_pr_state+$ghub_pr_date_type:$ghub_search_start_date..$ghub_search_end_date"
  echo $ghub_search_string
}

# this function executes search using the GitHub search api
run_search () {
  local ghub_pr_state=$1
  local ghub_pr_date_type=$2
  
  ghub_search_string=$(build_search_string $ghub_pr_state $ghub_pr_date_type)
  echo "ghub_search_string: $ghub_search_string"

  #raw csv output
  local raw_format="raw_data.csv"
  local search_raw_output=$output_dir"/"$(build_output_file $ghub_pr_state $ghub_pr_date_type $raw_format)
  curl -s -H "Authorization: token $ghub_api_token" "https://$ghub_api_search_endpoint?q=$ghub_search_string&per_page=$ghub_search_results_count" | jq -r '.items[] | "\(.number),\(.html_url),\(.url)"' > "$search_raw_output"

  #pretty output
  local pretty_format="pretty_data.txt"
  local search_pretty_output=$output_dir"/"$(build_output_file $ghub_pr_state $ghub_pr_date_type $pretty_format)
  column -t -N "pr_no,pr_html_url,pr_api_endpoint" -s "," < $search_raw_output > "$search_pretty_output"

  #consolidate output
  echo "PR list with search criteria: (state:$ghub_pr_state, date_type:$ghub_pr_date_type)" >> "$search_consolidated_output"
  cat "$search_pretty_output" >> "$search_consolidated_output"
  echo " " >> "$search_consolidated_output"
}

# this is a parent search function that will loop through all values in the input files: pr_states.txt, pr_dates.txt and uses the run_search helper function to execute the search
search_pr_date_range () {
  # loop through all pull request states
  while IFS= read -r item_state; do
    local pr_state=$item_state
    while IFS= read -r item_date_type; do
      local pr_date_type=$item_date_type
  
      run_search $pr_state $pr_date_type
    
    done < "$GHUB_PR_DATES"
  done < "$GHUB_PR_STATES"
}

# this function will send an email that includes PR summary report to a user's email address defined in the app.config file
send_pr_summary_report () {
  mail -s "PR Summary Report for the date range: ($ghub_search_start_date, $ghub_search_end_date)" "$user_email" < "$search_consolidated_output"
}

# main function
main () {
  echo "##### start: main () #####"

  echo "command line arguments: "
  echo "input 1: $1"
  echo "input 2: $2"
  echo "input 3 :$3"

  #global variables
  app_config=$1
  pr_states=$2
  pr_dates=$3

  echo "***** read app config *****"
  GHUB_APP_CONFIG=$app_config
  echo "***** GHUB_APP_CONFIG: $GHUB_APP_CONFIG *****"

  echo "***** read pr states *****"
  GHUB_PR_STATES=$pr_states
  echo "***** GHUB_PR_STATES: $GHUB_PR_STATES *****"

  echo "***** read pr dates *****"
  GHUB_PR_DATES=$pr_dates
  echo "***** GHUB_PR_DATES: $GHUB_PR_DATES *****"

  
  # sub functions
  
  process_app_config

  create_temp_dirs

  build_consolidated_output_file
  
  search_pr_date_range
  
  send_pr_summary_report

  echo "##### end: main() #####"


}

# calling main function
main "$@"

# debug: used for troubleshooting
# turn off by commenting out with #
set +x

