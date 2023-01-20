## scan-build dockerized

This folder contains the scripts and Dockerfile necessary to build a Dockerized
version of clang's scan-build with Z3 cross-check support. It also performs a clang-tidy cognitive
complexity analysis on all functions found in the project during build.

### scan-build.sh

This script is set as the ENTRYPOINT for the Docker image and takes three inputs. It expects a
shared folder to be mounted at /work and the target repository already to be cloned at /work/repo.

Inputs:

```
$1: Name of the repository in {owner}/{repo} format (for example "intel/srs").
$2: LLVM version to use, default is 15
$3: Timeout value for each scan , default is "30m"
```

Outputs:

The scan-build HTMLs will placed in the shared host folder at /work/{owner}.{repo}/scan-build-result

The clang-tidy cognitive complexity log will be at /work/{owner}.{repo}/cognitive-complexity.log

### convert2json.sh

Given a folder containing scan-build.sh results convert the HTML and cognitive complexity reports to JSON.

Input:
```
$1: Folder containing scan-build.sh output (ie. {owner}.{repo})
```

The resulting JSON will be placed in the input folder as `result.json`.
