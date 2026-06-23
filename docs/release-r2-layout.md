# Release R2 Layout

Status: non-publishing release-candidate infrastructure for `ctx` `0.1.0`.
Do not repoint `ctx.rs/install`, publish `ctx.rs`, or promote an R2 object path
to a production URL without explicit approval.

Release dry-run lanes produce platform artifacts under Buildkite. The release
candidate metadata lane downloads those artifacts, verifies each SHA-256 digest,
and writes a staging upload plan.

Default staging identifiers:

- bucket: `ctx-release-artifacts`
- prefix template: `ctx/records/release-candidate/v0.1.0/<git-commit>`
- public base URL template:
  `https://example.invalid/ctx/records/release-candidate/v0.1.0/<git-commit>`

The public base URL is intentionally invalid by default. A manager must set
`CTX_RELEASE_PUBLIC_BASE_URL` to an approved HTTPS R2/custom-domain staging URL
before running an installer smoke against staged objects.

## Object Layout

```text
r2://$CTX_RELEASE_R2_BUCKET/$CTX_RELEASE_R2_PREFIX/
  ctx-0.1.0-x86_64-unknown-linux-gnu
  ctx-0.1.0-aarch64-apple-darwin
  ctx-0.1.0-x86_64-apple-darwin
  ctx-0.1.0-x86_64-pc-windows-gnu.exe
  install.sh
  install.ps1
  ctx-release-metadata.env
  checksums.sha256
  release-candidate-manifest.json
```

FreeBSD is not included in the install metadata until a native
`x86_64-unknown-freebsd` artifact exists. The release certificate records the
FreeBSD blocker artifact instead.

## Staging Command

The metadata lane writes exact staging and cleanup commands:

```bash
CTX_ARTIFACT_DIR=artifacts/buildkite/release-candidate \
  ./scripts/release-candidate-metadata.sh \
  artifacts/buildkite/release-dry-run \
  artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json

bash artifacts/buildkite/release-candidate/r2-upload-commands.sh
```

The generated upload script uses `wrangler r2 object put`. It does not upload
install redirect files, does not touch DNS, and does not modify `ctx.rs/install`.

## Installer Smoke

After staging, use the approved HTTPS base URL from
`CTX_RELEASE_PUBLIC_BASE_URL`:

```bash
bash scripts/install.sh \
  --metadata "$CTX_RELEASE_PUBLIC_BASE_URL/ctx-release-metadata.env" \
  --platform linux-x64 \
  --bin-dir "$(mktemp -d)" \
  --dry-run
```

Windows smoke uses the same metadata:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 `
  -Metadata "$env:CTX_RELEASE_PUBLIC_BASE_URL/ctx-release-metadata.env" `
  -Platform windows-x64 `
  -BinDir "$env:TEMP\ctx-install-smoke" `
  -DryRun
```

Run a live install smoke only after dry-runs pass and the target directory is a
throwaway location.
