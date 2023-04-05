#!/bin/bash
set -o pipefail

usage() { echo "Usage: $0 [-r <owner/repo>] [-l <llvm_version>] [-t <timeout>] [-b <error-on-bugs (0/1)>]" 1>&2; exit 1; }

WORKDIR=$PWD
[[ -d /work ]] && WORKDIR="/work"
[[ -d /github/workspace ]] && WORKDIR="/github/workspace"

OUTPUT="$WORKDIR/scan-build-result"
LLVM_VERSION="15"
TIMEOUT="30m"
ERROR_ON_BUGS="0"
REPO="placeholder"
SREPO="placeholder"

if [ ! -z $GITHUB_REPOSITORY ]; then
    REPO="$GITHUB_REPOSITORY_OWNER/$GITHUB_REPOSITORY"
    SREPO="$GITHUB_REPOSITORY_OWNER.$GITHUB_REPOSITORY"
fi

while getopts ":r:l:t:b:" o; do
    case "${o}" in
        r)
            [[ ${OPTARG} == "placeholder" ]] && continue

            REPO=${OPTARG}
            SREPO=$(echo $REPO | tr '/' .)
            OUTPUT=$WORKDIR/$SREPO
            ;;
        l)
            LLVM_VERSION=${OPTARG}
            ;;
        t)
            TIMEOUT=${OPTARG}
            ;;
        b)
            ERROR_ON_BUGS=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

echo "Setting options:"
echo "  WORKDIR: $WORKDIR"
echo "  OUTPUT: $OUTPUT"
echo "  REPO: $REPO"
echo "  TIMEOUT: $TIMEOUT"
echo "  ERROR_ON_BUGS: $ERROR_ON_BUGS"

##############

find_autoconf_builddir() {
  local search="configure autogen.sh bootstrap.sh bootstrap boot buildconf configure.ac"
  touch $OUTPUT/build_autoconf

  for f in $search; do
    local dir=$(find . -iname "$f" -type f -printf '%h\n')
    for d in $dir; do
      if [ $(grep "$PWD/$d" $OUTPUT/build_autoconf | wc -l) -eq 0 ]; then
        ODIR=$PWD
        cd $d
        s=$(find . -iname "$f" -type f | head -n1 | awk -F'/' '{ print $2 }')
        echo "Found $s in $PWD"
        echo "$PWD $s" >> $OUTPUT/build_autoconf
        cd $ODIR
      fi
    done
  done
}

find_cmake_builddir() {
  local search="CMakeLists.txt"
  touch $OUTPUT/build_cmake

  for f in $search; do
    local dir=$(find . -iname "$f" -type f -printf '%h\n')
    for d in $dir; do
      echo "Found $f in $PWD/$d"
      project=$(grep 'project(' ${d}/${f} | wc -l)
      if [ ${project} -gt 0 ]; then
        echo "Top level $f found at ${d}/${f}"
        echo "$PWD/$d $f" >> $OUTPUT/build_cmake
      fi
    done
  done
}

find_meson_builddir() {
  local search="meson.build"
  touch $OUTPUT/build_meson

  for f in $search; do
    local dir=$(find . -iname "$f" -type f -printf '%h\n')
    for d in $dir; do
      project=$(grep 'project(' "$d/$f" | wc -l)
      if [ $project -gt 0 ]; then
        echo "Found $f in $PWD/$d"
        echo "$PWD/$d $f" >> $OUTPUT/build_meson
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
              if [ $(echo -n "${line}" | grep "apt" | grep "install" | wc -l) -eq 1 ]; then
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

          apt-get update
          for p in ${packages}; do
            apt-get -y install "${p}" || :
          done
}

get_submodules() {
  local dir=$(find . -iname ".gitmodules" -type f -printf '%h\n')
  for d in $dir; do
      cd $d
      git submodule update --init --recursive || :
  done
}

scan_build_autoconf() {
          while read -r build; do

            echo "Autoconf $build"

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
            analyze-build-${LLVM_VERSION} -v --cdb compile_commands.json --no-failure-reports --analyze-headers --force-analyze-debug-code -o ${OUTPUT}/scan-build-result \
              --analyzer-config crosscheck-with-z3=true \
              --disable-checker deadcode.DeadStores \
              --enable-checker security.FloatLoopCounter \
              --enable-checker security.insecureAPI.strcpy | tee -a ${OUTPUT}/analyze-build.log 2>&1 || continue

            t=$(cat $OUTPUT/scan-build-time | grep real | awk '{ print $2 }')
            echo "$dir $t" > $OUTPUT/time.log

            touch $dir/scan-build-done

          done < $OUTPUT/build_autoconf
}

scan_build_cmake() {
          while read -r build; do

            echo "CMake $build"

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
            analyze-build-${LLVM_VERSION} -v --cdb compile_commands.json --no-failure-reports --analyze-headers --force-analyze-debug-code -o ${OUTPUT}/scan-build-result \
              --analyzer-config crosscheck-with-z3=true \
              --disable-checker deadcode.DeadStores \
              --enable-checker security.FloatLoopCounter \
              --enable-checker security.insecureAPI.strcpy | tee -a ${OUTPUT}/analyze-build.log 2>&1 || continue

            t=$(cat $OUTPUT/analyze-build-time | grep real | awk '{ print $2 }')
            echo "$dir $t" > $OUTPUT/time.log

            touch $dir/scan-build-done

          done < $OUTPUT/build_cmake
}

scan_build_meson() {
          while read -r build; do

            echo "Meson $build"

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
            analyze-build-${LLVM_VERSION} -v --cdb compile_commands.json --no-failure-reports --analyze-headers --force-analyze-debug-code -o ${OUTPUT}/scan-build-result \
              --analyzer-config crosscheck-with-z3=true \
              --disable-checker deadcode.DeadStores \
              --enable-checker security.FloatLoopCounter \
              --enable-checker security.insecureAPI.strcpy | tee -a ${OUTPUT}/analyze-build.log 2>&1 || continue

            t=$(cat $OUTPUT/analyze-build-time | grep real | awk '{ print $2 }')
            echo "$dir $t" > $OUTPUT/time.log

            touch $dir/scan-build-done

          done < $OUTPUT/build_meson
}

scan_build() {
    scan_build_autoconf
    scan_build_cmake
    scan_build_meson

    if [ ! -d $OUTPUT/scan-build-result ]; then
        exit 10
    fi

    if [ $(cat $OUTPUT/cognitive-complexity.log | wc -l) -eq 0 ]; then
        exit 11
    fi
}

######

mkdir -p $OUTPUT

cd $WORKDIR

find_builddirs
search_and_install_dependencies
get_submodules
scan_build

[[ ! -f /convert2json.sh ]] && exit 0

/convert2json.sh "${REPO}" "${OUTPUT}"

chmod -R +r $OUTPUT

if [ ! -f $OUTPUT/$SREPO.scan-build.json ]; then
    echo "Converting to JSON failed"
    exit 1
fi

if [ ! -z $GITHUB_OUTPUT ]; then
    JSON=$(cat $OUTPUT/$SREPO.scan-build.json)
    echo "json=${JSON}" >> $GITHUB_OUTPUT
else
    jq '.' $OUTPUT/$SREPO.scan-build.json
fi

if [ $ERROR_ON_BUGS != "0" ]; then
    BUGCOUNT=$(jq '.bugs | length' $OUTPUT/$SREPO.scan-build.json)
    if [ $BUGCOUNT -gt 0 ]; then
        echo "Found $BUGCOUNT bugs."
        exit 1
    fi
fi
