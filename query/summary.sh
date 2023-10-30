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

          # Save stats for website summary
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

          echo "| #   | Repo        | Scan-build Bugs | Infer Bugs | OSSF Score | High cognitive complexity functions / Total functions   | Comments / LoC |" >> summary.md
          echo "| --- | ----------- | --------------- | ---------- | ---------- | ------------------------------------------------------- | -------------- |" >> summary.md

          rm *.tmp || :

          for f in $(find $ARTIFACT_DIR -type f -name '*.metadata.json'); do
            repo=$(jq -r '.full_name' $f)
            srepo=$(echo $repo | tr '/' .)

            unset bugs
            unset functions
            unset complex_functions
            if [ -f $ARTIFACT_DIR/$srepo.scan-build/$srepo.scan-build.json ]; then
                functions=$(jq '.functions' $ARTIFACT_DIR/$srepo.scan-build/$srepo.scan-build.json)
                complex_functions=$(jq '.bugs[] | select( any(.; .type == "Cognitive complexity") ) | length' $ARTIFACT_DIR/$srepo.scan-build/$srepo.scan-build.json | wc -l)
                bugs=$(jq '.bugs | length' $ARTIFACT_DIR/$srepo.scan-build/$srepo.scan-build.json)
                bugs=$(( bugs - complex_functions ))
            fi
            [[ -z $functions ]] && functions="-1"
            [[ -z $complex_functions ]] && complex_functions="-1"
            [[ -z $bugs ]] && bugs="-1"

            unset score
            if [ -f $ARTIFACT_DIR/$srepo.ossf-scorecard/$srepo.ossf-scorecard.json ]; then
                score=$(jq '.score' $ARTIFACT_DIR/$srepo.ossf-scorecard/$srepo.ossf-scorecard.json)
            fi
            [[ -z $score ]] && score="-1"

            unset lines
            unset comments
            if [ -f $ARTIFACT_DIR/$srepo.metadata/$srepo.cloc.json ]; then
                lines=$(jq -r '[."C".code, ."C++".code, ."C/C++ Header".code ] | add' $ARTIFACT_DIR/$srepo.metadata/$srepo.cloc.json)
                comments=$(jq -r '[."C".comment, ."C++".comment, ."C/C++ Header".comment ] | add' $ARTIFACT_DIR/$srepo.metadata/$srepo.cloc.json)
            fi
            [[ -z $lines ]] && lines="-1"
            [[ -z $comments ]] && comments="-1"

            unset infer
            if [ -f $ARTIFACT_DIR/$srepo.infer/$srepo.infer.json ]; then
                infer=$(jq -r '.bugs | length' $ARTIFACT_DIR/$srepo.infer/$srepo.infer.json)
            fi
            [[ -z $infer ]] && infer="-1"

            echo "$repo $bugs $infer $score $functions $complex_functions $comments $lines" >> s.tmp
          done

          sort -k 2 -n -r s.tmp > s2.tmp

          echo "repo, scan-build-bugs, infer-bugs, ossf-score, complex-functions, total-functions, lines-of-code, lines-of-comments" > summary.csv
          count=1
          while read -r repo bugs infer score functions complex_functions comments lines; do
            echo "| $count | [$repo](https://github.com/$repo) | $bugs | $infer | $score | $complex_functions / $functions | $comments / $lines |" >> summary.md
            echo "$repo,$bugs,$infer,$score,$complex_functions,$functions,$comments,$lines" >> summary.csv
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

    for f in $(find $ARTIFACT_DIR -type f -name '*.infer.json'); do
        cp $f $ARTIFACT_DIR/aggregate-results/ || :
    done

    tar -C $ARTIFACT_DIR/aggregate-results -czvf all-results.tar.gz .
}

###############################

create_table
aggregate
