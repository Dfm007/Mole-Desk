# Vendored Mole

This directory contains the Mole source tree used to build Mole Desk.

- Source: Mole upstream or the current working tree at the time of vendoring
- Upstream: https://github.com/tw93/Mole
- Synced: 2026-11-05
- Git metadata (`.git`) and `.DS_Store` files are intentionally excluded.
- `build.sh` copies only the runtime subset into the app bundle:
  - `mole`
  - `lib/`
  - `bin/`
  - `LICENSE`
  - `README_CN.md`

To update Mole later, sync the upstream/current checkout into this directory, review the diff, then rebuild the app.
