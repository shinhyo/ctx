# Release R2 Layout

This page documents the intended R2 staging layout for ctx release candidates.
Normal CI validates the plan only; it does not upload objects or expose public
install instructions.

## R2 staging layout

Release-candidate objects use this prefix shape:

```text
ctx/releases/release-candidate/v<version>/<git-commit>/
```

The current non-publishing CI staging set contains:

- one binary artifact per install platform;
- `install.sh`;
- `install.ps1`;
- `ctx-release-metadata.env`;
- `checksums.sha256`;
- `release-candidate-manifest.json`.

The current staging smoke expects nine objects: four produced platform
artifacts, two installer scripts, metadata, checksums, and the manifest.
Production release staging must include `freebsd-x64` as a fifth platform
artifact, or the release evidence must carry an explicit manager-approved
release exception for the missing target.

## Cutover Rules

No installer endpoint cutover is allowed from normal CI. A manager-run staging
upload must use approved credentials, then verify public HTTPS reads, checksums,
and installer dry-runs before any public install page can change.

Cleanup commands must be recorded with the staging plan so a failed candidate
can be removed without guessing object names.
