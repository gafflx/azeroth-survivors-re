#!/usr/bin/env bash
# Strict clippy for survivors mode: any clippy or rustc warning in crates/benilla-app/src/survivors/
# or crates/warcraft-survivors/ fails the run.
#
# Why not `cargo clippy -p benilla-app -- -D warnings`: clippy lints every workspace crate in the
# build graph, and upstream's benilla-world carries a lint that stops the run before benilla-app
# is reached (`--no-deps` fixes that); and benilla-app itself has warnings outside survivors
# (webbridge/, realmlist.rs) that are not this mode's to fix. So the crates are linted without
# their dependencies and the findings are filtered to the survivors paths; everything else stays
# a warning, as it is today.
#
# Extra arguments go to cargo, e.g. `scripts/survivors-lint.sh --no-default-features`.
set -uo pipefail
cd "$(dirname "$0")/.."

out=$(cargo clippy -p benilla-app -p warcraft-survivors --no-deps --all-targets \
    --message-format=short "$@" 2>&1)
status=$?
if [ $status -ne 0 ]; then
    printf '%s\n' "$out"
    echo "survivors-lint: cargo clippy failed (exit $status)"
    exit $status
fi

hits=$(printf '%s\n' "$out" |
    grep -E '^crates[/\\](benilla-app[/\\]src[/\\]survivors|warcraft-survivors)[/\\].*: (warning|error)' ||
    true)
if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    echo "survivors-lint: $(printf '%s\n' "$hits" | wc -l) finding(s) in survivors code"
    exit 1
fi
echo "survivors-lint: clean"
