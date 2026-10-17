# Patches to the vendored UxPlay engine

`Sources/UxPlayLib/uxplay/` is UxPlay v1.73.7 **plus the patches below, already
applied**. Each patch is a `git diff` against the unmodified upstream file.
When updating UxPlay, check whether upstream has absorbed each patch; re-apply
the rest with `git apply Patches/<file>`.

| Patch | Why | Upstream status |
|---|---|---|
| `0001-pair-setup-pin-accept-sha1-proof.patch` | "Ask for a code" (PIN pairing): UxPlay's SRP uses SHA-1 (`SRP_SHA1`), so iOS 26 sends a 20-byte proof, but v1.73.7 rejected anything but 64 bytes (`client_proof_len 20 invalid`) and the iPhone asked for the code again forever. Accept 1–64 bytes and copy only the bytes sent. Test: `PinPairingTests.twentyByteProofReachesVerification`. | Fixed upstream after v1.73.7 (commit `d29dfab` drops the check, but copies 64 bytes regardless). Drop this patch when updating past that commit. |
