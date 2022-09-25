#!/bin/bash

function split_by_newline {
    local str IFS
    str=$1
    IFS=$'\n'
    split_str=($str)
    echo $split_str
}

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

    start_index=$index_of_config+$config_len-1
    end_index=$index_of_space_after_config-$index_of_config-$config_len
    actual_value="${java_args:$start_index:$end_index}"

    echo $(convert_xm_val_to_bytes $actual_value)
}

function exec_antipattern_check {
    local matching_java_args all_matches path_to_check actual_memory_allocated
    path_to_check=$1
    actual_memory_allocated=$2

    echo "Inside dir $path_to_check with memory allocation $actual_memory_allocated"

    # Find all matching JAVA args containing both Xms and Xmx
    matching_java_args=$(grep -Hnr --include="*.conf" 'Xms.*Xmx\|Xmx.*Xms' $path_to_check)

    # Convert matching_java_args to array of strings
    all_matches=$(split_by_newline "$matching_java_args")

    # If there are 0 match on a Java repo then that means we don't have the configuration, return error
    if (( ${#all_matches[@]} == 0 )); then
        echo "{\"output\": \"No Java Args with Xmx and Xms configuration found!\"}"
        exit 0
    fi

    for match in "${all_matches[@]}"
    do
        echo "Executing anti-pattern check on $match"
    done
}

# Find all yaml files available in the repo.
all_yaml_files=$(find . -name "*.yaml" -or -name "*.yml")

# Convert the same to array.
all_matching_ymls=$(split_by_newline $all_yaml_files)

# Loop through all matching yaml files and execute anti-pattern.
for yaml_file in "${all_matching_ymls[@]}"
do
    echo "Checking file $yaml_file"

    # Parse yaml file.
    eval $(parse_yaml $yaml_file)

    # Check if infra compute memory is present in the yaml.
    if [[ -z $infra_compute_memory ]]; then
        continue
    fi

    # Check if conf directory path is specified in the yaml.
    if [[ -z $envVar_config_ref ]]; then
        continue
    fi

    # Compute actual memory specified in service definition as bytes.
    infra_compute_memory=$(convert_app_yaml_memory_to_bytes $infra_compute_memory)

    # Execute anti pattern checks.
    exec_antipattern_check $envVar_config_ref $infra_compute_memory

    # Reset for next iteration
    infra_compute_memory=""
    envVar_config_ref=""
done

