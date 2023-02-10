#!/bin/bash
export REPO=$1
export OUTPUT=$2
export SREPO=$(echo $REPO | tr '/' .)

if [ $# -ne 2 ]; then
    echo "Specify '{owner}/{repo}' and folder where scan-build.sh results are"
    exit 1
fi

if [ ! -d $OUTPUT ]; then
    echo "Specify folder where scan-build.sh results are"
    exit 1
fi

if [ ! -d $OUTPUT/scan-build-result ]; then
    echo "Specified folder doesn't have scan-build results"
    exit 1
fi

if [ ! -f $OUTPUT/cognitive-complexity.log ]; then
    echo "Specified folder doesn't have cognitive complexity results"
    exit 1
fi

######

parse_info() {
  local f=$1
  local d=$2
  grep $d $f | awk -F "$d " '{ print $2 }' | rev | cut -c5- | rev | tr '"' "'"
}

generate_json() {

          bugfound=0
          now=$(date)
          functions=$(cat ${OUTPUT}/cognitive-complexity.log 2>/dev/null | wc -l)

          JSON="{ \"repo\": \"$REPO\", \"scan-date\": \"$now\", \"functions\": $functions, \"bugs\": ["

          for f in $(find ${OUTPUT}/scan-build-result -type f -name '*.html' | grep report); do
            bugfound=1
            bugtype=$(parse_info $f BUGTYPE)
            bugcategory=$(parse_info $f BUGCATEGORY)
            bugfile=$(parse_info $f BUGFILE)
            bugline=$(parse_info $f BUGLINE)
            bugdescription=$(parse_info $f BUGDESC)
            bugfunction=$(parse_info $f FUNCTIONNAME)
            report=$(echo -n $f | sed "s/${OUTPUT}\/scan-build-result\///")

            JSON+="{"
            JSON+=" \"category\": \"$bugcategory\","
            JSON+=" \"type\": \"$bugtype\","
            JSON+=" \"file\": \"$bugfile\","
            JSON+=" \"line\": $bugline,"
            JSON+=" \"function\": \"$bugfunction\","
            JSON+=" \"description\": \"$bugdescription\","
            JSON+=" \"report\": \"$report\""
            JSON+=" },"
          done

          if [ -f ${OUTPUT}/cognitive-complexity.log ]; then
            while read -r line; do
              bugtype="Cognitive complexity"
              bugcategory="Readability"
              bugfile=$(echo $line | awk '{ print $1 }' | awk -F":" '{ print $1 }')
              bugline=$(echo $line | awk '{ print $1 }' | awk -F":" '{ print $2 }')
              bugfunction=$(echo $line | awk '{ print $4 }' | tr -d "'" )
              bugdescription=$(echo $line | awk '{ print $9 }')

              [[ $bugdescription -lt 25 ]] && continue

              bugfound=1

              JSON+="{"
              JSON+=" \"category\": \"$bugcategory\","
              JSON+=" \"type\": \"$bugtype\","
              JSON+=" \"file\": \"$bugfile\","
              JSON+=" \"line\": $bugline,"
              JSON+=" \"function\": \"$bugfunction\","
              JSON+=" \"description\": \"$bugdescription\""
              JSON+=" },"
            done < ${OUTPUT}/cognitive-complexity.log
          fi

          if [ $bugfound -eq 1 ]; then
            JSON="${JSON%?}" # Remove last ","
          fi

          JSON+="]"
          JSON+="}"

          echo $JSON > $OUTPUT/$SREPO.scan-build.json

          if [ $bugfound -eq 0 ]; then
            exit 0
          fi

          jq '.bugs[].category' $OUTPUT/$SREPO.scan-build.json | sort | uniq -c > $OUTPUT/bug-categories.txt
          jq '.bugs[].type' $OUTPUT/$SREPO.scan-build.json | sort | uniq -c > $OUTPUT/bug-types.txt

          JSON="${JSON%?}" # Remove last "}"
          JSON+=","

          JSON+="\"categories\": ["

          while read -r line; do
            c=$(echo $line | awk -F ' ' '{ print $1 }')
            d=$(echo $line | awk -F '"' '{ print $2 }')

            JSON+="{\"category\": \"$d\", \"count\": $c },"
          done < $OUTPUT/bug-categories.txt

          JSON="${JSON%?}" # Remove last ","
          JSON+="],\"types\":["

          while read -r line; do
            c=$(echo $line | awk -F ' ' '{ print $1 }')
            d=$(echo $line | awk -F '"' '{ print $2 }')

            JSON+="{\"type\": \"$d\", \"count\": $c },"
          done < $OUTPUT/bug-types.txt

          JSON="${JSON%?}" # Remove last ","
          JSON+="]}"
          echo $JSON > $OUTPUT/$SREPO.scan-build.json
}

######

generate_json
