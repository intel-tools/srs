PROJECT NOT UNDER ACTIVE MANAGEMENT

This project will no longer be maintained by Intel.

Intel has ceased development and contributions including, but not limited to, maintenance, bug fixes, new releases, or updates, to this project.  

Intel no longer accepts patches to this project.

If you have an ongoing need to use this project, are interested in independently developing it, or would like to maintain patches for the open source software community, please create your own fork of this project.  

Contact: webadmin@linux.intel.com
# Scaling Repo Scanner (SRS)

GitHub Actions based repository scanning workflows with a primary goal of evaluating C & C++ repositories for risks.

Current scans being performed:
 - [clang's scan-build](https://clang-analyzer.llvm.org/scan-build.html): Detect common C & C++ bugs using static source analysis. [More details on how to integrate this scan into your CI using GitHub Actions](scan-build).
 - [clang-tidy cognitive complexity](https://clang.llvm.org/extra/clang-tidy/checks/readability/function-cognitive-complexity.html): Calculate readability score for every function. [More details on how to integrate this scan into your CI using GitHub Actions](scan-build).
 - [OSSF Scorecard](https://github.com/ossf/scorecard): Measure software development practices.
 - [CLoC](https://github.com/AlDanial/cloc): Calculate lines of code & comments.
 - [Infer](https://fbinfer.com): Infer checks for null pointer dereferences, memory leaks, coding conventions and unavailable API’s in C & C++ code.

Scans run monthly and results are automatically published at [https://intel.github.io/srs](https://intel.github.io/srs)

# License

[MIT](https://github.com/intel/srs/blob/main/COPYING)

# Forking

The repository can be forked and the existing scans replaced or new ones added. All you need to add is a GitHub PAT to secrets with the name `GHPAT`.
 
## Adding more scans

1. Create a workflow YAML file under `.github/workflows/my-new-scan.yml` with the following required inputs:

```yaml
on:
  workflow_call:
    inputs:
      repo:
        description: 'repo'
        required: true
        default: ''
        type: string
      rate-limit:
        description: 'rate limit GitHub API requests'
        required: false
        default: 150
        type: number
```

For steps you can define whatever is needed to perform the scan as you would with a workflow. Use [Upload-Artifact Action](https://github.com/actions/upload-artifact) to store the results of the scan with a key that uniquely identifies the repo and the scan, for example `some-repo.my-new-scan.results.zip`). It is advisable to check the GitHub API rate limit and sleep if there are fewer then 150 calls remaining for your token.

2. Add call to the new workflow in `.github/workflows/srs.yml`:

```yaml
on:
  workflow_dispatch:
    inputs:
      ...
      my-new-scan:
        description: 'Run my-new-scan workflow'
        required: false
        type: number
        default: 0
  ...
  jobs:
    ...   
    my-new-scan:
      if: inputs.my-new-scan == 1
      needs: matrix
      secrets: inherit
      strategy:
        matrix: ${{fromJson(needs.matrix.outputs.matrix)}}
        fail-fast: false # don't stop other jobs if one fails
      uses: ./.github/workflows/my-new-scan.yml
      with:
        repo: ${{ matrix.repo }}
```

3. Add the new scan to the `next` job's `needs` list:

```yaml
next:
    needs: [..., my-new-scan]
```

4. Add my-new-scan to the enabled workflows in `query.yml`:

```yaml
      ...
      workflows:
        description: 'List of workflows to enable (CSV)'
        required: false
        type: string
        default: '...,my-new-scan'
      ...
```

5. Add the scan's result file (for example `my-new-scan.results.zip`) to the `aggregate` function in `query/summary.sh`.

```bash
    for f in $(find $ARTIFACT_DIR -type f -name '*.my-new-scan.results.zip'); do
        cp $f $ARTIFACT_DIR/aggregate-results/ || :
    done
```

Results will be saved and published on GitHub Pages as part of the next scan.
