# Hotpath Relay

A GitHub Action that uploads [hotpath-rs](https://hotpath.rs) Rust performance reports from pull requests, including pull requests from forks, to [hotpath-cloud](https://hotpath.rs/cloud).

Fork pull requests get no OIDC token, so the benchmark job stores its report as an artifact. This action runs in a separate `workflow_run` workflow, finds the pull request through the GitHub API, and uploads the report without checking out or running any pull request code.

## Usage

`.github/workflows/hotpath-relay.yml`:

```yaml
name: hotpath relay

on:
  workflow_run:
    workflows: ["Benchmark"] # the `name:` of your benchmark workflow
    types: [completed]

permissions: {}

jobs:
  relay:
    runs-on: ubuntu-latest
    permissions:
      actions: read # download the report artifact
      id-token: write # authenticate the upload
      pull-requests: read # find the pull request
    steps:
      - uses: hotpath-rs/hotpath-relay@v1.0.0
        with:
          benchmark: my_benchmark
```

The benchmark workflow, inputs and troubleshooting: [setup and usage docs](https://hotpath.rs/ci_integration).
