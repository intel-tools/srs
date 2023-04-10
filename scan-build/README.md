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

#### Inputs (all optional)

 - `repository`: {owner}/{repo} (for example `${{ github.repository }}`)
 - `error-on-bugs`: Make action exit with error code in case bugs were found
 - `timeout`: limit how long scan-build process runs (default: 30m)
 - `llvm-version`: version of clang to use (default: 15)

#### Output
 - `json`: The json formatted results of the scan-build and cognitive complexity analysis

#### Defining additional build-steps

In case your repository needs additional packages and/or build preparation steps
before scan-build you can add a `bootstrap.sh` script which will be run in the
Docker container before scan-build.

#### Example workflows

The simplest way is to run the scan and error on any bugs found

```
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

```
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
          repository: ${{ github.repository }}

     - name: save scan-build result
       run: tar czvf scan-build-result.tar.gz scan-build-result

     - uses: actions/upload-artifact@v3
       with:
         name: ${{github.repository }}.scan-build-result
         path: scan-build-result.tar.gz

    - name: error if bug(s) found
      run: [[ $(jq '.bugs | length' scan-build-result/scan-build.json) -gt 0 ]] && exit 1
```
