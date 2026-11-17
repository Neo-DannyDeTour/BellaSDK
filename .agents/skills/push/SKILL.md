---
name: push
description: Group uncommitted changes into small, logical conventional commits and push to GitHub.
---

# `/push` — Atomic Commits & Push

Split all uncommitted changes into small, logical commits (one per feature, fix, asset, or config change) and push to `origin`.

## Steps

1. **Inspect working tree**:
   - Run `git status --short` and `git diff --stat`.
   - If working tree is clean and nothing is ahead of `origin`, report clean status and stop.

2. **Safety check**:
   - Pause and ask user before staging if any untracked secrets (`.env`, `*.key`, credentials) or unexpected large binaries appear.
   - Never force-push (`--force`) or rewrite history.

3. **Group into atomic commits**:
   - Partition modified/untracked files into small, cohesive groups by scope/feature/change (e.g., one commit per system, scene, asset, or doc update).
   - Never lump unrelated changes into one large commit.

4. **Commit each group**:
   - Stage only the files for the current group: `git add <files>`.
   - Write a Conventional Commit message:
     - Header: `<type>(<scope>): <summary>` (`<= 72` chars; types: `feat`, `fix`, `refactor`, `perf`, `docs`, `chore`, `test`, `assets`).
     - Body: concise bulleted list of what changed and why.
   - Run `git commit -m "<header>" -m "<body>"`.

5. **Push to GitHub**:
   - Run `git push` (or `git push -u origin $(git branch --show-current)` if no upstream is set).
   - If push fails due to non-fast-forward or conflict, stop and report to user.

6. **Report**:
   - List created commit hashes + headers and confirm push target branch.
