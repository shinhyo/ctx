# Release Supply Chain

ctx release evidence is split into classes so CI output is not mistaken for a
public release approval.

## Evidence Classes

Contract fixture evidence is generated for script self-tests. It uses fake
artifacts with real checksums and must set `self_test_fixture=true` plus
`evidence_class=contract_fixture`. It can prove that the certificate verifier
works, but it cannot approve a release.

Host artifact dry-run evidence is produced on one runner from a local release
build. It proves that the runner can build a ctx binary, write a manifest, and
record checksums. It is not multi-platform release proof.

Multi-platform artifact proof requires separate evidence for each install
target. A production release requires proof for `linux-x64`, `macos-arm64`,
`macos-x64`, `windows-x64`, and `freebsd-x64`, or an explicit
manager-approved release exception that names the missing target and reason.

FreeBSD is a first-class release target, not an optional stretch target. The
current public CI contract may emit a `freebsd-x64` blocker while no native
Buildkite queue exists, but that blocker keeps the release non-publishing and
not launch-ready. The intended proof path is a native `freebsd-x64` lane that
builds ctx, writes the dry-run manifest, and exports artifact plus checksum
evidence for `x86_64-unknown-freebsd`.

R2 staging evidence proves only that the object layout and upload plan are
well-formed. Normal CI does not upload objects, move channels, or expose public
install instructions.

## Release Blockers

Signing, notarization, SBOM, and provenance are external blockers. Public
release approval requires configured credentials, approved policy, generated
artifacts, and verification instructions for each item.

The completion certificate remains non-publishing until all blockers are
replaced by explicit pass evidence or by a manager-approved release exception
that is recorded in the release evidence. A contract fixture certificate must
never be used as approval for public artifacts.
