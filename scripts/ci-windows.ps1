param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("platform-smoke", "release-dry-run")]
  [string]$Mode
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Join-PathSafe {
  param([string]$Base, [string]$Child)
  return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($Base, $Child))
}

function Positive-Int {
  param([string]$Value)
  return $Value -match '^[0-9]+$' -and [int]$Value -gt 0
}

function Json-Escape {
  param([string]$Value)
  return ($Value | ConvertTo-Json -Compress)
}

function Run-Step {
  param(
    [string]$Name,
    [scriptblock]$Body
  )

  Write-Host "==> $Name"
  $started = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  try {
    & $Body
    $exitCode = 0
    $status = "passed"
  } catch {
    $exitCode = if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
    $status = "failed"
    throw
  } finally {
    $ended = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $duration = $ended - $started
    Add-Content -Path $script:TimingEvents -Value (@{
      name = $Name
      status = $status
      started_at_unix_s = $started
      ended_at_unix_s = $ended
      duration_s = $duration
      exit_code = $exitCode
      note = $Name
    } | ConvertTo-Json -Compress)
  }
}

function Finish-Timings {
  if (Test-Path $script:TimingEvents) {
    $events = Get-Content -Path $script:TimingEvents -Raw
    if ($events.Trim().Length -eq 0) {
      "[]" | Set-Content -Path $script:TimingFile -Encoding utf8
    } else {
      $json = @()
      foreach ($line in (Get-Content -Path $script:TimingEvents)) {
        if ($line.Trim().Length -gt 0) {
          $json += ($line | ConvertFrom-Json)
        }
      }
      $json | ConvertTo-Json -Depth 8 | Set-Content -Path $script:TimingFile -Encoding utf8
    }
    Remove-Item -Force $script:TimingEvents
    Write-Host "timing artifact: $script:TimingFile"
  }
}

function Require-Command {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "$Name is required but was not found on PATH=$env:PATH"
  }
  return $cmd.Source
}

function Rust-Tools-Available {
  try {
    Require-Command "cargo" | Out-Null
    Require-Command "rustc" | Out-Null
    & cargo fmt --version | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    & cargo clippy --version | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    return $true
  } catch {
    return $false
  }
}

function Invoke-Batch-Environment {
  param(
    [string]$BatchFile,
    [string[]]$BatchArgs
  )

  if (-not (Test-Path $BatchFile)) {
    throw "MSVC environment script not found: $BatchFile"
  }

  $escapedArgs = @()
  foreach ($arg in $BatchArgs) {
    $escapedArgs += '"' + ($arg -replace '"', '\"') + '"'
  }
  $command = 'call "' + $BatchFile + '" ' + ($escapedArgs -join ' ') + ' >nul && set'
  $output = & cmd.exe /d /s /c $command
  if ($LASTEXITCODE -ne 0) {
    throw "MSVC environment script failed: $BatchFile"
  }

  foreach ($line in $output) {
    $separator = $line.IndexOf("=")
    if ($separator -gt 0) {
      $name = $line.Substring(0, $separator)
      $value = $line.Substring($separator + 1)
      Set-Item -Path "Env:$name" -Value $value
    }
  }
}

function Find-MSVC-Environment-Script {
  $candidates = @()
  $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
  $programFiles = [Environment]::GetEnvironmentVariable("ProgramFiles")

  if ($programFilesX86) {
    $vswhere = Join-PathSafe $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
      $installPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1)
      if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($installPath)) {
        $candidates += Join-PathSafe $installPath "Common7\Tools\VsDevCmd.bat"
        $candidates += Join-PathSafe $installPath "VC\Auxiliary\Build\vcvars64.bat"
      }
    }
  }

  foreach ($root in @($programFilesX86, $programFiles)) {
    if ([string]::IsNullOrWhiteSpace($root)) {
      continue
    }
    foreach ($year in @("2022", "2019", "2017")) {
      foreach ($edition in @("BuildTools", "Community", "Professional", "Enterprise")) {
        $base = Join-PathSafe $root "Microsoft Visual Studio\$year\$edition"
        $candidates += Join-PathSafe $base "Common7\Tools\VsDevCmd.bat"
        $candidates += Join-PathSafe $base "VC\Auxiliary\Build\vcvars64.bat"
      }
    }
  }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $null
}

function Ensure-MSVC-Build-Environment {
  if ($env:CTX_EXPECT_HOST_TRIPLE -ne "x86_64-pc-windows-msvc") {
    return
  }

  if (Get-Command "link.exe" -ErrorAction SilentlyContinue) {
    return
  }

  $script = Find-MSVC-Environment-Script
  if ([string]::IsNullOrWhiteSpace($script)) {
    throw "MSVC linker link.exe is required for x86_64-pc-windows-msvc but was not found on PATH, and no Visual Studio Build Tools environment script was found"
  }

  Write-Host "link.exe not found on PATH; importing MSVC environment from $script"
  if ($script.EndsWith("VsDevCmd.bat", [StringComparison]::OrdinalIgnoreCase)) {
    Invoke-Batch-Environment -BatchFile $script -BatchArgs @("-arch=x64", "-host_arch=x64")
  } else {
    Invoke-Batch-Environment -BatchFile $script -BatchArgs @()
  }

  if (-not (Get-Command "link.exe" -ErrorAction SilentlyContinue)) {
    throw "MSVC environment loaded from $script but link.exe is still unavailable on PATH"
  }
}

function Ensure-Rust-Toolchain {
  $env:CARGO_HOME = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-PathSafe $script:RepoRoot "target\tool-cache\cargo" }
  $env:RUSTUP_HOME = if ($env:RUSTUP_HOME) { $env:RUSTUP_HOME } else { Join-PathSafe $script:RepoRoot "target\tool-cache\rustup" }
  New-Item -ItemType Directory -Force -Path $env:CARGO_HOME, $env:RUSTUP_HOME | Out-Null
  $cargoBin = Join-PathSafe $env:CARGO_HOME "bin"
  $env:PATH = "$cargoBin;$env:PATH"

  if (Rust-Tools-Available) {
    return
  }

  $rustup = Get-Command "rustup" -ErrorAction SilentlyContinue
  if (-not $rustup) {
    $installerDir = Join-PathSafe $script:RepoRoot "target\tool-cache\rustup-init"
    New-Item -ItemType Directory -Force -Path $installerDir | Out-Null
    $installer = Join-PathSafe $installerDir "rustup-init.exe"
    if (-not (Test-Path $installer)) {
      $url = "https://win.rustup.rs/x86_64"
      Write-Host "cargo/rustup not found; downloading rustup-init from $url"
      Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $installer
    }
    & $installer -y --profile minimal --default-toolchain stable --component rustfmt --component clippy
    if ($LASTEXITCODE -ne 0) {
      throw "rustup-init failed with exit code $LASTEXITCODE"
    }
  } else {
    Write-Host "Rust toolchain found but rustfmt or clippy is missing; installing components"
    & rustup component add rustfmt clippy
    if ($LASTEXITCODE -ne 0) {
      & rustup toolchain install stable --profile minimal --component rustfmt --component clippy
      if ($LASTEXITCODE -ne 0) {
        throw "rustup component install failed"
      }
    }
  }

  if (-not (Rust-Tools-Available)) {
    throw "Rust toolchain is incomplete after bootstrap; cargo, rustc, rustfmt, and clippy are required"
  }
}

function Host-Triple {
  $lines = & rustc -vV
  if ($LASTEXITCODE -ne 0) {
    throw "rustc -vV failed"
  }
  foreach ($line in $lines) {
    if ($line -match '^host:\s+(.+)$') {
      return $Matches[1]
    }
  }
  throw "rustc -vV did not report a host triple"
}

function Require-Host-Triple {
  param([string]$Expected)
  if ([string]::IsNullOrWhiteSpace($Expected)) {
    return
  }
  Ensure-Rust-Toolchain
  $actual = Host-Triple
  if ($actual -ne $Expected) {
    throw "host triple mismatch: expected $Expected, got $actual"
  }
  if ($actual -match '-msvc$') {
    Ensure-MSVC-Build-Environment
  }
}

function Cargo-Locked-Args {
  if (($env:CTX_CARGO_LOCKED -ne "0") -and (Test-Path (Join-PathSafe $script:RepoRoot "Cargo.lock"))) {
    return @("--locked")
  }
  return @()
}

function Init-Resource-Env {
  $cpu = if (Positive-Int $env:CTX_CPU_COUNT) { [int]$env:CTX_CPU_COUNT } else { [Environment]::ProcessorCount }
  if ($cpu -lt 1) { $cpu = 2 }
  $memoryGb = if (Positive-Int $env:CTX_TOTAL_MEMORY_GB) { [int]$env:CTX_TOTAL_MEMORY_GB } else { 4 }
  $memoryJobs = [Math]::Max([int][Math]::Floor($memoryGb / 3), 1)
  $defaultJobs = [Math]::Max([Math]::Min($cpu, $memoryJobs), 1)

  $env:CTX_CPU_COUNT = "$cpu"
  $env:CTX_TOTAL_MEMORY_GB = "$memoryGb"
  $env:CARGO_BUILD_JOBS = if ($env:CARGO_BUILD_JOBS) { $env:CARGO_BUILD_JOBS } elseif ($env:CTX_CARGO_JOBS) { $env:CTX_CARGO_JOBS } else { "$defaultJobs" }
  $env:RUST_TEST_THREADS = if ($env:RUST_TEST_THREADS) { $env:RUST_TEST_THREADS } elseif ($env:CTX_TEST_THREADS) { $env:CTX_TEST_THREADS } else { $env:CARGO_BUILD_JOBS }
  $env:CARGO_TERM_COLOR = if ($env:CARGO_TERM_COLOR) { $env:CARGO_TERM_COLOR } else { "always" }
  $env:TMPDIR = if ($env:TMPDIR) { $env:TMPDIR } else { Join-PathSafe $script:RepoRoot "target\tmp" }
  $env:TMP = $env:TMPDIR
  $env:TEMP = $env:TMPDIR
  New-Item -ItemType Directory -Force -Path $env:TMPDIR | Out-Null

  if ($env:CTX_USE_SCCACHE -ne "1" -and $env:RUSTC_WRAPPER -like "*sccache*") {
    Remove-Item Env:RUSTC_WRAPPER
  }
}

function Print-Resource-Env {
  Write-Host "resource limits: cpu=$env:CTX_CPU_COUNT memory_gb=$env:CTX_TOTAL_MEMORY_GB cargo_jobs=$env:CARGO_BUILD_JOBS test_threads=$env:RUST_TEST_THREADS tmpdir=$env:TMPDIR"
}

function Run-Cargo {
  param([string[]]$CargoArgs)
  & cargo @CargoArgs
  if ($LASTEXITCODE -ne 0) {
    throw "cargo $($CargoArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Run-Ctx {
  param([string]$Binary, [string[]]$CtxArgs)
  & $Binary @CtxArgs
  if ($LASTEXITCODE -ne 0) {
    throw "$Binary $($CtxArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Run-Platform-Smoke {
  Require-Host-Triple $env:CTX_EXPECT_HOST_TRIPLE
  Ensure-Rust-Toolchain
  Ensure-MSVC-Build-Environment
  $locked = Cargo-Locked-Args
  Run-Cargo -CargoArgs (@("build", "-p", "ctx", "--bin", "ctx") + $locked)

  $bin = Join-PathSafe $script:RepoRoot "target\debug\ctx.exe"
  if (-not (Test-Path $bin)) {
    throw "expected smoke binary missing: $bin"
  }

  $dataRoot = Join-PathSafe $env:TMPDIR ("ctx-work-record-smoke-" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
  $env:CTX_DATA_ROOT = $dataRoot

  Run-Ctx $bin @("setup")
  $recordOutput = & $bin record --title "platform smoke" --body "platform smoke body" --tag "smoke" --json
  if ($LASTEXITCODE -ne 0) {
    throw "platform smoke failed to create a record"
  }
  try {
    $recordJson = $recordOutput | ConvertFrom-Json
    if (-not $recordJson.id) {
      throw "missing id"
    }
  } catch {
    throw "platform smoke failed to parse record id from: $recordOutput"
  }
  Run-Ctx $bin @("search", "platform", "--json")
  Run-Ctx $bin @("context", "platform", "--json")
  Run-Ctx $bin @("dashboard", "export", "--output", (Join-PathSafe $dataRoot "dashboard"))
  Run-Ctx $bin @("validate")
}

function Sha256-File {
  param([string]$Path)
  return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Cargo-Version {
  $cargoToml = Join-PathSafe $script:RepoRoot "crates\ctx-cli\Cargo.toml"
  foreach ($line in Get-Content $cargoToml) {
    if ($line -match '^version\s*=\s*"([^"]+)"') {
      return $Matches[1]
    }
  }
  throw "could not read ctx-cli version from $cargoToml"
}

function Run-Release-Dry-Run {
  Require-Host-Triple $env:CTX_EXPECT_HOST_TRIPLE
  Ensure-Rust-Toolchain
  Ensure-MSVC-Build-Environment
  $locked = Cargo-Locked-Args
  Run-Cargo -CargoArgs (@("build", "--workspace", "--release", "--bins") + $locked)

  $version = Cargo-Version
  $hostTriple = Host-Triple
  $targetTriple = if ($env:CTX_RELEASE_TARGET_TRIPLE) { $env:CTX_RELEASE_TARGET_TRIPLE } else { $hostTriple }
  $platform = if ($env:CTX_RELEASE_PLATFORM) { $env:CTX_RELEASE_PLATFORM } else { "host-$hostTriple" }
  $commit = (& git rev-parse HEAD).Trim()
  $branch = (& git branch --show-current).Trim()
  $sourceBin = Join-PathSafe $script:RepoRoot "target\release\ctx.exe"
  if (-not (Test-Path $sourceBin)) {
    throw "expected host binary missing: $sourceBin"
  }

  $artifact = "ctx-$version-$targetTriple.exe"
  $artifactRel = Join-PathSafe $script:ArtifactDir $artifact
  Copy-Item -Force $sourceBin $artifactRel
  $checksum = Sha256-File $artifactRel
  $bytes = (Get-Item $artifactRel).Length
  $generatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

  "$checksum  $artifact" | Set-Content -Path (Join-PathSafe $script:ArtifactDir "checksums.sha256") -Encoding ascii
  @{
    schema_version = 1
    dry_run = $true
    upload = $false
    package = "ctx"
    version = $version
    platform = $platform
    target_triple = $targetTriple
    host_triple = $hostTriple
    expected_host_triple = $env:CTX_EXPECT_HOST_TRIPLE
    git_commit = $commit
    git_branch = $branch
    generated_at_unix_s = $generatedAt
    artifacts = @(@{
      path = $artifactRel
      sha256 = $checksum
      bytes = $bytes
    })
  } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-PathSafe $script:ArtifactDir "manifest.json") -Encoding utf8

  Write-Host "release dry-run manifest: $(Join-PathSafe $script:ArtifactDir "manifest.json")"
  Write-Host "release dry-run checksums: $(Join-PathSafe $script:ArtifactDir "checksums.sha256")"
}

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:RepoRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($script:ScriptDir, ".."))
Set-Location $script:RepoRoot

Init-Resource-Env
$script:ArtifactDir = if ($env:CTX_ARTIFACT_DIR) { $env:CTX_ARTIFACT_DIR } else { Join-PathSafe $script:RepoRoot "target\ctx-artifacts\windows-ci" }
New-Item -ItemType Directory -Force -Path $script:ArtifactDir | Out-Null
$script:TimingFile = Join-PathSafe $script:ArtifactDir "timings.json"
$script:TimingEvents = "$($script:TimingFile).events"
Set-Content -Path $script:TimingEvents -Value "" -Encoding utf8

try {
  Print-Resource-Env
  if ($Mode -eq "platform-smoke") {
    Run-Step "platform-smoke" { Run-Platform-Smoke }
  } elseif ($Mode -eq "release-dry-run") {
    Run-Step "release-dry-run" { Run-Release-Dry-Run }
  } else {
    throw "unknown Windows CI mode: $Mode"
  }
} finally {
  Finish-Timings
}
