#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
exec "$script_dir/benchmark-memory.sh" 30
