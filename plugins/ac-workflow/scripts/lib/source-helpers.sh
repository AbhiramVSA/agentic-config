#!/usr/bin/env bash
# Shared bootstrap helpers for ac-workflow plugin scripts
# Provides CLAUDE_PLUGIN_ROOT resolution and config-loader sourcing
#
# Usage (from scripts/ directory):
#   # shellcheck source=lib/source-helpers.sh
#   source "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib/source-helpers.sh"
#
# Note on ${BASH_SOURCE[0]:-$0}: BASH_SOURCE is a bash-only array. Under zsh
# it is unset, so the expansion falls back to $0, which zsh populates with the
# sourced file path by default (FUNCTION_ARGZERO option, on by default). This
# pattern keeps the scripts working under both bash and zsh without requiring
# zsh-only syntax such as ${(%):-%x} that would break bash parsing.
#
# Caveat: the one zsh configuration this does NOT cover is a user who has
# explicitly set `setopt NO_FUNCTION_ARGZERO` (or `setopt POSIX_ARGZERO`) in
# their zshrc. Under that option, $0 inside a sourced file becomes "zsh"
# rather than the file path, and sibling-path resolution degrades to the
# original bug. That is a non-default opt-in and not covered here; users who
# hit it should restore the default or export CLAUDE_PLUGIN_ROOT explicitly.

# Capture this sourced helper's path at top level. In zsh, $0 is the sourced
# file here, but becomes the function name inside _source_config_loader.
_source_helpers_path="${BASH_SOURCE[0]:-$0}"
_source_helpers_dir="$(cd "$(dirname "$_source_helpers_path")" && pwd)"
unset _source_helpers_path

# Bootstrap CLAUDE_PLUGIN_ROOT if not set
# Resolves from this file's location: scripts/lib/ -> ../../ = plugin root
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  CLAUDE_PLUGIN_ROOT="$(cd "$_source_helpers_dir/../.." && pwd)"
fi

# Source shared config loader
# Tries CLAUDE_PLUGIN_ROOT first, then falls back to locating via the caller's
# script path (BASH_SOURCE entries under bash, captured helper path under zsh).
_source_config_loader() {
  local config_loader="${CLAUDE_PLUGIN_ROOT}/scripts/lib/config-loader.sh"

  # Fallback: resolve relative to caller script path(s).
  # Under bash: iterate every frame in BASH_SOURCE so we can walk up from the
  # sourced file (e.g. spec-resolver.sh in scripts/) to locate config-loader.sh.
  # Under zsh: BASH_SOURCE is unset, so use the helper directory captured while
  # source-helpers.sh was being sourced. $0 is not used here because zsh's
  # default FUNCTION_ARGZERO makes it the function name inside this function.
  # Checks both lib/config-loader.sh (for callers in scripts/) and
  # config-loader.sh (for this file in scripts/lib/)
  if [[ ! -f "$config_loader" ]]; then
    local script_dir candidate resolved_plugin_root
    for candidate in "${BASH_SOURCE[@]:-}" "$_source_helpers_dir"; do
      [[ -n "$candidate" ]] || continue
      if [[ -d "$candidate" ]]; then
        script_dir="$candidate"
      else
        script_dir="$(cd "$(dirname "$candidate")" && pwd 2>/dev/null)" || continue
      fi
      if [[ -f "$script_dir/lib/config-loader.sh" ]]; then
        config_loader="$script_dir/lib/config-loader.sh"
        resolved_plugin_root="$(cd "$script_dir/.." && pwd)"
        echo "WARNING: CLAUDE_PLUGIN_ROOT fallback activated; resolved to $resolved_plugin_root" >&2
        CLAUDE_PLUGIN_ROOT="$resolved_plugin_root"
        break
      elif [[ -f "$script_dir/config-loader.sh" ]]; then
        config_loader="$script_dir/config-loader.sh"
        resolved_plugin_root="$(cd "$script_dir/../.." && pwd)"
        echo "WARNING: CLAUDE_PLUGIN_ROOT fallback activated; resolved to $resolved_plugin_root" >&2
        CLAUDE_PLUGIN_ROOT="$resolved_plugin_root"
        break
      fi
    done
  fi

  if [[ ! -f "$config_loader" ]]; then
    echo "ERROR: config-loader.sh not found" >&2
    echo "  Searched: ${CLAUDE_PLUGIN_ROOT}/scripts/lib/config-loader.sh" >&2
    echo "  Set CLAUDE_PLUGIN_ROOT to the ac-workflow plugin directory" >&2
    return 1
  fi

  if declare -f load_agentic_config >/dev/null 2>&1 && \
     declare -f get_project_root >/dev/null 2>&1; then
    return 0
  fi

  # shellcheck source=config-loader.sh
  source "$config_loader" || return 1

  if declare -f load_agentic_config >/dev/null 2>&1 && \
     declare -f get_project_root >/dev/null 2>&1; then
    return 0
  fi

  echo "ERROR: config-loader.sh missing required functions" >&2
  echo "  Expected: load_agentic_config and get_project_root" >&2
  return 1
}
