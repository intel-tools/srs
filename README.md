# Scaling Repo Scanner (SRS)

GitHub Actions based repository scanning workflows with a primary goal of evaluating C & C++ repositories for risks.

Current scans being performed:
 - [clang's scan-build](https://clang-analyzer.llvm.org/scan-build.html): Detect common C & C++ bugs with low false-positive rate. [More details on how to integrate this scan into your CI using GitHub Actions](scan-build).
 - [clang-tidy cognitive complexity](https://clang.llvm.org/extra/clang-tidy/checks/readability/function-cognitive-complexity.html): Calculate readability score for every function. [More details on how to integrate this scan into your CI using GitHub Actions](scan-build).
 - [OSSF Scorecard](https://github.com/ossf/scorecard): Measure software development practices
 - [CLoC](https://github.com/AlDanial/cloc): Calculate lines of code

Scans run weekly and results are automatically published at [https://intel.github.io/srs](https://intel.github.io/srs)

# License

[MIT](https://github.com/intel/srs/blob/main/COPYING)

# Forking

The repository can be forked and the existing scans replaced or new ones added. All you need to add is a GitHub PAT to secrets with the name `GHPAT`.
 
## Adding more scans

1. Create a workflow YAML file under `.github/workflows/my-new-scan.yml` with the following required inputs:

```
on:
  workflow_call:
    inputs:
      repo:
        description: 'repo'
        required: true
        default: ''
        type: string
      rate-limit:
        description: 'rate limit'
        required: false
        default: 150
        type: number
    secrets:
      GHPAT:
        required: true
```

For steps you can define whatever is needed to perform the scan as you would with a workflow. Use [Upload-Artifact Action](https://github.com/actions/upload-artifact) to store the results of the scan with a key that uniquely identifies the repo and the scan, for example `some-repo.my-new-scan.results.zip`).

2. Add call to the new workflow in `.github/workflows/srs.yml`:

```
  my-new-scan:
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

```
next:
    needs: [scan-build, ossf-scorecard, metadata, my-new-scan]
```

4. Add the scan's result file (for example `my-new-scan.results.zip`) to the `aggregate` function in `query/summary.sh`.

```
    for f in $(find $ARTIFACT_DIR -type f -name '*.my-new-scan.results.zip'); do
        cp $f $ARTIFACT_DIR/aggregate-results/ || :
    done
```

Results will saved and published on GitHub Pages as part of the next scan.
