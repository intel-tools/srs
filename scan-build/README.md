## scan-build dockerized

This folder contains the scripts and Dockerfile necessary to build a Dockerized
version of clang's scan-build with Z3 cross-check support. It also performs a clang-tidy cognitive
complexity analysis on all functions found in the project during build.

### scan-build.sh

This script is set as the ENTRYPOINT for the Docker image. It expects a
shared folder to be mounted at /work with the code to be scanned placed inside.

Inputs:

```
-r: Name of the repository in {owner}/{repo} format (for example "intel/srs").
-l: LLVM version to use, default is 15
-t: Timeout value for each scan , default is "30m"
-o: Name of the folder to use for storing the results
```

Outputs:

The scan-build HTMLs will placed in the shared host folder at /work/{owner}.{repo}/scan-build-result or
if no name has been specified at /work/scan-build-result/scan-build-result.

The clang-tidy cognitive complexity log will be in cognitive-complexity.log in the result folder.

A combined json of the scan-build results and the cognitive complexity analysis will be in scan-build.json.

### Build it

```
cd scan-build
docker build . -t scan-build
```

### Run it

```
docker run -v $FOLDER_CONTAINING_REPOSITORY:/work scan-build
```

### Use it as a GitHub Action

The branch `scan-build-action-v1` contains the action.yml to run this Dockerfile as
a GitHub Action so you can integrate it into your CI easily.

#### Inputs (all optional)

 - `repository`: {owner}/{repo} (for example `${{ github.repository }}`)
 - `error-on-bugs`: Make action exit with error code in case bugs were found
 - `timeout`: limit how long scan-build process runs (default: 30m)
 - `llvm-version`: version of clang to use (default: 15)

#### Output
 - `bugs`: The number of bugs found during the scan
 - `json`: The json formatted results of the scan-build and cognitive complexity analysis

#### Defining additional build-steps

In case your repository needs additional packages and/or build preparation steps
before scan-build you can add a `bootstrap.sh` script which will be run in the
Docker container before scan-build.

#### Example workflows

The simplest way is to run the scan and error on any bugs found

```yaml
name: Intel SRS scan-build action using clang
on:
  pull_request:
    branches: [ main ]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: intel/srs@scan-build-action-v1
        with:
          error-on-bugs: 1
```

You can also save the results if you prefer:

```yaml
name: Intel SRS scan-build action using clang
on:
  pull_request:
    branches: [ main ]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: intel/srs@scan-build-action-v1
        id: scan-build
        with:
          repository: ${{ github.repository }}

     - name: create scan-build-result tarball
       run: tar czvf scan-build-result.tar.gz scan-build-result

     - name: save results
       uses: actions/upload-artifact@v3
       with:
         name: ${{github.repository }}.scan-build-result
         path: scan-build-result.tar.gz

    - name: error if bug(s) found
      run: |
        [[ ${{ steps.scan-build.outputs.bugs }} -gt 0 ]] && exit 1
```

If you want to error only on certain types of bugs you can parse the `scan-build-result/scan-build.json`
file using `jq`. For example, if you don't want to error on cognitive complexity issues:

```yaml
    - name: error only on non-complex bugs
      run: |
        BUGS=$(jq '.bugs[] | select( any(.; .type != "Cognitive complexity") ) | length' scan-build-result/scan-build.json | wc -l)
        [[ $BUGS -gt 0 ]] && exit 1
```

If you want to error only if the bug count increased compared to your main branch:

```yaml
name: Intel SRS scan-build action using clang
on:
  pull_request:
    branches: [ main ]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: intel/srs@scan-build-action-v1

      - name: backup scan-build-result
        run: mv scan-build-result /tmp

      - uses: actions/checkout@v3
        with:
          ref: main
      - uses: intel/srs@scan-build-action-v1

      - name: error if bug count increased
        run: |
          BUGS_IN_MAIN=$(jq '.bugs | length' scan-build-result/scan-build.json)
          BUGS_IN_PR=$(jq '.bugs | length' /tmp/scan-build-result/scan-build.json)

          [[ ${{ BUGS_IN_PR }} -gt ${{ BUGS_IN_MAIN }} ]] && exit 1
```
