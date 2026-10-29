# Releasing

Versions are `vMAJOR.MINOR.PATCH` tags of immutable GitHub releases. A published tag is never moved or deleted, and there is no moving `v1` tag. A fix is a new patch release.

## Before the first release (once)

1. **Immutable releases.** Repository **Settings**, section **Releases**: select **Enable release immutability**. It applies only to releases published after it is enabled, so do this before `v1.0.0`. (Organization alternative: org **Settings** > **Repository** > **General** > **Releases**: **Selected repositories** with `hotpath-relay`.)
2. **Tag ruleset** (belt and braces for tags not yet bound to a release): **Settings** > **Rules** > **Rulesets** > **New ruleset** > **New tag ruleset**, target `v*`, enable **Restrict updates** and **Restrict deletions**, no bypass list.
3. **Marketplace agreement.** An organization owner of `hotpath-rs` accepts the GitHub Marketplace Developer Agreement (the link appears in the release form in step 3 of "Publishing" below).
4. **Two-factor authentication** on the account that publishes.
5. Make sure the name `Hotpath Relay` is free on the Marketplace (no action, user, organization or category of that name); the release form reports a clash.

## Validation (before every release)

1. CI is green on `main` (shellcheck, actionlint).
2. Integration test against hotpath.rs. `workflow_run` workflows run from the default branch only, so the relay under test is pinned on a default branch by commit SHA (`hotpath-rs/hotpath-relay@<sha of main>`), never by a tag that does not exist yet:
   - **Same-repository canary.** In hotpath-backend, point the relay job of `.github/workflows/hotpath-relay.yml` (on its default branch) at the action, then push an empty commit to pull request #177 (`relay-canary`, it rewrites `meta.ci.pull_request.number` to 176). Expect: relay run green, comment on #177 and not on #176, step summary with `HTTP 201`.
   - **Fork pull request.** In hotpath-rs/hotpath, switch `cloud-benchmark-relay.yml` on `main` to the action (keeping its `if:`, lookup and permissions). From a fork owned by another account, open a pull request touching a benchmarked crate. Expect: the benchmark job has no `id-token`, the relay run uploads, the comment and the `hotpath / <benchmark>` check appear on the fork's pull request, and the relay run log shows no checkout.
   - **Negative cases** on the fork pull request: push a commit that breaks the benchmark (relay notice "concluded 'failure'", nothing uploaded); push two commits quickly (the older run is cancelled or finds no pull request); a branch named like `x$(touch${IFS}pwned)` (lookup still works, nothing executed).
3. Read the step summaries of the relay runs; each names the server's request id.

## Publishing `v1.0.0`

1. Merge the release commit to `main` and note its full SHA: `git rev-parse origin/main`.
2. Open `action.yml` on GitHub and click **Draft a release** in the banner (or **Releases** > **Draft a new release**).
3. Check **Publish this Action to the GitHub Marketplace** and fix anything reported until it says "Everything looks good!".
4. **Primary Category**: Continuous integration; **Another Category**: Testing.
5. **Tag**: `v1.0.0`, created on publish, **Target**: the SHA from step 1 (pick the commit, not just the branch, if `main` may move).
6. **Title**: `v1.0.0`; notes: the change summary. Leave it as the latest release.
7. **Publish release** (asks for 2FA).
8. Check: the release page shows it as immutable, and `git ls-remote https://github.com/hotpath-rs/hotpath-relay refs/tags/v1.0.0` names the SHA from step 1. Use that SHA for the hotpath docs and for `cloud-benchmark-relay.yml`.

Later releases repeat "Validation" and "Publishing" with the next version; bump every `@v1.0.0` in `README.md` in the release commit.
