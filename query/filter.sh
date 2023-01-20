#!/bin/bash

REPOSJSON=${1:-"repos.json"}

search() {
    BUILD=$1
    jq ".repos[] | select( any(.; .repo.languages.nodes[].name == \"$BUILD\") )" $REPOSJSON | jq -r '.repo.nameWithOwner'
}

if [ ! -f $REPOSJSON ]; then
    echo "Please specify input (repos.json)"
    exit 1
fi

REPOS=$(search M4)
REPOS+=" "
REPOS+=$(search CMake)
REPOS+=" "
REPOS+=$(search Meson)

JSON="["
for repo in $REPOS; do
    JSON+="{\"repo\":\"$repo\"},"
done
JSON="${JSON%?}"
JSON+="]"

echo $JSON
