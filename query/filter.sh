#!/bin/bash

REPOSJSON=${1:-"repos.json"}

search() {
    BUILD=$1
    jq ".repos[] | select( any(.; .repo.languages.nodes[].name == \"$BUILD\") )" $REPOSJSON | jq -r '.repo.nameWithOwner'
    echo " "
}

if [ ! -f $REPOSJSON ]; then
    echo "Please specify input (repos.json)"
    exit 1
fi

REPOS=$(search M4)
REPOS+=$(search CMake)
REPOS+=$(search Meson)

REPOS=$(echo $REPOS | sort -u)

JSON="["
for repo in $REPOS; do
    JSON+="{\"repo\":\"$repo\"},"
done
JSON="${JSON%?}"
JSON+="]"

echo $JSON
