#!/bin/bash
set -o pipefail

usage() { echo "Usage: $0 [-w <work_folder>] [-t <timeout>]" 1>&2; exit 1; }

WORKDIR=$PWD
TIMEOUT="1200"

while getopts ":t:o:w:" o; do
    case "${o}" in
        t)
            TIMEOUT=${OPTARG}
            ;;
        w)
            WORKDIR=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

echo "Setting options:"
echo "  WORKDIR: $WORKDIR"
echo "  TIMEOUT: $TIMEOUT"

##############

find_autoconf_builddir() {
  local search="configure autogen.sh bootstrap.sh bootstrap boot buildconf configure.ac"
  touch $WORKDIR/build_autoconf

  for f in $search; do
    local dir=$(find . -iname "$f" -type f -printf '%h\n')
    for d in $dir; do
      if [ $(grep "$PWD/$d" $WORKDIR/build_autoconf | wc -l) -eq 0 ]; then
        pushd $d
        s=$(find . -iname "$f" -type f | head -n1 | awk -F'/' '{ print $2 }')
        echo "Found $s in $PWD"
        echo "$PWD $s" >> $WORKDIR/build_autoconf
        popd
      fi
    done
  done
}

find_cmake_builddir() {
  local search="CMakeLists.txt"
  touch $WORKDIR/build_cmake

  for f in $search; do
    local dir=$(find . -iname "$f" -type f -printf '%h\n')
    for d in $dir; do
      echo "Found $f in $PWD/$d"
      project=$(grep 'project(' ${d}/${f} | wc -l)
      if [ ${project} -gt 0 ]; then
        echo "Top level $f found at ${d}/${f}"
        echo "$PWD/$d $f" >> $WORKDIR/build_cmake
      fi
    done
  done
}

find_meson_builddir() {
  local search="meson.build"
  touch $WORKDIR/build_meson

  for f in $search; do
    local dir=$(find . -iname "$f" -type f -printf '%h\n')
    for d in $dir; do
      project=$(grep 'project(' "$d/$f" | wc -l)
      if [ $project -gt 0 ]; then
        echo "Found $f in $PWD/$d"
        echo "$PWD/$d $f" >> $WORKDIR/build_meson
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
      pushd $dir
      git submodule update --init --recursive || :
      popd
  done
}

build_autoconf() {
    while read -r build; do

            echo "Autoconf $build"

            dir=$(echo $build | awk '{ print $1 }')
            script=$(echo $build | awk '{ print $2 }')

            cd $dir

            # don't build the same folder multiple times
            if [ -f "build-done" ]; then
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

            echo $dir >> ${WORKDIR}/configure.log

            ./configure | tee -a ${WORKDIR}/configure.log 2>&1 || continue
            infer capture -- make | tee -a ${WORKDIR}/infer.log 2>&1 || continue
            infer analyze --bufferoverrun --no-liveness | tee -a ${WORKDIR}/infer.log 2>&1

            touch "build-done"

    done < $WORKDIR/build_autoconf
}

build_cmake() {
    while read -r build; do

            echo "CMake $build"

            dir=$(echo $build | awk '{ print $1 }')

            cd $dir

            # don't build the same folder multiple times
            if [ -f "build-done" ]; then
              continue;
            fi

            echo "Attempting to build $GITHUB_WORKSPACE/repo/$dir"

            mkdir -p $dir/build
            cd $dir/build

            echo $dir >> $WORKDIR/cmake.log

            cmake DCMAKE_EXPORT_COMPILE_COMMANDS=YES $dir | tee -a ${WORKDIR}/cmake.log 2>&1 || continue
            cd ..
            infer capture --compilation-database build/compile_commands.json | tee -a ${WORKDIR}/infer.log 2>&1
            infer analyze --bufferoverrun --no-liveness | tee -a ${WORKDIR}/infer.log 2>&1

            touch $dir/build-done

    done < $WORKDIR/build_cmake
}

build_meson() {
    while read -r build; do

            echo "Meson $build"

            dir=$(echo $build | awk '{ print $1 }')

            cd $dir

            # don't build the same folder multiple times
            if [ -f "build-done" ]; then
              continue;
            fi

            echo $dir >> ${WORKDIR}/meson-setup.log

            meson setup build --buildtype debug 2>&1 | tee -a $WORKDIR/meson-setup.log || continue
            infer capture --compilation-database build/compile_commands.json | tee -a ${WORKDIR}/infer.log 2>&1
            infer analyze --bufferoverrun --no-liveness | tee -a ${WORKDIR}/infer.log 2>&1

            touch $dir/build-done

    done < $WORKDIR/build_meson
}


build_and_run_infer() {
    build_autoconf
    build_cmake
    build_meson
}

######

cd $WORKDIR

find_builddirs
search_and_install_dependencies
get_submodules
build_and_run_infer

exit 0
