# bootstrapmate-macintosh

## Worktrees

Create development worktrees **inside this repo** at `./.worktrees/<name>` — never as sibling `<repo>.worktree` folders next to it. Use the global `git wt` alias, which resolves the repo root and places the worktree under `.worktrees/` from any subdirectory:

```bash
git wt <name> [branch]
```

That runs `git worktree add .worktrees/<name> [branch]`. Keep `/.worktrees/` listed in this repo's `.gitignore`.
