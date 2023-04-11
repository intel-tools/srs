#!/bin/bash
ARTIFACT_DIR=${1:-"."}
RUD_IDS=$2

create_table() {
          echo "" > summary.md

          built=$(find $ARTIFACT_DIR -type f -name '*.scan-build.json' | wc -l)
          scored=$(find $ARTIFACT_DIR -type f -name '*.ossf-scorecard.json' | wc -l)
          bugs=$(find $ARTIFACT_DIR -type f -name '*.scan-build.json' -exec jq '.bugs | length' {} + | awk '{ sum += $1 } END { print sum }')
          complex_functions=$(find $ARTIFACT_DIR -type f -name '*.scan-build.json' -exec jq '.bugs[] | select( any(.; .type == "Cognitive complexity") ) | length' {} + | wc -l | awk '{ sum += $1 } END { print sum }')
          bugs=$(( bugs - complex_functions ))

          echo "$built, $scored, $bugs, $complex_functions" > stats

          echo "### Repositories built with scan-build: ${built}" >> summary.md
          echo "### Repositories scored with OSSF scorecard: ${scored}" >> summary.md
          echo "" >> summary.md
          echo "***" >> summary.md
          echo "" >> summary.md
          echo "### Total number of bugs found: ${bugs}" >> summary.md
          echo "### Total number of high cognitivite complexity functions found: ${complex_functions}" >> summary.md
          echo "" >> summary.md
          echo "***" >> summary.md
          echo "" >> summary.md

          if [ ! -z $RUN_IDS ]; then
            echo -n "GitHub Action Run IDS: " >> summary.md
            for r in $(echo $RUN_IDS | tr ',' ' '); do
                echo -n "[$r](https://github.com/intel/srs/actions/runs/$r) " >> summary.md
            done
            echo "" >> summary.md
            echo "" >> summary.md
            echo "***" >> summary.md
            echo "" >> summary.md
          fi

          echo "### Breakdown" >> summary.md

          echo "| #    | Repo        | Bugs       | OSSF score | High cognitive complexity functions / Total functions   |" >> summary.md
          echo "| ---- | ----------- | ---------- | ---------- | ------------------------------------------------------- |" >> summary.md

          rm *.tmp || :

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

          echo "repo, bugs, ossf score, complex functions, total functions" > score_vs_bugs.csv
          count=1
          while read -r repo bugs score functions complex_functions; do
            echo "| $count | [$repo](https://github.com/$repo) | $bugs | $score | $complex_functions / $functions |" >> summary.md
            echo "$repo,$bugs,$score,$complex_functions,$functions" >> score_vs_bugs.csv
            (( count++ ))
          done < s2.tmp

          rm *.tmp || :
}

aggregate() {
    mkdir -p $ARTIFACT_DIR/aggregate-results
    for f in $(find $ARTIFACT_DIR -type f -name '*.scan-build.json'); do
        cp $f $ARTIFACT_DIR/aggregate-results/ || :
    done

    for f in $(find $ARTIFACT_DIR -type f -name '*.ossf-scorecard.json'); do
        cp $f $ARTIFACT_DIR/aggregate-results/ || :
    done

    for f in $(find $ARTIFACT_DIR -type f -name '*.metadata.json'); do
        cp $f $ARTIFACT_DIR/aggregate-results/ || :
    done

    for f in $(find $ARTIFACT_DIR -type f -name '*.cloc.json'); do
        cp $f $ARTIFACT_DIR/aggregate-results/ || :
    done

    tar -C $ARTIFACT_DIR/aggregate-results -czvf all-results.tar.gz .
}

###############################

create_table
aggregate
