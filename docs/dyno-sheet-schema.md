# LJ OS Daily Dyno Sheet Schema

Schema version: `0.1.0`

A portable JSON file produced by obsidian-lj-os-cli and consumed by obsidian-lj-os-plugin.

## File path

```text
<vaultPath>/<statsOutputPath>/YYYY-MM-DD.json
```

## Top-level fields

- `schemaVersion`: string, currently `0.1.0`.
- `date`: local date in `yyyy-MM-dd` format.
- `generatedAt`: ISO timestamp for when the file was written.
- `source`: `obsidian-lj-os-cli`.
- `machine`: object with `name` and `user`.
- `summary`: aggregate repo activity counts.
- `repos`: included repo activity objects.
- `notes`: reserved array for future local notes.

## Summary fields

- `reposScanned`: number of Git repos discovered after ignore filtering.
- `reposIncluded`: number of repos written to `repos`.
- `reposTouchedToday`: number of scanned repos where `touchedToday` is `true`.
- `commitsToday`: total commits since local midnight.
- `dirtyRepos`: number of scanned repos with `git status --porcelain` output.
- `unpushedCommits`: total commits ahead of configured upstream branches.
- `behindCommits`: total commits behind configured upstream branches.

## Repo fields

- `name`: repo folder name.
- `path`: absolute local repo path.
- `branch`: current branch name, or `HEAD`/empty when detached or unborn.
- `hasCommits`: `true` when `git rev-parse --verify HEAD` succeeds.
- `touchedToday`: `true` when `commitsToday` is greater than zero; for empty repos, `true` only when the repo is dirty.
- `commitsToday`: commits found with `git log --since`.
- `dirty`: `true` when `git status --porcelain` has output.
- `unpushedCommits`: commits ahead of upstream, or `0` when no upstream exists.
- `behindUpstream`: commits behind upstream, or `0` when no upstream exists.
- `latestCommit`: object with `hash`, `message`, and `time`, or `null` when the repo has no commits.
- `notes`: repo-level notes. Empty repos include `Git repository has no commits yet.`

When `includeReposWithNoActivity` is `false`, `repos` includes repos with `touchedToday`, `dirty`, `unpushedCommits > 0`, or `behindUpstream > 0`. Empty repos are included only when dirty or when `includeEmptyRepos` is `true`.

## Config fields

- `vaultPath`: absolute path to the Obsidian vault.
- `statsOutputPath`: folder inside the vault where JSON files are written.
- `repoRoots`: folders scanned recursively for `.git` directories.
- `repoIgnoreNames`: repo folder names to skip.
- `authorName`: optional Git author filter for today's commits.
- `includeReposWithNoActivity`: include every scanned repo when `true`.
- `includeEmptyRepos`: include clean Git repos with no commits when `true`.

