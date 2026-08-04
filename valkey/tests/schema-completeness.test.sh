#!/usr/bin/env bash
# Test to ensure all values.yaml properties are defined in values.schema.json.
# Requires: bash 4+, yq, jq

set -euo pipefail

readonly mydir=${0%/*}

readonly values_yaml_path="$mydir/../values.yaml"
readonly values_schema_path="$mydir/../values.schema.json"

declare -A schema_keys
declare -A open_objects

while IFS= read -r line
do
    if [[ $line == OPEN:* ]]
    then
        open_objects[${line#OPEN:}]=1
    else
        schema_keys[$line]=1
    fi
done < <(
    jq --raw-output '
        . as $root
        |
        def resolve:
            if type == "object" and has("$ref")
            then
                .["$ref"] as $ref
                |
                if $ref | startswith("#/")
                then
                    $root
                    |
                    getpath(
                        $ref
                        |
                        sub("^#/"; "")
                        |
                        split("/")
                        |
                        map(gsub("~1"; "/") | gsub("~0"; "~"))
                    )
                else
                    error("unsupported non-local schema reference: \($ref)")
                end
            else
                .
            end
        ;
        def get_props($path):
            resolve
            |
            .properties // {}
            |
            to_entries[]
            |
            (
                $path + (
                    if $path == ""
                    then
                        ""
                    else
                        "."
                    end
                ) + .key
            ) as $full
            |
            (.value | resolve) as $value
            |
            $full,
            if $value.type == "object"
            then
                if $value.properties
                then
                    $value
                    |
                    get_props($full)
                else
                    "OPEN:\($full)"
                end
            else
                empty
            end
        ;
        get_props("")
    ' -- "$values_schema_path"
)

readarray -t values_keys < <(
    yq \
        '.. | path | join(".")' \
        -- \
        "$values_yaml_path" \
    |
    grep \
        --extended-regexp \
        --invert-match \
        '(^|\.)[0-9]+($|\.)|^$' \
    |
    sort \
        --unique
)

declare -a missing=()
for key in "${values_keys[@]}"
do
    if [[ -v schema_keys[$key] ]]
    then
        continue
    fi

    parent=$key
    while [[ $parent == *.* ]]
    do
        parent=${parent%.*}
        if [[ -v open_objects[$parent] ]]
        then
            continue 2
        fi
    done

    missing+=("$key")
done

if ((${#missing[@]} != 0))
then
    printf '%u properties in `values.yaml` missing from `values.schema.json`:\n' "${#missing[@]}" >&2
    printf ' - %s\n' "${missing[@]}" >&2
    exit 1
fi
