#!/bin/bash
# Syncs marketplace plugin sources to the local cache.
# Run after pulling changes or editing plugin files.

MARKETPLACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="$HOME/.claude/plugins/cache/softsolutions-plugins"

for plugin_dir in "$MARKETPLACE_DIR"/plugins/*/; do
  plugin_name=$(basename "$plugin_dir")
  version=$(jq -r '.version // "1.0.0"' "$plugin_dir/.claude-plugin/plugin.json")
  target="$CACHE_DIR/$plugin_name/$version"
  mkdir -p "$target"
  rsync -a --delete --exclude='.sessions' "$plugin_dir" "$target/"
  echo "Synced $plugin_name@$version"
done
