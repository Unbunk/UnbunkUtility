# Contributing / branch workflow

A light, solo-friendly branch model. Long-lived branches:

- **`dev`** — the **default** working branch. Day-to-day changes land here first.
- **`main`** — stable, released code only. Protected: changes land via pull request
  (no direct pushes, no merge commits — squash or rebase), and releases are tagged from here.
- **`ptr`** — parallel branch tracking the WoW PTR (next-patch Interface version).

## Making changes

- **Small / self-contained fixes** — push straight to `dev`, or open a short PR into `dev`.
- **Larger features that need in-game testing** — build them on `dev` (or a feature branch
  merged into `dev`), iterate there, and promote to `main` only once proven.
- After any hotfix that lands directly on `main`, sync it back:
  `git checkout dev && git merge main`.

## Promoting to `main`

When a batch of work on `dev` is finished and tested, open a PR **`dev` → `main`**.
`main`'s ruleset requires the PR and forbids merge commits, so merge with **squash** (or rebase).

## Releasing

Releases are driven by **tags** — the GitHub Action builds `UnbunkUtility.zip`, creates the
GitHub release with auto-generated notes, and uploads to CurseForge / Wago / WoWInterface.
The addon version comes from the tag (`@project-version@`), so there is **no manual version bump**.

- **Stable** — tag from `main`:
  ```
  git checkout main && git pull
  git tag -a v5.2.0 -m "…" && git push origin v5.2.0
  ```
- **Beta / alpha** — tag from `dev` with a prerelease suffix (`-alpha`/`-beta`); it publishes to
  the alpha channels of the addon sites and is marked a prerelease on GitHub:
  ```
  git tag -a v5.2.0-beta1 -m "…" && git push origin v5.2.0-beta1
  ```
