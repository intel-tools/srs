#!/bin/bash
set -o pipefail

REPO=$1
LLVM=VERSION=${2:-15}
TIMEOUT=${3:-30}

SREPO=$(echo $REPO | tr '/' .)

export OUTPUT=/work/$SREPO

find_autoconf_builddir() {
  local search="configure autogen.sh bootstrap.sh bootstrap boot buildconf configure.ac"
  touch /work/build_autoconf

  for f in $search; do
    local dir=$(find . -iname "$f" -type f -printf '%h\n')
    for d in $dir; do
      if [ $(grep "$PWD/$d" /work/build_autoconf | wc -l) -eq 0 ]; then
        ODIR=$PWD
        cd $d
        s=$(find . -iname "$f" -type f | head -n1)
        echo "Found $s in $PWD/$d"
        echo "$PWD/$d $s" >> /work/build_autoconf
        cd $ODIR
      fi
    done
  done
}

find_cmake_builddir() {
  local search="CMakeLists.txt"
  touch /work/build_cmake

  for f in $search; do
    local dir=$(find . -iname "$f" -type f -printf '%h\n')
    for d in $dir; do
      echo "Found $f in $PWD/$d"
      project=$(grep 'project(' ${d}/${f} | wc -l)
      if [ ${project} -gt 0 ]; then
        echo "Top level $f found at ${d}/${f}"
        echo "$PWD/$d $f" >> /work/build_cmake
      fi
    done
  done
}

find_meson_builddir() {
  local search="meson.build"
  touch /work/build_meson

  for f in $search; do
    local dir=$(find . -iname "$f" -type f -printf '%h\n')
    for d in $dir; do
      project=$(grep 'project(' "$d/$f" | wc -l)
      if [ $project -gt 0 ]; then
        echo "Found $f in $PWD/$d"
        echo "$PWD/$d $f" >> /work/build_meson
      fi
    done
  done
}

find_builddirs() {
    find_autoconf_builddir
    find_cmake_builddir
    find_meson_builddir
}

search_and_install_dependencies() {
          packages=""
          declare -a files=(
            $(grep -rl "apt-get install")
            $(grep -rl "apt install")
            $(grep -rl "aptitude install")
          )

          for r in "${files[@]}"; do
            found=0
            newline=0

            while read -r line; do
              if [ $(echo -n "${line}" | grep "apt-get install" | wc -l) -eq 1 ]; then
                found=1
              fi

              # found install line, grab all potential packages from this line plus lines after while there is linebreak 
              if [ $found -eq 1 ]; then
                if [ $newline -eq 0 ]; then
                  packages+=$(echo -n $line | sed -r 's/^.*install //' | sed -r 's/^;//' | sed 's/\\/ /g' | awk '{split($0,a," "); for (x in a) { if (a[x] ~ /^[^-].*$/) { printf("%s ", a[x]) } } }')
                else
                  packages+=$(echo -n $line | sed -r 's/^;//' | sed 's/\\/ /g' | awk '{split($0,a," "); for (x in a) { if (a[x] ~ /^[^-].*$/) { printf("%s ", a[x]) } } }')
                fi

                # check if there is a linebreak at the end
                if [ $(echo -n $line | awk '{print $NF}' | grep "\\\\" | wc -l) -eq 0 ]; then
                  newline=0
                  found=0
                else
                  newline=1
                fi
              fi
            done < $r
          done

          packages=$(echo -n $packages | tr -dc '[:alnum:]\-\_ ')

          for p in ${packages}; do
            apt-get -y install "${p}" || :
          done
}

get_submodules() {
  cd /work/repo
  git submodule update --init --recursive || :
}

scan_build_autoconf() {
    if [ ! -f /work/build_autoconf ]; then
        exit 0
    fi

          while read -r build; do

            dir=$(echo $build | awk '{ print $1 }')
            script=$(echo $build | awk '{ print $2 }')

            cd $dir

            # don't scan the same folder multiple times
            if [ -f "scan-build-done" ]; then
              continue;
            fi

            echo "Scanning $dir with setup $script"

            case $script in
              configure.ac)
                autoreconf -vif
                ;;

              Configure)
                mv Configure configure
                ;;

              configure)
                ;;

              *)
                chmod +x ./$script
                ./$script
                ;;
            esac

            echo $dir >> ${OUTPUT}/scan-build-configure.log

            ./configure | tee -a ${OUTPUT}/configure.log 2>&1 || continue
            intercept-build-${LLVM_VERSION} make -j2 | tee -a ${OUTPUT}/make.log 2>&1 || continue

            timeout -s 2 ${TIMEOUT} \
            run-clang-tidy-${LLVM_VERSION} -quiet \
              -config="{Checks: 'readability-function-cognitive-complexity', CheckOptions: [{key: readability-function-cognitive-complexity.Threshold, value: 0}, {key: readability-function-cognitive-complexity.DescribeBasicIncrements, value: False}]}" \
              2>/dev/null | \
              grep warning | grep "cognitive complexity" | tee -a ${OUTPUT}/cognitive-complexity.log || :

            echo $dir >> ${OUTPUT}/scan-build.log

            timeout -s 2 ${TIMEOUT} \
            /usr/bin/time -p -o ${OUTPUT}/scan-build-time \
            analyze-build-${LLVM_VERSION} -v --cdb compile_commands.json --analyze-headers --keep-empty --force-analyze-debug-code --html-title $SREPO -o ${OUTPUT}/scan-build-result \
              --analyzer-config crosscheck-with-z3=true \
              --disable-checker deadcode.DeadStores \
              --enable-checker security.FloatLoopCounter \
              --enable-checker security.insecureAPI.strcpy | tee -a ${OUTPUT}/analyze-build.log 2>&1 || continue

            t=$(cat $OUTPUT/scan-build-time | grep real | awk '{ print $2 }')
            echo "$dir $t" > $OUTPUT/time.log

            touch $dir/scan-build-done

          done < /work/build_autoconf

          if [ ! -d $OUTPUT/scan-build-result ]; then
            exit 10
          fi
}

scan_build_cmake() {
    if [ ! -f /work/build_cmake ]; then
        exit 0
    fi

          while read -r build; do

            dir=$(echo $build | awk '{ print $1 }')

            cd $dir

            # don't scan the same folder multiple times
            if [ -f "scan-build-done" ]; then
              continue;
            fi

            echo "Attempting to build $GITHUB_WORKSPACE/repo/$dir"

            mkdir -p $dir/build
            cd $dir/build

            echo $dir >> $OUTPUT/cmake.log

            cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=YES $dir | tee -a ${OUTPUT}/cmake.log 2>&1 || continue

            timeout -s 2 ${TIMEOUT} \
            run-clang-tidy-${LLVM_VERSION} -quiet \
              -config="{Checks: 'readability-function-cognitive-complexity', CheckOptions: [{key: readability-function-cognitive-complexity.Threshold, value: 0}, {key: readability-function-cognitive-complexity.DescribeBasicIncrements, value: False}]}" \
              2>/dev/null | \
              grep warning | grep "cognitive complexity" | tee -a ${OUTPUT}/cognitive-complexity.log || :

            echo $dir >> $OUTPUT/analyze-build.log

            timeout -s 2 ${TIMEOUT} \
            /usr/bin/time -p -o ${OUTPUT}/analyze-build-time \
            analyze-build-${LLVM_VERSION} -v --cdb compile_commands.json --analyze-headers --keep-empty --force-analyze-debug-code --html-title $SREPO -o ${OUTPUT}/scan-build-result \
              --analyzer-config crosscheck-with-z3=true \
              --disable-checker deadcode.DeadStores \
              --enable-checker security.FloatLoopCounter \
              --enable-checker security.insecureAPI.strcpy | tee -a ${OUTPUT}/analyze-build.log 2>&1 || continue

            t=$(cat $OUTPUT/analyze-build-time | grep real | awk '{ print $2 }')
            echo "$dir $t" > $OUTPUT/time.log

            touch $dir/scan-build-done

          done < /work/build_cmake

          if [ ! -d $OUTPUT/scan-build-result ]; then
            exit 10
          fi
}

scan_build_meson() {
    if [ ! -f /work/build_meson ]; then
        exit 0
    fi

          while read -r build; do

            dir=$(echo $build | awk '{ print $1 }')

            cd $dir

            # don't scan the same folder multiple times
            if [ -f "scan-build-done" ]; then
              continue;
            fi

            echo $dir >> ${OUTPUT}/meson-setup.log

            meson setup builddir --buildtype debug 2>&1 | tee -a $OUTPUT/meson-setup.log || continue

            cd builddir

            timeout -s 2 ${TIMEOUT} \
            run-clang-tidy-${LLVM_VERSION} -quiet \
              -config="{Checks: 'readability-function-cognitive-complexity', CheckOptions: [{key: readability-function-cognitive-complexity.Threshold, value: 0}, {key: readability-function-cognitive-complexity.DescribeBasicIncrements, value: False}]}" \
              2>/dev/null | \
              grep warning | grep "cognitive complexity" | tee -a ${OUTPUT}/cognitive-complexity.log || :

            echo $dir >> ${OUTPUT}/analyze-build.log

            timeout -s 2 ${TIMEOUT} \
            /usr/bin/time -p -o ${OUTPUT}/analyze-build-time \
            analyze-build-${LLVM_VERSION} -v --cdb compile_commands.json --analyze-headers --keep-empty --force-analyze-debug-code --html-title $SREPO -o ${OUTPUT}/scan-build-result \
              --analyzer-config crosscheck-with-z3=true \
              --disable-checker deadcode.DeadStores \
              --enable-checker security.FloatLoopCounter \
              --enable-checker security.insecureAPI.strcpy | tee -a ${OUTPUT}/analyze-build.log 2>&1 || continue

            t=$(cat $OUTPUT/analyze-build-time | grep real | awk '{ print $2 }')
            echo "$dir $t" > $OUTPUT/time.log

            touch $dir/scan-build-done

          done < /work/build_meson

          if [ ! -d $OUTPUT/scan-build-result ]; then
            exit 10
          fi
}

scan_build() {
    scan_build_autoconf
    scan_build_cmake
    scan_build_meson
}

parse_info() {
  local f=$1
  local d=$2
  grep $d $f | awk -F "$d " '{ print $2 }' | rev | cut -c5- | rev
}

generate_json() {

          bugfound=0
          now=$(date)
          functions=$(cat ${OUTPUT}/cognitive-complexity.log 2>/dev/null | wc -l)

          JSON="{ \"repo\": \"$REPO\", \"scan-date\": \"$now\", \"functions\": $functions, \"bugs\": ["

          for f in $(find . -type f -name '*.html' | grep report); do
            bugfound=1
            bugtype=$(parse_info $f BUGTYPE)
            bugcategory=$(parse_info $f BUGCATEGORY)
            bugfile=$(parse_info $f BUGFILE)
            bugline=$(parse_info $f BUGLINE)
            bugdescription=$(parse_info $f BUGDESC)
            bugfunction=$(parse_info $f FUNCTIONNAME)

            JSON+="{"
            JSON+=" \"category\": \"$bugcategory\","
            JSON+=" \"type\": \"$bugtype\","
            JSON+=" \"file\": \"$bugfile\","
            JSON+=" \"line\": $bugline,"
            JSON+=" \"function\": \"$bugfunction\","
            JSON+=" \"description\": \"$bugdescription\""
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

          echo $JSON > $OUTPUT/result.json

          if [ $bugfound -eq 0 ]; then
            exit 0
          fi

          jq '.bugs[].category' $OUTPUT/result.json | sort | uniq -c > $OUTPUT/bug-categories.txt
          jq '.bugs[].type' $OUTPUT/result.json | sort | uniq -c > $OUTPUT/bug-types.txt

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
          echo $JSON > $OUTPUT/result.json
}

######

mkdir -p $OUTPUT

cd /work/repo

find_builddirs
search_and_install_dependencies
get_submodules
scan_build
generate_json
