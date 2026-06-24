#!/usr/bin/env bash
set -euo pipefail

pipeline=".buildkite/pipeline.yml"
test -f "${pipeline}"

if command -v ruby >/dev/null 2>&1; then
  ruby -e '
    require "yaml"
    data = YAML.load_file(ARGV.fetch(0))
    abort "pipeline must have steps" unless data.is_a?(Hash) && data["steps"].is_a?(Array)
    keys = data["steps"].map { |step| step["key"] }.compact
    abort "missing search-mvp step" unless keys.include?("search-mvp")
    search = data["steps"].find { |step| step["key"] == "search-mvp" }
    abort "search-mvp must run scripts/check.sh --mode=ci" unless search["command"] == "./scripts/check.sh --mode=ci"
  ' "${pipeline}"
fi

if ! grep -F -q './scripts/check.sh --mode=ci' "${pipeline}"; then
  printf 'pipeline must run ./scripts/check.sh --mode=ci\n' >&2
  exit 1
fi

if command -v rg >/dev/null 2>&1; then
  if rg -n -i 'dashboard|shim|publish|pull request|hosted|ADE|ctx evidence|ctx pr' "${pipeline}"; then
    printf 'pipeline contains removed search-MVP surfaces\n' >&2
    exit 1
  fi
fi

printf 'search MVP pipeline ok\n'
