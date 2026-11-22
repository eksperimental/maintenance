[
  version: "0.9.0",
  # Can also be set/reset with `--autocorrect`/`--no-autocorrect`.
  autocorrect: true,
  # With "--dry" no changes will be written to the files.
  # Can also be set/reset with `--dry`/`--no-dry`.
  # If dry is true then verbose is also active.
  dry: false,
  # Enables or disables color in the output.
  color: true,
  # Can also be set/reset with `--verbose`/`--no-verbose`.
  verbose: false,
  # Can be overwritten with `--silent`/`--no-silent`.
  # When enabled, suppresses all non-essential output during execution.
  silent: false,
  # Inputs can be a path, glob expression or list of paths and glob expressions.
  # With the atom :formatter the inputs from .formatter.exs are
  # used. also allowed in the list mentioned above.
  # Can be overwritten by calling `mix recode "lib/**/*.ex"`.
  inputs: ["{mix,.formatter}.exs", "{apps,config,lib,test}/**/*.{ex,exs}"],
  formatters: [Recode.CLIFormatter],
  # Can also be set/reset with `--manifest`/`--no-manifest`.
  manifest: false,
  tasks: [
    # Tasks could be added by a tuple of the tasks module name and an options
    # keyword list. A task can be deactivated by `active: false`. The execution of
    # a deactivated task can be forced by calling `mix recode --task ModuleName`.
    {Recode.Task.AliasExpansion, []},
    {Recode.Task.AliasOrder, []},
    {Recode.Task.Dbg, [autocorrect: false]},
    {Recode.Task.EnforceLineLength, [active: false]},
    {Recode.Task.FilterCount, []},
    {Recode.Task.Format, [active: false]},
    {Recode.Task.IOInspect, [autocorrect: false]},
    {Recode.Task.LocalsWithoutParens, []},
    {Recode.Task.Moduledoc, [exclude: ["test/**/*.{ex,exs}", "mix.exs"], active: false]},
    {Recode.Task.Nesting, []},
    {Recode.Task.PipeChainStart, [active: false]},
    {Recode.Task.PipeFunOne, []},
    {Recode.Task.SinglePipe, []},
    {Recode.Task.Specs,
     [exclude: ["test/**/*.{ex,exs}", "mix.exs"], config: [only: :visible], active: false]},
    {Recode.Task.TagFIXME, [exit_code: 2]},
    {Recode.Task.TagTODO, [exit_code: 4, active: false]},
    {Recode.Task.TestFile, []},
    {Recode.Task.UnnecessaryIfUnless, []},
    {Recode.Task.UnusedVariable, [active: false]}
  ]
]
