#!/usr/bin/env bash
set -euo pipefail

pipeline=".buildkite/pipeline.yml"
test -f "${pipeline}"

if command -v ruby >/dev/null 2>&1; then
  ruby -e '
    require "yaml"
    data = YAML.load_file(ARGV.fetch(0))
    abort "pipeline must have steps" unless data.is_a?(Hash) && data["steps"].is_a?(Array)
    steps = data["steps"]
    abort "pipeline should include public smoke, perf gate, and gated artifact matrix" unless steps.length == 8
    smoke = steps.fetch(0)
    abort "pipeline step must be a mapping" unless smoke.is_a?(Hash)
    abort "pipeline public smoke step must be keyed" unless smoke.key?("key")
    abort "missing public-smoke step" unless smoke["key"] == "public-smoke"
    abort "public-smoke must use the release-linux-managed queue" unless smoke.dig("agents", "queue") == "release-linux-managed"
    abort "public-smoke must use the release-linux-control runner" unless smoke.dig("agents", "ctx-runner-class") == "release-linux-control"
    command = smoke["command"].to_s
    abort "public-smoke must run scripts/check.sh --mode=ci" unless command.include?("./scripts/check.sh --mode=ci")
    abort "public-smoke must install missing Ubuntu runner packages before Bazel tests" unless command.include?("apt-get install -y")
    abort "public-smoke must verify runner tools before Bazel tests" unless command.include?("command -v \"$${tool_binary}\"")
    perf = steps.fetch(1)
    abort "missing public-perf step" unless perf.is_a?(Hash) && perf["key"] == "public-perf"
    abort "public-perf must be gated" unless perf["if"].to_s.include?("CTX_PUBLIC_CLI_PERF_GATES")
    abort "public-perf must use release-linux-managed queue" unless perf.dig("agents", "queue") == "release-linux-managed"
    abort "public-perf must run scripts/check.sh --mode=perf" unless perf["command"].to_s.include?("./scripts/check.sh --mode=perf")
    required_keys = %w[
      public-cli-linux-x64
      public-cli-windows-x64
      public-cli-freebsd-x64
      public-cli-macos-arm64
      public-cli-macos-x64
    ]
    actual_keys = steps.filter_map { |step| step["key"] if step.is_a?(Hash) }
    required_keys.each { |key| abort "missing gated artifact step #{key}" unless actual_keys.include?(key) }
    steps.drop(3).each do |step|
      next unless step.is_a?(Hash)
      abort "artifact step #{step["key"]} must be gated" unless step["if"].to_s.include?("CTX_PUBLIC_CLI_ARTIFACT_MATRIX")
    end
  ' "${pipeline}"
else
  top_level_steps="$(
    awk '
      /^steps:[[:space:]]*$/ { in_steps = 1; next }
      /^[^[:space:]]/ { in_steps = 0 }
      in_steps && /^  -[[:space:]]/ { count++ }
      END { print count + 0 }
    ' "${pipeline}"
  )"
  if [[ "${top_level_steps}" != "8" ]]; then
    printf 'pipeline should include public smoke, perf gate, and gated artifact matrix\n' >&2
    exit 1
  fi
fi

for required in \
  'key: "public-smoke"' \
  'queue: "release-linux-managed"' \
  'ctx-runner-class: "release-linux-control"' \
  'ensure_runner_tool zip zip' \
  'ensure_runner_tool rg ripgrep' \
  './scripts/check.sh --mode=ci' \
  'key: "public-perf"' \
  'CTX_PUBLIC_CLI_PERF_GATES' \
  './scripts/check.sh --mode=perf' \
  'CTX_PUBLIC_CLI_ARTIFACT_MATRIX' \
  'scripts/build-public-cli-artifact.sh linux-x64' \
  'scripts/build-public-cli-artifact.sh windows-x64' \
  'scripts/build-public-cli-artifact.sh freebsd-x64' \
  'scripts/build-public-cli-artifact.sh macos-arm64' \
  'scripts/build-public-cli-artifact.sh macos-x64'; do
  if ! grep -F -q "${required}" "${pipeline}"; then
    printf 'pipeline missing required snippet: %s\n' "${required}" >&2
    exit 1
  fi
done

if grep -E -q 'release-artifact|r2-|provider-live|OpenRouter|completion-certificate|freebsd-native-release-proof' "${pipeline}"; then
  printf 'pipeline contains non-smoke release or provider-live wiring\n' >&2
  exit 1
fi

printf 'Buildkite pipeline check ok\n'
