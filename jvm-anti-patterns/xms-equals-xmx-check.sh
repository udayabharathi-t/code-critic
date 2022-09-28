#!/bin/bash

# parse_yaml is a function to parse yaml files. 
# Note: this is not a full fledged implementation. This won't work for array cases.
# Expects YAML file's indentation to be 2 spaces all the time.
# Usage: parse_yaml "/path/to/file.yaml" <optional prefix for exported configs>
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

# find_index_of_substring is a function to find a substring in a string and return index.
# Usage: find_index_of_substring "<actual string>" "<string to find>" "<start index>"
# echoes first occurrence if substring exists else echoes -1.
function find_index_of_substring {
    local start string substring len pos
    start="$3"
    if [[ -z $start ]]; then
        start="1"
    fi
    string="$1"
    substring="$2"

    len="${#string}"

    # strip start-1 characters
    string="${string:start-1}"

    # strip the first substring and everything beyond
    string="${string%%"$substring"*}"

    # the position is calculated
    pos=$((start+${#string}))

    # if it's more than the original length, it means "not found"
    if [ "$pos" -gt "$len" ]; then
       echo "-1"
    else
       echo "$pos"
       return 0
    fi
}

# convert_app_yaml_memory_to_bytes is a function to convert app.yaml's infra_compute_memory to bytes.
# Supports following suffixes: Gi, gi, Mi, mi
# Usage: convert_app_yaml_memory_to_bytes "<Value of app.yaml's infra_compute_memory>"
# echoes value in bytes.
function convert_app_yaml_memory_to_bytes {
    local val suffix num
    val=$1

    # Extract the prefix number
    num=${val:0:${#val}-2}

    # Extract the suffix character
    suffix=${val:${#val}-2:${#val}}

   if [ "$suffix" == "Gi" ] || [ "$suffix" == "gi" ]; then
       echo $(($num*1000*1000*1000))
   elif [ "$suffix" == "Mi" ] || [ "$suffix" == "mi" ]; then
       echo $(($num*1000*1000))
   fi
}

# convert_xm_val_to_bytes is a function to convert -Xm_ value to bytes. Supports following suffixes: 
# G, g, M, m, K, k
# Usage: convert_xm_val_to_bytes "<Value of Xms or Xmx>"
# echoes value in bytes.
function convert_xm_val_to_bytes {
    local val suffix num
    val=$1

    # Extract the prefix number
    num=${val:0:${#val}-1}

    # Extract the suffix character
    suffix=${val:${#val}-1:${#val}}

   if [ "$suffix" == "G" ] || [ "$suffix" == "g" ]; then
       echo $(($num*1000*1000*1000))
   elif [ "$suffix" == "M" ] || [ "$suffix" == "m" ]; then
       echo $(($num*1000*1000))
   elif [ "$suffix" == "K" ] || [ "$suffix" == "k" ]; then
       echo $(($num*1000));
   fi
}

# get_xm_as_bytes fetches specified configuration either -Xms or -Xmx value as bytes.
# Usage: get_xm_as_bytes "<x or s>" "<actual java args string>"
# echoes Xms or Xmx value as bytes given the java args and config type.
function get_xm_as_bytes {
    local config_type java_args config index_of_config config_len index_of_space_after_config start_index end_index actual_value
    config_type=$1
    java_args="$2"

    config="-Xm${config_type}"
    config_len=4

    index_of_config=$(find_index_of_substring "$java_args" $config 1)

    index_of_space_after_config=$(find_index_of_substring "$java_args" " " $index_of_config)

    # If the configuration is specified dead last.
    if [[ $index_of_space_after_config -eq -1 ]]; then
        re_for_number='^[0-9]+$'
        for (( i=$index_of_config+$config_len-1; i<${#java_args}; i++ )); do
            if ! [[ "${java_args:$i:1}" =~ $re_for_number ]] ; then
                index_of_space_after_config=i
            fi
        done
    fi

    start_index=$index_of_config+$config_len-1
    end_index=$index_of_space_after_config-$index_of_config-$config_len
    actual_value="${java_args:$start_index:$end_index}"

    echo $(convert_xm_val_to_bytes $actual_value)
}

# get_file_path_from_grep_match is a function used to fetch the file path from a grep match output
# Usage: get_file_path_from_grep_match <grep match>
function get_file_path_from_grep_match {
    local match index_of_first_colon
    match=$1

    index_of_first_colon=$(find_index_of_substring "$match" ":" 1)
    echo "${match:0:$index_of_first_colon-1}"
}

# line_number_from_grep_match is a function used to fetch the line number from a grep match output.
# Usage: line_number_from_grep_match <grep match>
function line_number_from_grep_match {
    local match index_of_first_colon index_of_second_colon
    match=$1

    index_of_first_colon=$(find_index_of_substring "$match" ":" 1)
    index_of_second_colon=$(find_index_of_substring "$match" ":" index_of_first_colon+1)
    echo "${match:index_of_first_colon:index_of_second_colon-index_of_first_colon-1}"
}

# exec_antipattern_check_for_conf is a function which actually handles the anti pattern check for a 
# given matching Java Args output.
# Usage: exec_antipattern_check_for_conf <JAVA Args> <actual memory allocated>
function exec_antipattern_check_for_conf {
    local match xmx_val xms_val actual_memory_allocated file_path line_number
    match=$1
    actual_memory_allocated=$2
    file_path=$(get_file_path_from_grep_match "$match")
    line_number=$(line_number_from_grep_match "$match")

    xmx_val=$(get_xm_as_bytes x "$match")
    xms_val=$(get_xm_as_bytes s "$match")

    # echo "DEBUG: File: $file_path, Line number: $line_number, Xmx: $xmx_val bytes, Xms: $xms_val bytes, Actual memory: $actual_memory_allocated bytes"

    # Check if -Xmx configuration is equal to -Xms configuration.
    if [[ $xmx_val -ne $xms_val ]]; then
        echo "Xmx value ($xmx_val bytes) is not equal to Xms ($xms_val bytes) value at file: $file_path, line:$line_number"
    fi

    # Check if at least 1 GB of space is left for system process.
    if [[ $xmx_val+1000000000 -gt $actual_memory_allocated ]]; then
        echo "At least 1 GB of memory should be left for the system processes. Xmx is configured too high comparing to actual memory allocated. Xmx: $xmx_val, Actual memory: $actual_memory_allocated at file: $file_path, line:$line_number"
    fi
}

# exec_antipattern_check_for_file is a function which executes anti pattern check on every match 
# found in a given conf directory path
# Usage: exec_antipattern_check_for_conf_path <Path to conf> <actual memory allocated>
function exec_antipattern_check_for_conf_path {
    local matching_java_args all_matches path_to_check actual_memory_allocated
    path_to_check=$1
    actual_memory_allocated=$2

    # Find all matching JAVA args containing both Xms and Xmx
    matching_java_args=$(grep -Hnr --include="*.conf" 'Xms.*Xmx\|Xmx.*Xms' $path_to_check)

    # If there are 0 match on a Java repo then that means we don't have the configuration, return error
    if [[ -z $matching_java_args ]]; then
        echo "{\"output\": \"No Java Args with Xmx and Xms configuration found on conf directory at path: $path_to_check!\"}"
    fi

    # Execute antipattern check for each match.
    echo "$matching_java_args" | while read match ; do exec_antipattern_check_for_conf "$match" $actual_memory_allocated ; done

}

# process_yaml is a function which processes a given service definition app yaml file and 
# executes anti pattern check on the configured conf directory with the mentioned infra 
# compute memory.
# Note: if given yaml file doesn't have infra.compute.memory or envVar.config.ref configuration,
# this function will simply skip processing for that file.
# Usage: process_yaml <path to app.yaml>
function process_yaml {
    local yaml_file infra_compute_memory envVar_config_ref
    yaml_file=$1

    # Parse yaml file.
    eval $(parse_yaml $yaml_file)

    # Check if infra compute memory is present in the yaml.
    if [[ -z $infra_compute_memory ]]; then
        return
    fi

    # Check if conf directory path is specified in the yaml.
    if [[ -z $envVar_config_ref ]]; then
        return
    fi

    # echo "==========Processing $yaml_file==========="

    # Compute actual memory specified in service definition as bytes.
    infra_compute_memory=$(convert_app_yaml_memory_to_bytes $infra_compute_memory)

    # Execute anti pattern checks.
    exec_antipattern_check_for_conf_path $envVar_config_ref $infra_compute_memory

    # echo "==========Processed $yaml_file==========="

    # Reset for next iteration
    infra_compute_memory=""
    envVar_config_ref=""
}

# Find all yaml files available in the repo and process for each file.
for yaml in $(find . -name "*.yaml" -or -name "*.yml"); do
    process_yaml $yaml
done

