# Upstream: UxPlay engine

`uxplay/` is a byte-for-byte copy of the `lib/` directory of UxPlay.

- Repository: https://github.com/FDH2/UxPlay
- Tag: v1.73.7
- Commit: df67c212a433cf6dda3676dd40c097900d24e645
- Copied: 2026-10-17
- License: GPL-3.0 (UxPlay); individual files carry their own headers
  (LGPL-2.1 for the RPiPlay/shairplay-derived files, MIT for llhttp, see
  `uxplay/playfair/LICENSE.md` for playfair).

Applied on top of v1.73.7: the patches listed in `/Patches/README.md` (each a
`git diff` against the upstream file). Do not edit files under `uxplay/` without
adding a patch file and a note there, so the engine can be updated from upstream.

To update: replace `uxplay/` with a newer `lib/`, update this file, rebuild,
run `swift test`.
