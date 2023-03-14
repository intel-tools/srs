#!/bin/bash
RUN_IDS=$1

if [ -z $RUN_IDS ]; then
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

download_workflow_id() {
    RUN_ID=$1
    DEST=$2

    page=1
    got=0
    while [ true ]; do
        rate_limit
        gh api -H "Accept: application/vnd.github+json" "/repos/$GITHUB_REPOSITORY/actions/runs/$RUN_ID/artifacts?per_page=100&page=$page" > $DEST/artifacts.$RUN_ID.$page.json

        total=$(jq '.total_count' $DEST/artifacts.$RUN_ID.1.json)
        got=$(( page * 100 ))
        (( page++ ))

        [[ $got -lt $total ]] && continue

        break
    done

    for a in $(ls $DEST/artifacts.$RUN_ID.*.json); do
        for b in $(jq -r '.artifacts[] | "\(.id),\(.name),\(.expired)"' $a); do
            id=$(echo $b | awk -F',' '{ print $1 }')
            name=$(echo $b | awk -F',' '{ print $2 }')
            expired=$(echo $b | awk -F',' '{ print $3 }')

            [[ $expired == "true" ]] && continue
            rate_limit
            gh api -H "Accept: application/vnd.github+json" /repos/$GITHUB_REPOSITORY/actions/artifacts/$id/zip > $DEST/$name.zip || continue
            mkdir -p $DEST/$name
            unzip -o -d $DEST/$name $DEST/$name.zip || continue
            rm $DEST/$name.zip

            if [ -f $DEST/$name/$name.tar.gz ]; then
                tar -xvf $DEST/$name/$name.tar.gz -C $DEST/$name --wildcards --no-anchored '*.scan-build.json'
                rm $DEST/$name/$name.tar.gz
            fi
        done
    done

    rm $DEST/artifacts.*.json
}

DEST=$(echo $RUN_IDS | awk -F',' '{ print $1 }')
mkdir -p $DEST

for RUN_ID in $(echo $RUN_IDS | tr "," "\n"); do
    download_workflow_id $RUN_ID $DEST
done
