#!/bin/bash
ARTIFACT_DIR=${1:-"."}

decompress() {
    for f in $(find $ARTIFACT_DIR -type f -name '*.tar.gz'); do
        echo "Extracting $f"
        tar -xvf $f -C $ARTIFACT_DIR > /dev/null
    done
}

summarize() {
          bugs=$(find $ARTIFACT_DIR -type f -name 'result.json' -type f -exec jq '.bugs | length' {} + | awk '{ sum += $1 } END { print sum }')
          complex_functions=$(find $ARTIFACT_DIR -type f -name 'result.json' -type f -exec jq '.bugs[] | select( any(.; .type == "Cognitive complexity") ) | length' {} + | wc -l | awk '{ sum += $1 } END { print sum }')
          bugs=$(( bugs - complex_functions ))

          echo "### Total number of bugs found: ${bugs}" >> summary.md
          echo "### Total number of high cognitivite complexity functions found: ${complex_functions}" >> summary.md

          JSON="{\"bugs\": $bugs, "

          for f in $(find $ARTIFACT_DIR -type f -name 'result.json'); do
            if [ $(jq '.bugs | length' $f) -eq 0 ]; then
                jq -r '.repo' $f >> clean-repos.txt
            else
                jq -r '.types[] | "\(.type),\(.count)"' $f >> aggregate-bug-types.txt
                jq -r '.categories[] | "\(.category),\(.count)"' $f >> aggregate-bug-categories.txt
            fi
          done

          echo "" >> summary.md
          echo "***" >> summary.md
          echo "" >> summary.md

          cat aggregate-bug-categories.txt | awk -F',' '{ print $1 }' | sort -u > bug-categories.txt
          cat aggregate-bug-types.txt | awk -F',' '{ print $1 }' | sort -u > bug-types.txt

          echo "#### Bug categories" >> summary.md

          JSON+="\"categories\": ["
          while read -r line; do
            c=$(grep "$line" aggregate-bug-categories.txt | awk -F ',' '{ sum += $2 } END { print sum }')
            echo "##### $line: $c" >> summary.md
            JSON+="{\"category\": \"$line\", \"count\": $c, \"repos\": ["

            for r in $(grep -rl "$line" $ARTIFACT_DIR/*/result.json); do
              repo=$(jq -r '.repo' $r)
              count=$(jq ".bugs[] | select( any(.; .category == \"$line\") ) | length" $r | wc -l)

              JSON+="{\"repo\": \"$repo\", \"count\": $count},"
              echo "$repo ($count)" >> summary.md
            done
            JSON="${JSON%?}" # Remove last ","
            JSON+="]},"

            echo "" >> summary.md
            echo "***" >> summary.md
            echo "" >> summary.md

          done < bug-categories.txt
          JSON="${JSON%?}" # Remove last ","
          JSON+="], "

          echo "#### Bug types" >> summary.md

          JSON+="\"types\": ["
          while read -r line; do
            c=$(grep "$line" aggregate-bug-types.txt | awk -F ',' '{ sum += $2 } END { print sum }')
            echo "##### $line: $c" >> summary.md
            JSON+="{\"type\": \"$line\", \"count\": $c, \"repo\": ["

            for r in $(grep -rl "$line" $ARTIFACT_DIR/*/result.json); do
              repo=$(jq -r '.repo' $r)
              count=$(jq ".bugs[] | select( any(.; .type == \"$line\") ) | length" $r | wc -l)

              JSON+="{\"repo\": \"$repo\", \"count\": $count},"
              echo "$repo ($count)" >> summary.md
            done
            JSON="${JSON%?}" # Remove last ","
            JSON+="]},"

            echo "" >> summary.md
            echo "***" >> summary.md
            echo "" >> summary.md

          done < bug-types.txt
          JSON="${JSON%?}" # Remove last ","
          JSON+="]}"

          echo $JSON | jq '.' > aggregate-results.json

          echo "" >> summary.md
          echo "***" >> summary.md
          echo "" >> summary.md

          clean_repos=$(cat clean-repos.txt | wc -l)
          echo "### Repositories with no bugs: ${clean_repos}" >> summary.md
          cat clean-repos.txt >> summary.md
}

create_table() {
          touch score_vs_bugs.csv
          echo "### Breakdown" >> summary.md

          echo "| Repo        | OSSF score  | Bugs      | Cognitive complexity   |" >> summary.md
          echo "| ----------- | ----------- | --------- | ---------------------- |" >> summary.md

          for f in $(find $ARTIFACT_DIR -type f -name 'result.json'); do
            repo=$(jq -r '.repo' $f)

            if [ ! -f $ARTIFACT_DIR/$srepo.ossf-scorecard/$srepo.ossf-scorecard.json ]; then
                continue
            fi

            srepo=$(echo $repo | tr '/' .)
            functions=$(jq '.functions' $f)
            complex_functions=$(jq '.bugs[] | select( any(.; .type == "Cognitive complexity") ) | length' $f | wc -l)
            bugs=$(jq '.bugs | length' $f)
            bugs=$(( bugs - complex_functions ))

            score=$(jq '.score' $ARTIFACT_DIR/$srepo.ossf-scorecard/$srepo.ossf-scorecard.json)

            echo "| $repo | $score | $bugs | $complex_functions / $functions |" >> summary.md

            if [ ${score} != "-1" ] && [ $functions -gt 0 ]; then
              echo "$repo,$score,$bugs,$functions,$complex_functions" >> score_vs_bugs.csv
            else
              echo "Repo $repo had a failed OSSF scorecard or clang-tidy scan ($score, $functions)"
            fi
          done
}

###############################

decompress
summarize
create_table
