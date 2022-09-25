#!/bin/bash

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

# Find all matching JAVA args containing both Xms and Xmx
matching_java_args=$(grep -Hnr --include="*.conf" 'Xms.*Xmx\|Xmx.*Xms' .)

# Convert matching_java_args to array of strings
IFS=$'\n' read -r -a all_matches <<< "$matching_java_args"

# If there are 0 match on a Java repo then that means we don't have the configuration, return error
if (( ${#all_matches} == 0 )); then
    echo "{\"output\": \"No Java Args with Xmx and Xms configuration found!\"}"
    exit 0
fi

for match in "${all_matches[@]}"
do
    
done

