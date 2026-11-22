# Plan: turn Maintenance into a CLI you run occasionally

Status: decisions made, waiting for the go-ahead to implement.

## Goal

Run a yearly job without remembering anything:

```sh
mix maintenance.status                  # what is due?
mix maintenance.run otp unicode         # build the commit locally
mix maintenance.publish otp unicode    # push that commit, open the PR
```

The app was built to run all the time on a server. It is now used by hand, a
few times a year. Code that only made sense for a server goes away.

## Non-goals

- Running it on GitHub Actions. That can come later and builds on this.
- Flattening the umbrella into one app.
- Changing what the Unicode jobs write into the Elixir and OTP repositories.

## Commands

All three are Mix tasks in `apps/maintenance/lib/mix/tasks/`. Errors go
through `Mix.raise/1`, so the exit code is non-zero.

### `mix maintenance`

Prints the three commands below and the configured projects and jobs.

### `mix maintenance.status [PROJECT [JOB]]`

For every project/job pair (or the ones given), prints one line:

```
otp     unicode  16.0.0 -> 17.0.0  due
elixir  unicode  17.0.0            up to date
otp     unicode  16.0.0 -> 17.0.0  PR open: https://github.com/...
```

Uses the network but never touches the git cache. Works without
`GITHUB_ACCESS_TOKEN` (unauthenticated GitHub API reads).

### `mix maintenance.run PROJECT JOB`

Same as `Maintenance.Runner.update/2` today with publishing disabled:
refresh the cache checkout, write the files, commit on `unicode_<version>`.
It then prints the checkout path and a diffstat, plus the command to inspect
the commit (`git -C <path> show --stat`) and the publish command.

It can be rerun: it resets to upstream and rebuilds the branch. If GitHub
already has a PR for that branch, it prints the URL and does nothing.

Unknown project or job: the error lists the valid ones.

### `mix maintenance.publish PROJECT JOB [--fork OWNER]`

Pushes the branch that `run` left behind, without rebuilding it, and opens
the PR inside the fork. Steps:

1. Ask the job which branch it would use (`status/1`, below).
2. Fail with "run `mix maintenance.run PROJECT JOB` first" if the branch is
   missing or has no commits on top of main.
3. If GitHub already has a PR from that branch, print its URL and stop.
4. Push the branch and fast-forward the fork's main (`Git.push/2`, as today).
5. Open the PR. The title is the commit subject and the body is the current
   default body.

This is the only command that needs `GITHUB_ACCESS_TOKEN`.

## Code changes

### Job contract (`MaintenanceJob`)

Replace `update/1` (which checks, writes, commits and publishes) with:

- `status(project) :: {:due, info} | {:up_to_date, info}`, where
  `info` has `current`, `latest` and `branch`. Network only, no git.
- `prepare(project) :: {:ok, :committed, branch} | {:ok, :no_update_needed} | {:error, term}`.
  Writes and commits. Never pushes.

`job/0` and `implements_project?/1` stay. The optional `needs_update?/3`
and `run_tasks/3` callbacks leave the behaviour. `run_tasks` becomes a
private function of `MaintenanceJob.Unicode`.

### Publishing becomes generic

A new `Maintenance.Publish` module does the publish steps above for any job.
`Git.submit_pr/3`, `Git.produce_commit/4`,
`Git.checkout_new_branch_and_produce_commit!/4` and the commit-and-submit
code in `unicode.ex` collapse into it.

### Duplicate PRs: ask GitHub, not CubDB

Add `Github.find_pull_request(owner, repo, head)`
(`GET /repos/{owner}/{repo}/pulls?head=owner:branch&state=all`). It replaces
`pr_exists?` and the `DB.put` in `Git.open_pull_request`. State in
`~/maintenance_data/database` is lost on a new machine and forgotten after
a year. GitHub is the record.

### Fork selection: the runner's account, not `MIX_ENV`

`MIX_ENV` used to pick the fork between two fixed accounts. Now the config
holds only the upstream projects. The fork is the one of `GITHUB_ACCOUNT`,
set in `.env`, and `--fork OWNER` picks another one. `status`, `run` and
`publish` all take `--fork`, and each stops when neither is given.
`Maintenance.env!/0` goes away.

The config holds no name or email either. Commits use the Git identity of
whoever runs the app, and `run` stops when Git has none.

### Token read only when needed

`config/runtime.exs` stops calling `System.fetch_env!("GITHUB_ACCESS_TOKEN")`.
`Maintenance.github_access_token!/0` reads the variable when called and
raises a message that says to put it in `.env` and `source .env`.
`MAINTENANCE_PUBLISH` and `Maintenance.publish?/0` go away: running
`publish` is the opt-in.

## Removals

| What | Why it existed |
|---|---|
| Quantum, `MaintenanceJob.Scheduler`, cron entries in `config.exs` | Run on a timer |
| Swoosh, `Maintenance.Mailer`, mailer config | Notify while unattended. Nothing calls it. |
| `releases` in `mix.exs`, `build.sh`, `RELEASE_MODE` / `prod_release?` | Deploy to a server |
| `setup.sh` | Sets **global** git config on the machine. `Git.config/1` already sets it per checkout. |
| CubDB, `Maintenance.DB`, `Project.list_entries_by_job/2`, `data_dir_backup` | Remember PRs between scheduled runs |
| `Maintenance.Runner` | Replaced by the tasks |
| Startup log about publishing in `Maintenance.Application` | Publishing is now a command |

`Maintenance.Application` keeps only `Maintenance.TaskSupervisor`, which the
Unicode downloads use (`unicode.ex:544`).

Also removed (decision 1): `elixir_releases.ex`, `otp_releases.ex`,
`sample_job.ex`, the unreferenced `data.ex`, and the `beam_langs_meta_data`
path dependency, which stops a fresh clone from building.

## Delivery: one commit per step, each verified

1. **Remove the release and sample jobs.** Check:
   `mix compile --warnings-as-errors`, `mix test`.
2. **Remove server leftovers** (Quantum, Swoosh, releases, `setup.sh`). Same checks.
3. **Detect existing PRs through GitHub; delete CubDB.** Tests for
   `find_pull_request` with `Req.Test` stubs (found, not found, API error).
4. **Read the token only when it is used.** Check: `mix run -e
   'IO.inspect(Maintenance.projects())'` with the variable unset.
5. **Split the job contract and add `Maintenance.Publish`; `GITHUB_ACCOUNT`
   and `--fork` replace `MIX_ENV`; drop `MAINTENANCE_PUBLISH`.** Tests against a local bare
   repository, like `git_test.exs`: publish pushes the existing commit
   unchanged and opens a PR titled with its subject; an existing PR means no
   push; a missing branch gives the "run first" error.
6. **Add the Mix tasks.** Tests for argument errors. Then on the real thing:
   `mix maintenance.status` and `mix maintenance.run otp unicode` against the
   real network, with no publish.
7. **Rewrite the README Usage section** around the three commands.

A real `mix maintenance.publish` opens a public PR, so it runs only when
you ask for it.

## Decisions

1. Delete the release jobs, the sample job, `data.ex` and the
   `beam_langs_meta_data` dependency. Git history keeps them.
2. `--fork` is optional and defaults to `GITHUB_ACCOUNT`. Without either,
   the error says how to set `GITHUB_ACCOUNT`.
3. The PR title is the commit subject, for example "Update Unicode to version
   17.0.0".
