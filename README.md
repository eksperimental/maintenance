# Maintenance BEAM

[`Maintenance` BEAM project](https://github.com/eksperimental/maintenance) is an
app which aims to automatize tasks in codebases of the Elixir, Erlang,
or any other project using a Git repository (only GitHub is initially supported).

## Feature Requests & Bug reports

Feel free to open up an issue <https://github.com/eksperimental/beam_meta/issues> with your request/report.

## Usage

Maintenance is for occasional use: run it when a new version of Unicode comes out, which is about once a year. It is three Mix commands, run from the root of this repository.

```sh
mix maintenance                          # the commands, projects, jobs and the default fork
mix maintenance.status [PROJECT [JOB]]   # which jobs are due
mix maintenance.run PROJECT JOB          # build the commit locally
mix maintenance.publish PROJECT JOB      # push it and open the pull request
```

### 1. See what is due

```sh
mix maintenance.status
```

```text
elixir  unicode  17.0.0 -> 18.0.0  due
otp     unicode  17.0.0 -> 18.0.0  due
```

A job is `due`, `up to date`, or due with a pull request that is already open
(`PR open: <url>`). The command reads from unicode.org and GitHub. It needs no token.

### 2. Build the commit

```sh
mix maintenance.run otp unicode
```

This updates the checkout under `~/maintenance_data/cache` and commits the changes to
a new branch there. Nothing is pushed. The command prints the path of the checkout, the
files that changed, and the `git show` command to inspect the commit. It does nothing
if the job is up to date or a pull request for it is already open. You can run it again:
it starts from the upstream branch each time.

### 3. Publish it

Publishing is the only step that needs a GitHub token. Store `GITHUB_ACCESS_TOKEN` in
`.env` and run `source .env` in your terminal.

```sh
mix maintenance.publish otp unicode
```

Pull requests are opened inside a fork, never in the upstream project
(`elixir-lang/elixir` or `erlang/otp`), from the new branch into the fork's main branch.
The upstream projects and your GitHub account are configured in `config/config.exs`.
Set `author_github_account` to the account that owns `GITHUB_ACCESS_TOKEN`. Its fork is
used by default.

To use the fork of another account the token can push to, such as an organization, pass
`--fork OWNER` to `status`, `run` and `publish`. `status` and `run` look for an open
pull request on that same fork.

The title of the pull request is the subject of the commit.

The command pushes the commit that `mix maintenance.run` built, as it is. If there is
no such commit, it tells you to run `mix maintenance.run PROJECT JOB` first. If a
pull request for the branch already exists on the fork, it prints its URL and pushes
nothing.

Each publish also fast-forwards the fork's main branch to the upstream commit
the job started from, so the pull request shows only the new commits. If the
fork's main branch has commits of its own, nothing is pushed and no pull
request is opened.

## Contact

Eksperimental <eksperimental (at) tutamail (dot) com>

## License

No Copyright

This work is released to the
[Public Domain](https://creativecommons.org/publicdomain/mark/1.0/) and multi-licensed under the
[Creative Commons Zero Universal version 1.0 license](https://creativecommons.org/publicdomain/zero/1.0/),
the [MIT No Attribution license](https://spdx.org/licenses/MIT-0.html),
and the [BSD Zero Clause license](https://opensource.org/licenses/0BSD).

You can choose between one of them if you use this work.

The author, [Eksperimental](https://github.com/eksperimental) has dedicated the work to the
public domain by waiving all copyright and related or neighboring rights to this work worldwide
under copyright law including all related and neighboring rights, to the extent allowed by law.

You can copy, modify, distribute and create derivative work, even for commercial purposes, all
without asking permission. Giving credits is appreciated though;
you may link to this repository if you wish.

<p xmlns:dct="https://purl.org/dc/terms/">
  <a rel="license" href="https://creativecommons.org/publicdomain/mark/1.0/">
    <img src="https://i.creativecommons.org/p/mark/1.0/88x31.png"
       style="border-style: none;" alt="Public Domain Mark" />
  </a><br />
  <a rel="license"
     href="https://creativecommons.org/publicdomain/zero/1.0/">
    <img src="https://i.creativecommons.org/p/zero/1.0/88x31.png" style="border-style: none;" alt="Creative Commons Zero" />
  </a>
</p>

Check the [NOTICE](NOTICE),
[LICENSES/LICENSE.CC0-1.0.txt](LICENSES/LICENSE.CC0-1.0.txt),
[LICENSES/LICENSE.MIT-0.txt](LICENSES/LICENSE.MIT-0.txt),
[LICENSES/LICENSE.0BSD.txt](LICENSES/LICENSE.0BSD.txt) files for more information.

`SPDX-License-Identifier: CC0-1.0 or MIT-0 or 0BSD`
