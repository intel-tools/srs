#!/bin/bash
SEARCH=${1:-"archived:false language:c language:c++"}
MINSTARS=${2:-1000} # Starting range, no results from below this
MAXSTARS=${3:-10000} # Stop when reached
INCREMENT=${4:-300} # Group size to split search into
ABOVEMAX=${5:-1} # Include results above MAXSTARS in a single query

# Github search is limited to return 1000 results at most
# even if the repositoryCount returns total number of matches (may also be limited to 4000).
# Workaround is to break the search up into slots based on stars

if [ -z "$SEARCH" ]; then
    echo "No search term specified"
    exit 1
fi

execute_query() {
            local counter=0
            local cursor=""
            local s=$1
            local retry=$2
            local retry_counter=$retry

            local query='
            query($search: String!, $endCursor: String) {
              search(
                type: REPOSITORY,
                query: $search,
                first: 100
                after: $endCursor
              )
              {
                repositoryCount
                repos: edges {
                  repo: node {
                    ... on Repository {
                      nameWithOwner
                      languages(first: 100) { nodes { name } }
                    }
                  }
                }
              pageInfo { hasNextPage endCursor }
              }
            rateLimit { remaining resetAt }
            }
            '

            while : ; do

              echo "Running iteration $counter of query $s"

              if [ -z ${cursor} ]; then
                gh api graphql -F search="$s" -f query="$query" > data.${counter}.json
              else
                gh api graphql -F search="$s" -F endCursor="${cursor}" -f query="$query" > data.${counter}.json
              fi

              r=$?

              if [ $r -ne 0 ] && [ $retry_counter -gt 0 ]; then
                sleep 5
                (( retry_counter-- )) || :

                # TODO: check rate limiting and sleep till resetAt if needed and then retry

                continue
              fi

              c=$(jq '.data.search.repositoryCount' data.0.json)
              t=$(jq '.data.search.pageInfo | "\(.hasNextPage) \(.endCursor)"' data.${counter}.json | tr -d '"')
              next=$(echo -n $t | awk '{ print $1 }')
              cursor=$(echo -n $t | awk '{ print $2 }')

              if [ $c -gt 1000 ]; then
                echo "Results will be truncated due to more then a 1000 matches to the query ($c), consider decreasing the INCREMENT threshold"
                exit 1
              fi

              echo "Total count: $c, more data? $next $cursor"

              if [ "${next}" == "false" ]; then
                break
              fi

              retry_counter=$retry
              (( counter++ )) || :

            done

            # merge jsons
            find . -type f -name 'data.*.json' -exec jq -cn '{ repos: [ inputs.data.search.repos ] | add }' {} + > merged.json
            rm data*

            if [ -f repos.json ]; then
                jq -cn '{ repos: [ inputs.repos ] | add }'  merged.json repos.json > tmp.json
                mv tmp.json repos.json
                rm merged.json
            else
                mv merged.json repos.json
            fi

          }

if [ $MAXSTARS -lt $MINSTARS ]; then
    MAXSTARS=$MINSTARS
fi

for s in `seq $MINSTARS $INCREMENT $MAXSTARS`; do
    if [ $s -lt $MAXSTARS ]; then
        sp=$(( s + INCREMENT ))
        q="$SEARCH stars:$s..$sp"
    else
        [[ $ABOVEMAX -eq 0 ]] && exit 0

        q="$SEARCH stars:>=$MAXSTARS"
    fi

    echo $q

    execute_query "${q}" 5
done
