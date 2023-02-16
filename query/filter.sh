#!/bin/bash

REPOSJSON=${1:-"repos.json"}

search() {
    BUILD=$1
    jq ".repos[] | select( any(.; .repo.languages.nodes[].name == \"$BUILD\") )" $REPOSJSON | jq -r '.repo.nameWithOwner' >> matching-repos.txt
}

if [ ! -f $REPOSJSON ]; then
    echo "Please specify input (repos.json)"
    exit 1
fi

search M4
search CMake
search Meson

REPOS=$(cat matching-repos.txt | sort -u)

rm matchin-repos.txt

JSON="["
for repo in $REPOS; do
    JSON+="{\"repo\":\"$repo\"},"
done
JSON="${JSON%?}"
JSON+="]"

echo $JSON
