# fnwsl

## Versioning
- Semver (semver.org). Base version in `VERSION` file; build metadata derived from git.
- In semver's terminology, "build" = git commit for this project.
- Every release MUST bump the `VERSION` file according to semver rules. Patch for fixes, minor for features, major for breaking changes.

## Commits
- Commit upon completion of every task. No exceptions.
- Atomic commits. One logical change per commit. If outstanding changes span separate tasks, split into separate commits so any can be cherry-picked cleanly.
- Terse commit messages. No AI/Claude attribution or references.

## Branching
- All work happens on `dev`. Never commit directly to `main`.
- `main` is updated from `dev` via GitHub Action.
