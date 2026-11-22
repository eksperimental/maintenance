# Maintenance BEAM

[`Maintenance` BEAM project](https://github.com/eksperimental/maintenance) is an
app which aims to automatize tasks in codebases of the Elixir, Erlang,
or any other project using a Git repository (only GitHub is initially supported).

It is mainly used to keep Unicode in Erlang/OTP and Elixir updated to the latest version.
See the pull requests submitted to
[Erlang/OTP](https://github.com/erlang/otp/pulls?q=is%3Apr+in%3Atitle+%22Update+Unicode%22) and
[Elixir](https://github.com/elixir-lang/elixir/pulls?q=is%3Apr+%28in%3Atitle+%22Update+Unicode%22+OR+in%3Atitle+%22Upgrade+Unicode%22%29).

## Feature Requests & Bug reports

Feel free to open up an issue <https://github.com/eksperimental/maintenance/issues> with your request/report.

## Usage

Maintenance is for occasional use: run it when a new version of Unicode comes out, which is about once a year. It is three Mix commands, run from the root of this repository.

```sh
mix maintenance                          # the commands, projects, jobs and the default fork
mix maintenance.status [PROJECT [JOB]]   # which jobs are due
mix maintenance.run PROJECT JOB          # build the commit locally
mix maintenance.publish PROJECT JOB      # push it and open the pull request
```

### Before you start

Nothing about you is stored in this repository. The commits are authored with your own
Git identity, and `mix maintenance.run` stops if Git does not have one:

```sh
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Copy `.example.env` to `.env`, which Git ignores, put your GitHub account and token in
it, and run `source .env` in your terminal:

```sh
export GITHUB_ACCOUNT=your-account
export GITHUB_ACCESS_TOKEN=your-token
```

`GITHUB_ACCOUNT` names the fork that pull requests are opened in, and each command
takes `--fork OWNER` to use another one.

#### Create the token

The token is used only by `mix maintenance.publish`, which pushes to the fork and
opens the pull request inside it. Nothing is written to the upstream projects, so the
token needs access to your forks only.

1. Fork [elixir-lang/elixir](https://github.com/elixir-lang/elixir) and
   [erlang/otp](https://github.com/erlang/otp) into the account of `GITHUB_ACCOUNT`.
2. On GitHub, go to **Settings** > **Developer settings** > **Personal access tokens** >
   **Fine-grained tokens**, and select **Generate new token**.
3. Set **Resource owner** to the account that holds the forks.
4. Under **Repository access**, select **Only select repositories**, and select the
   `elixir` and `otp` forks.
5. Under **Repository permissions**, set:
   - **Contents**: Read and write. Publishing pushes the branch and fast-forwards the
     fork's main branch.
   - **Pull requests**: Read and write. Publishing opens the pull request.
   - **Workflows**: Read and write. The upstream commits that the fork's main branch is
     fast-forwarded to often change files in `.github/workflows`, and GitHub rejects
     those pushes without this permission.

   GitHub adds **Metadata**: Read-only by itself.
6. Generate the token, and put it in `.env` as `GITHUB_ACCESS_TOKEN`.

A classic token works too, with the `repo` and `workflow` scopes, but it can reach every
repository of the account.

To commit with another identity than your global one, add it to `.env` too:

```sh
export GIT_AUTHOR_NAME="Your Name"
export GIT_AUTHOR_EMAIL="you@example.com"
export GIT_COMMITTER_NAME="Your Name"
export GIT_COMMITTER_EMAIL="you@example.com"
```

These variables apply to every Git command in the terminal where you ran `source .env`,
not only to this app.

### 1. See what is due

```sh
mix maintenance.status
```

```text
elixir  unicode  17.0.0 -> 18.0.0  due
otp     unicode  17.0.0 -> 18.0.0  due
```

A job is `due`, `up to date`, or due with a pull request that is already open
(`PR open: <url>`). A pull request that was closed without being merged does not block
the job: it shows as `due (closed PR: <url>)`, and `run` and `publish` go ahead. The
command reads from unicode.org and GitHub. It needs no token.

A job that cannot be checked shows the error on its line, and the command exits with an
error after it prints every line. For example, `error: <account>/otp not found on GitHub`
means that the account has no fork of `erlang/otp`. `run` and `publish` stop with the same
message. GitHub answers 60 requests an hour without a token, and the line says when
that limit resets once it is used up.

A `unicode` job says which Unicode version it could not find. `error: current Unicode
version not found in <url>` means that the project's source file at `<url>` has no version
where Maintenance looks for it, so the file has likely changed. `error: latest Unicode
version not found at https://www.unicode.org/versions/latest/` means that the page did not
redirect to the page of a Unicode version. When GitHub answers the request for the file with
an HTTP error, the line says `error: could not download <url> (HTTP <status>)`. When the
file or the page cannot be reached, it says `error: network error (<reason>)` instead.

### 2. Build the commit

```sh
mix maintenance.run otp unicode
```

This updates the checkout under `~/maintenance_data/cache` and commits the changes to
a new branch there. Nothing is pushed. The command prints the path of the checkout, the
files that changed, and the `git show` command to inspect the commit. It does nothing
if the job is up to date or a pull request for it is already open. You can run it again:
it starts from the upstream branch each time.

The Unicode files are downloaded from unicode.org once and then read from the cache. When a
download fails, `run` stops with `could not download <url> (HTTP <status>)` or
`network error (<reason>)`, and leaves the checkout as it was. When a downloaded zip lacks a
file the job copies, `run` stops with `<file> missing from <url>` before it touches the
checkout. When Git cannot clone or update the
checkout, for example because GitHub cannot be reached, `run` stops with the Git command
and the first line of what Git said, such as `git clone ... failed: fatal: unable to access ...`.

### 3. Publish it

Publishing is the only step that needs a GitHub token. It is in `.env`, from
[Before you start](#before-you-start).

```sh
mix maintenance.publish otp unicode
```

Pull requests are opened inside a fork, never in the upstream project
(`elixir-lang/elixir` or `erlang/otp`), from the new branch into the fork's main branch.
The fork of `GITHUB_ACCOUNT` is used by default.

To use the fork of another account the token can push to, such as an organization, pass
`--fork OWNER` to `status`, `run` and `publish`. `status` and `run` look for an open
pull request on that same fork.

The title of the pull request is the subject of the commit.

The command pushes the commit that `mix maintenance.run` built, as it is. If there is
no such commit, it tells you to run `mix maintenance.run PROJECT JOB` first. If an
open pull request for the branch already exists on the fork, it prints its URL and
pushes nothing.

Each publish also fast-forwards the fork's main branch to the upstream commit
the job started from, so the pull request shows only the new commits. If the
fork's main branch has commits of its own, nothing is pushed and no pull
request is opened. To discard those commits, open the fork on GitHub, click
**Sync fork**, then **Discard commits**. Then run `mix maintenance.publish` again.

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
