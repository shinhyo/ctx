# FreeBSD Release Worker

FreeBSD is a first-class release target for ctx. It is not out of scope and is
not optional for a production release.

## Required Worker

- Buildkite queue label: `freebsd-x64`
- Target triple: `x86_64-unknown-freebsd`
- Required tools: Bash, Git, Rust stable, Cargo, and `sha256sum` or `shasum`
- Expected lane shape: build the ctx CLI on the native worker, write the release
  dry-run manifest, and export the artifact plus checksum evidence

## Release Requirement

A production release requires `freebsd-x64` proof alongside `linux-x64`,
`macos-arm64`, `macos-x64`, and `windows-x64`. If the native worker is still
absent, the release evidence must include an explicit manager-approved release
exception that names `freebsd-x64`, explains the temporary risk, and keeps the
certificate from implying full platform proof.

## Current Status

The release certificate must include a FreeBSD blocker artifact while this
worker is absent. The blocker is temporary evidence of missing required proof,
not a permanent waiver. It does not make FreeBSD optional.

The blocker does not publish, upload, sign, or move any release channel.
