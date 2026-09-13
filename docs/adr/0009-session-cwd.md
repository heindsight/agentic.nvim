# 0009. Session CWD

- Status: accepted
- Last updated: 2026-09-13
- Related: none yet

## Context

Every provider-facing directory was read live from `vim.fn.getcwd()` at the
moment a request was built: `session/new` in `ACPClient:create_session`,
`session/load` in `SessionStarter`, `session/list` in `SessionRestore`. The
file picker, the `@` paths it inserts, and `EnvironmentInfo`'s git summary all
ran in Neovim's process cwd. Observed failures:

- A user editing files in a project other than Neovim's cwd got an ACP session
  rooted in the wrong directory, and no configuration could change that.
- `/new`, provider switch and restore could each land in a different directory
  from the conversation they replaced, depending on where the user had `:cd`'d
  meanwhile.
- The picker inserts `@relative` text that the plugin never parses; the
  provider resolves it against the ACP session's cwd. Anchoring the picker to a
  directory other than the one sent on `session/new` makes `@x` name the wrong
  file.
- Two "Untitled" sessions on one provider in different repositories were
  indistinguishable in the session picker.

## Current decision

Each `SessionManager` owns one **Session CWD** (see `CONTEXT.md`), an absolute
directory fixed at creation and never re-derived.

**Resolution order, one resolver, one fallback.** In priority order: an explicit
`opts.cwd` from `Agentic.new_session`, `Agentic.restore_session` or
`Agentic.restore_session_by_id`; else the source `SessionManager`'s Session CWD
when one session starts another; else `Config.settings.session_cwd(ctx)` run on
the buffer the user acted from, `ctx = { bufnr }`; else `vim.fn.getcwd()`. Every
value passes through the same normalisation and validation; a non-string,
non-directory, or erroring function is reported through `Logger.notify` and
falls back to `vim.fn.getcwd()`. Session creation never aborts on a bad cwd.

**Inheritance sites.** `/new`, `Agentic.new_session` fired inside a widget
buffer, provider switch and restore with a live source all inherit through
`SessionRegistry.replace` or the widget-owning session. Restore and switch with
no live source run the derive rule on the current buffer, exactly like a fresh
keybinding.

**Reuse never re-derives.** `Agentic.open`, `toggle` and the `add_*` entry
points resolve through `SessionRegistry.resolve_or_create`; when a session
exists it is reused whatever project the acting buffer belongs to. Only
`new_session` creates a session rooted elsewhere.

**What follows the Session CWD.** `session/new`, `session/load` and the
`session/list` filter; the picker scan's process cwd and the relative form of
the `@` entries it inserts; the `@` lines `FileList` writes to the chat;
`EnvironmentInfo`'s project root and git commands; the oldfile placeholder
`ChatWidget:open_editor_window` picks.

**What stays on Neovim's cwd.** Display-only relative paths in
`CodeSelection`, `DiffPreview` and `DiagnosticsList`, and the clipboard's
last-resort image directory.

**Exposure.** `HeaderParts.cwd` for custom headers (default rendering
unchanged); every hook payload that carries `session_key` also carries `cwd`;
`SessionNavigation.select` rows always append the `~`-shortened path.

## Consequences

- `vim.fn.getcwd()` may only be read as the last fallback of the resolver. Any
  other read is a regression to the pre-ADR behaviour.
- Relative paths that reach the provider must be made relative to the Session
  CWD explicitly. `fnamemodify(":.")` resolves against Neovim's cwd and is
  wrong for picker output.
- `vim.fn.system` inherits Neovim's process cwd, so scans and git summaries run
  through `vim.system` with an explicit `cwd`.
- A session's cwd can diverge from Neovim's cwd for its whole life. Users who
  `:cd` expecting the chat to follow must start a new session.
- Adding `cwd` to hook payloads is additive; hook signatures do not change.

## Rejected / superseded alternatives

| Option                                                    | Reason rejected                                                                                                         |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Read `vim.fn.getcwd()` at request time (prior behaviour)  | Wrong root for files outside Neovim's cwd; replacements drifted with `:cd`.                                             |
| Auto-create a session when `open` hits a project mismatch | Silently spawns provider work; the repo has already shipped four such call sites by accident (ADR 0008).                |
| Declarative `root_markers` list instead of a function     | `vim.fs.root(ctx.bufnr, markers)` is the same thing in one line; two shapes need precedence rules.                      |
| Abort session creation on an invalid cwd                  | A broken config would leave the user with no chat at all.                                                               |
| Make every `to_smart_path` caller Session-CWD-relative    | Diff preview and diagnostics carry absolute paths from the provider or LSP; only picker and file-list output is at stake. |
| Re-derive the cwd when the user changes buffer or `:cd`   | The ACP session's cwd is fixed by the provider at `session/new`; re-deriving locally would desynchronise `@` paths.      |

## Changelog

| Date       | Change                                                              |
| ---------- | ------------------------------------------------------------------- |
| 2026-09-13 | Initial decision: per-session cwd, resolved once, inherited through replacement. |
