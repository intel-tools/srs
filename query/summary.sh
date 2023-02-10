#!/bin/bash
ARTIFACT_DIR=${1:-"."}

decompress() {
    for f in $(find $ARTIFACT_DIR -type f -name '*.tar.gz'); do
        echo "Extracting $f"
        tar -xvf $f -C $ARTIFACT_DIR > /dev/null
    done
}

summarize() {
          built=$(find $ARTIFACT_DIR -type f -name '*.scan-build.json' | wc -l)
          scored=$(find $ARTIFACT_DIR -type f -name '*.ossf-scorecard.json' | wc -l)
          bugs=$(find $ARTIFACT_DIR -type f -name '*.scan-build.json' -exec jq '.bugs | length' {} + | awk '{ sum += $1 } END { print sum }')
          complex_functions=$(find $ARTIFACT_DIR -type f -name '*.scan-build.json' -exec jq '.bugs[] | select( any(.; .type == "Cognitive complexity") ) | length' {} + | wc -l | awk '{ sum += $1 } END { print sum }')
          bugs=$(( bugs - complex_functions ))

          echo "" >> summary.md
          echo "***" >> summary.md
          echo "" >> summary.md
          echo "### Repositories built with scan-build: ${built}" >> summary.md
          echo "### Repositories scored with OSSF scorecard: ${scored}" >> summary.md
          echo "" >> summary.md
          echo "***" >> summary.md
          echo "" >> summary.md
          echo "### Total number of bugs found: ${bugs}" >> summary.md
          echo "### Total number of high cognitivite complexity functions found: ${complex_functions}" >> summary.md

          JSON="{\"bugs\": $bugs, "

          for f in $(find $ARTIFACT_DIR -type f -name '*.scan-build.json'); do
            if [ $(jq '.bugs | length' $f) -eq 0 ]; then
                jq -r '.repo' $f >> clean-repos.txt
            else
                jq -r '.types[] | ",\(.type),\(.count)"' $f >> aggregate-bug-types.txt
                jq -r '.categories[] | ",\(.category),\(.count)"' $f >> aggregate-bug-categories.txt
            fi
          done

          echo "" >> summary.md
          echo "***" >> summary.md
          echo "" >> summary.md

          cat aggregate-bug-categories.txt | awk -F',' '{ print $2 }' | sort -u > bug-categories.txt
          cat aggregate-bug-types.txt | awk -F',' '{ print $2 }' | sort -u > bug-types.txt

          echo "#### Bug categories" >> summary.md

          JSON+="\"categories\": ["
          while read -r line; do
            c=$(grep ",$line," aggregate-bug-categories.txt | awk -F ',' '{ sum += $3 } END { print sum }')

            echo "##### $line: $c" >> summary.md
            echo "| Repo        | Bug count   |" >> summary.md
            echo "| ----------- | ----------- |" >> summary.md

            JSON+="{\"category\": \"$line\", \"count\": $c, \"repos\": ["

            rm s.tmp || :
            for r in $(grep -rl "$line" $ARTIFACT_DIR/*/*.scan-build.json); do
              repo=$(jq -r '.repo' $r)
              count=$(jq ".bugs[] | select( any(.; .category == \"$line\") ) | length" $r | wc -l)

              if [ $count -gt 0 ]; then
                echo "$repo $count" >> s.tmp
              fi
            done

            sort -k 2 -n -r s.tmp > s2.tmp

            while read -r r c; do
                JSON+="{\"repo\": \"$r\", \"count\": $c},"
                echo "| $r | $c |" >> summary.md
            done < s2.tmp

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
            c=$(grep ",$line," aggregate-bug-types.txt | awk -F ',' '{ sum += $3 } END { print sum }')

            echo "##### $line: $c" >> summary.md
            echo "| Repo        | Bug count   |" >> summary.md
            echo "| ----------- | ----------- |" >> summary.md

            rm s.tmp || :
            for r in $(grep -rl "$line" $ARTIFACT_DIR/*/*.scan-build.json); do
              repo=$(jq -r '.repo' $r)
              count=$(jq ".bugs[] | select( any(.; .type == \"$line\") ) | length" $r | wc -l)

              if [ $count -gt 0 ]; then
                echo "$repo $count" >> s.tmp
              fi
            done

            sort -k 2 -n -r s.tmp > s2.tmp

            JSON+="{\"type\": \"$line\", \"count\": $c, \"repos\": ["

            while read -r r c; do
                JSON+="{\"repo\": \"$r\", \"count\": $c},"
                echo "| $r | $c |" >> summary.md
            done < s2.tmp

            JSON="${JSON%?}" # Remove last ","
            JSON+="]},"

            echo "" >> summary.md
            echo "***" >> summary.md
            echo "" >> summary.md
          done < bug-types.txt
          JSON="${JSON%?}" # Remove last ","
          JSON+="]}"

          echo $JSON

          echo $JSON | jq '.' > bug_breakdown.json

          echo "" >> summary.md
          echo "***" >> summary.md
          echo "" >> summary.md

          clean_repos=$(cat clean-repos.txt | wc -l)
          echo "### Repositories with no bugs: ${clean_repos}" >> summary.md
          echo "" >> summary.md
          echo "| Repo |" >> summary.md
          echo "| ---- |" >> summary.md
          while read -r repo; do
            echo "| $repo |"  >> summary.md
          done < clean-repos.txt
}

create_table() {
          touch score_vs_bugs.csv

          echo "" >> summary.md
          echo "### Breakdown" >> summary.md

          echo "| #    | Repo        | Bugs       | OSSF score | High cognitive complexity functions / Total functions   |" >> summary.md
          echo "| ---- | ----------- | ---------- | -------------------------------------------------------------------- |" >> summary.md

          for f in $(find $ARTIFACT_DIR -type f -name '*.scan-build.json'); do
            repo=$(jq -r '.repo' $f)
            srepo=$(echo $repo | tr '/' .)

            functions=$(jq '.functions' $f)
            complex_functions=$(jq '.bugs[] | select( any(.; .type == "Cognitive complexity") ) | length' $f | wc -l)
            bugs=$(jq '.bugs | length' $f)
            bugs=$(( bugs - complex_functions ))

            if [ ! -f $ARTIFACT_DIR/$srepo.ossf-scorecard/$srepo.ossf-scorecard.json ]; then
                score="-1"
            else
                score=$(jq '.score' $ARTIFACT_DIR/$srepo.ossf-scorecard/$srepo.ossf-scorecard.json)
            fi

            if [ ${score} != "-1" ] && [ $functions -gt 0 ]; then
              echo "$repo $bugs $score $functions $complex_functions" >> s.tmp
            else
              echo "Repo $repo had a failed OSSF scorecard or clang-tidy scan ($score, $functions)"
            fi
          done

          sort -k 2 -n -r s.tmp > s2.tmp

          count=1
          while read -r repo bugs score functions complex_functions; do
            echo "| $count | $repo | $bugs | $score | $complex_functions / $functions |" >> summary.md
            echo "$repo,$bugs,$score,$complex_functions,$functions" >> score_vs_bugs.csv
            (( count++ ))
          done < s2.tmp

          rm *.tmp
}

aggregate() {
    mkdir -p $ARTIFACT_DIR/aggregate-results
    for f in $(find $ARTIFACT_DIR -type f -name '*.scan-build.json'); do
        cp $f $ARTIFACT_DIR/aggregate-results/ || :
    done

    for f in $(find $ARTIFACT_DIR -type f -name '*.ossf-scorecard.json'); do
        cp $f $ARTIFACT_DIR/aggregate-results/ || :
    done

    tar -C $ARTIFACT_DIR/aggregate-results -czvf all-results.tar.gz .
}

###############################

decompress
summarize
create_table
aggregate
