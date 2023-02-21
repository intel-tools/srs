#!/bin/bash
RUN_ID=$1

if [ -z $RUN_ID ]; then
    echo "No run-id specified as input"
    exit 1
fi

if [ -z $GITHUB_REPOSITORY ]; then
    echo "No GITHUB_REPOSITORY env variable found"
    exit 1
fi

if [ -z $GH_TOKEN ]; then
    echo "No GH_TOKEN env variable found"
    exit 1
fi

rate_limit() {
    rl=$(gh api -H "Accept: application/vnd.github+json" /rate_limit | jq '.rate.remaining')
    echo "Rate limit remaining: $rl"
    while [ $rl -lt 150 ]; do
        sleep 1h
        rl=$(gh api -H "Accept: application/vnd.github+json" /rate_limit | jq '.rate.remaining')
        echo "Rate limit remaining: $rl"
    done
}

mkdir -p $RUN_ID

page=1
got=0
while [ true ]; do
    rate_limit
    gh api -H "Accept: application/vnd.github+json" "/repos/$GITHUB_REPOSITORY/actions/runs/$RUN_ID/artifacts?per_page=100&page=$page" > $RUN_ID/artifacts.$page.json

    total=$(jq '.total_count' $RUN_ID/artifacts.1.json)
    got=$(( page * 100 ))
    (( page++ ))

    [[ $got -lt $total ]] && continue

    break
done

for a in $(ls $RUN_ID/artifacts.*.json); do
    for b in $(jq -r '.artifacts[] | "\(.id),\(.name),\(.expired)"' $a); do
        id=$(echo $b | awk -F',' '{ print $1 }')
        name=$(echo $b | awk -F',' '{ print $2 }')
        expired=$(echo $b | awk -F',' '{ print $3 }')

        [[ $expired == "true" ]] && continue
        rate_limit
        gh api -H "Accept: application/vnd.github+json" /repos/$GITHUB_REPOSITORY/actions/artifacts/$id/zip > $RUN_ID/$name.zip || continue
        mkdir -p $RUN_ID/$name
        unzip -o -d $RUN_ID/$name $RUN_ID/$name.zip || continue
        rm $RUN_ID/$name.zip

        if [ -f $RUN_ID/$name/$name.tar.gz ]; then
            tar -xvf $RUN_ID/$name/$name.tar.gz -C $RUN_ID/$name --wildcards --no-anchored '*.html' '*.scan-build.json'
            rm $RUN_ID/$name/$name.tar.gz
        fi
    done
done

rm $RUN_ID/artifacts.*.json
