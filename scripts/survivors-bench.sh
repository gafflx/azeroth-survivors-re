#!/usr/bin/env bash
# The survivors frame-time benchmark: the same seeded auto run, launched N times with pinned
# settings, then summarised from the per-frame log (`WOW_SURVIVORS_FRAMES`, survivors/auto.rs)
# and the FPS journal. See docs/performance/M2_BASELINE.md for what the numbers mean.
#
#   scripts/survivors-bench.sh run <label> <late|normal> <reps> [wall_secs]
#   scripts/survivors-bench.sh summary <label>
#   scripts/survivors-bench.sh bins <label>...      (compare labels at matched entity load)
#   scripts/survivors-bench.sh trace <label> <late|normal> <close_after_secs>   (Windows)
#
# `trace` needs the trace_chrome build:
#   CARGO_TARGET_DIR=target/trace cargo build --profile play -p warcraft-survivors \
#       --features benilla-app/trace_chrome
# It runs once with the same settings, keeps the scheduler's bookkeeping spans out of the trace
# (RUST_LOG), asks the window to close after <close_after_secs> (taskkill without /F, so the
# trace writer can finish) and moves trace-*.json into the run folder. Traces are many GB.
#
# Outputs go to target/survivors-bench/<label>/run-N/ (git-ignored): frames.csv, journal.csv,
# log.txt. Needs the play build (`cargo build --profile play -p warcraft-survivors`) and
# wow-data/Data. Leave the machine idle while it runs: other load moves the timings.
#
# Pinned for every run:
#   - class Mage, map Elwynn Forest, seed 1234;
#   - vsync off, a 1600x900 window in the foreground (`WOW_BG=0`: any `WOW_FPS_*` variable
#     otherwise turns the run into a small unfocused background window);
#   - a fresh BENILLA_HOME per run, so no saved settings or pick carry over;
#   - no screenshots.
# Override the seed or class with SEED= and CLASS=. FIXED_DT=<ms> steps the simulation by exactly
# that much every frame (`WOW_FIXED_DT=<ms>,0`), so the same seed plays the same run; frames.csv's
# wall_ms is still the real frame cost, but the journal's mean_ms/p95_ms then show the fixed step.
# NOJOURNAL=1 leaves the FPS journal off: it has a per-frame cost of its own (its GPU-timing fold
# runs on the main thread every frame), so frame-time comparisons run without it; the CPU, main
# and GPU columns of the summary are then empty.
set -uo pipefail
cd "$(dirname "$0")/.."

ROOT="target/survivors-bench"
# EXE= runs another build, e.g. the trace_chrome one in target/trace (its numbers include the
# tracing overhead, so never compare them with the plain build's).
EXE="${EXE:-target/play/warcraft-survivors.exe}"
[ -x "$EXE" ] || EXE="target/play/warcraft-survivors"
SEED="${SEED:-1234}"
CLASS="${CLASS:-mage}"
# Frames this long after the run starts are skipped: the first spawn wave and warm-up.
SKIP_SECS="${SKIP_SECS:-10}"

run() {
    local label=$1 mode=$2 reps=$3 secs=${4:-300}
    local auto=$CLASS
    [ "$mode" = late ] && auto="$CLASS:late"
    for n in $(seq 1 "$reps"); do
        local dir="$ROOT/$label/run-$n"
        rm -rf "$dir"
        mkdir -p "$dir/home"
        local journal=(WOW_FPS_JOURNAL="$PWD/$dir/journal.csv")
        [ -n "${NOJOURNAL:-}" ] && journal=()
        echo "[$label run $n/$reps] $auto, seed $SEED, ${secs}s${FIXED_DT:+, fixed dt ${FIXED_DT} ms}${NOJOURNAL:+, no journal}"
        ${FIXED_DT:+env WOW_FIXED_DT="$FIXED_DT,0"} \
            env WOW_DATA="$PWD/wow-data/Data" \
            BENILLA_HOME="$PWD/$dir/home" \
            WOW_SURVIVORS_AUTO="$auto" \
            WOW_SURVIVORS_MAP=elwynn \
            WOW_SURVIVORS_SEED="$SEED" \
            WOW_BG=0 \
            WOW_WIN=1600x900 \
            WOW_NOVSYNC=1 \
            "${journal[@]}" \
            WOW_SURVIVORS_FRAMES="$PWD/$dir/frames.csv" \
            timeout "$secs" "$EXE" > "$dir/log.txt" 2>&1
        echo "  exit $? (124 = stopped by the time limit, as planned)"
    done
}

# Percentiles of a sorted column of numbers on stdin: prints n mean p50 p95 p99 max.
pcts() {
    sort -g | awk '{v[NR]=$1; s+=$1} END {
        if (NR == 0) { print "0 - - - - -"; exit }
        i50 = int(NR*0.50); if (i50 < 1) i50 = 1
        i95 = int(NR*0.95); if (i95 < 1) i95 = 1
        i99 = int(NR*0.99); if (i99 < 1) i99 = 1
        printf "%d %.2f %.2f %.2f %.2f %.2f\n", NR, s/NR, v[i50], v[i95], v[i99], v[NR] }'
}

summary() {
    local label=$1
    printf "%-6s %-24s %6s %7s %7s %7s %7s %8s %5s %5s %6s %6s %6s %6s %5s %s\n" \
        run class frames mean p50 p95 p99 max ">33" ">100" alive maxal cpu main gpu notes
    for dir in "$ROOT/$label"/run-*; do
        [ -f "$dir/frames.csv" ] || continue
        local L begins
        L=$(sed 's/\x1b\[[0-9;]*m//g' "$dir/log.txt")
        begins=$(grep -o "run begins as [A-Za-z]* at [A-Za-z ]*, seed [0-9]*" <<<"$L" | head -1)
        # The measured window: Playing frames, not under the loading screen, from SKIP_SECS of
        # run clock after the first such frame, until the first GameOver.
        local win
        win=$(awk -F, -v skip="$SKIP_SECS" 'NR > 1 {
            if ($3 == "GameOver") over = 1
            if (over || $3 != "Playing" || $4 != 0) next
            if (start == "") start = $6
            if ($6 - start < skip) next
            print }' "$dir/frames.csv")
        local stats t0 t1 alive maxal over
        stats=$(cut -d, -f2 <<<"$win" | grep . | pcts)
        t0=$(head -1 <<<"$win" | cut -d, -f1)
        t1=$(tail -1 <<<"$win" | cut -d, -f1)
        alive=$(awk -F, '{s+=$5; n++} END {if (n) printf "%.0f", s/n}' <<<"$win")
        maxal=$(awk -F, '$5 > m {m=$5} END {print m+0}' <<<"$win")
        local o33 o100
        o33=$(awk -F, '$2 > 33.3 {n++} END {print n+0}' <<<"$win")
        o100=$(awk -F, '$2 > 100 {n++} END {print n+0}' <<<"$win")
        over=$(grep -c ",GameOver," "$dir/frames.csv")
        # The journal's per-second CPU, main-thread and GPU ms over the same real-time window.
        local jr
        jr=$(awk -F, -v a="$t0" -v b="$t1" 'NR > 2 && $1 >= a && $1 <= b {
                c += $9; m += $26; if ($27 != "") { g += $27; gn++ }; n++ }
            END { if (n) printf "%.2f %.2f %s", c/n, m/n, (gn ? sprintf("%.2f", g/gn) : "-")
                  else print "- - -" }' "$dir/journal.csv" 2>/dev/null)
        [ -n "$jr" ] || jr="- - -"  # no journal (NOJOURNAL=1)
        local notes="window ${t0:-?}-${t1:-?}s real"
        [ "$over" -gt 0 ] && notes="$notes; GameOver reached"
        set -- $stats
        local n=$1 mean=$2 p50=$3 p95=$4 p99=$5 max=$6
        set -- $jr
        printf "%-6s %-24s %6s %7s %7s %7s %7s %8s %5s %5s %6s %6s %6s %6s %5s %s\n" \
            "${dir##*-}" "${begins#run begins as }" "$n" "$mean" "$p50" "$p95" "$p99" "$max" \
            "$o33" "$o100" "$alive" "$maxal" "$1" "$2" "$3" "$notes"
    done
    echo
    echo "Hitch warnings (>250 ms frames, from the engine's own check), whole run including loading:"
    for dir in "$ROOT/$label"/run-*; do
        local all play
        all=$(grep -c "frame hitch" "$dir/log.txt")
        play=$(awk -F, 'NR > 1 && $3 == "Playing" && $4 == 0 && $2 > 250 {n++} END {print n+0}' "$dir/frames.csv")
        echo "  run ${dir##*-}: $all in the log; $play of them during uncovered Playing frames"
    done
}

# Load-matched comparison: the measured Playing frames of every run of each label, grouped by the
# entity count of the journal second they fall in (5k-entity bins), so runs that drift into a
# different load (e.g. many more XP gems) are compared with baseline frames at the same load.
# Prints per (label, bin): frame-time p50/p95/p99 and the journal's main-thread ms p50.
# BY=gems groups by the frame's own gem count instead (50-gem bins; frames.csv column 9, which
# runs recorded before the column existed lack), for comparisons where the entity count itself
# changes, such as gems with and without their model.
bins() {
    local label by=${BY:-entities}
    for label in "$@"; do
        local d
        for d in "$ROOT/$label"/run-*; do
            [ -f "$d/journal.csv" ] || continue
            awk -F, -v set="$label" -v by="$by" '
                FNR == NR { if (FNR > 2) { jt[++nj] = $1; je[nj] = $8; jm[nj] = $26 } next }
                FNR == 1 { j = 1; next }
                $3 == "GameOver" { over = 1 }
                over || $3 != "Playing" || $4 != 0 { next }
                { if (s == "") s = $6; if ($6 - s < skip) next
                  while (j < nj && jt[j] < $1) j++
                  if (by == "gems" && $9 == "") next
                  bin = (by == "gems" ? int($9 / 50) * 50 : int(je[j] / 5000) * 5)
                  print set, bin, $2, (j != last ? jm[j] : "-"); last = j }' \
                skip="$SKIP_SECS" "$d/journal.csv" "$d/frames.csv"
        done
    done | sort -k1,1 -k2,2n -k3,3g | awk -v by="$by" '
        { key = $1 " " $2; n[key]++; v[key, n[key]] = $3
          if ($4 != "-" && $4 != "") { nm[key]++; m[key, nm[key]] = $4 }
          if (!(key in seen)) { seen[key] = 1; order[++k] = key } }
        END {
          printf "%-22s %-9s %7s %7s %7s %7s %9s\n", "label", by, "frames", "p50", "p95", "p99", "main p50"
          for (i = 1; i <= k; i++) {
            key = order[i]; split(key, p, " "); c = n[key]
            # The main-thread column: one journal value per second, sorted for the median.
            cm = nm[key]; delete s2; for (x = 1; x <= cm; x++) s2[x] = m[key, x]; asort(s2)
            range = (by == "gems" ? sprintf("%3d-%-3d", p[2], p[2] + 50) : sprintf("%3d-%-3dk", p[2], p[2] + 5))
            printf "%-22s %-9s %7d %7.2f %7.2f %7.2f %9s\n", p[1], range, c,
                v[key, int(c * 0.50) + 1], v[key, int(c * 0.95) + 1], v[key, int(c * 0.99) + 1],
                (cm ? sprintf("%.2f", s2[int((cm + 1) / 2)]) : "-") } }'
}

trace() {
    local label=$1 mode=$2 close_after=$3
    local auto=$CLASS exe=${EXE_TRACE:-target/trace/play/warcraft-survivors.exe}
    [ "$mode" = late ] && auto="$CLASS:late"
    local dir="$ROOT/$label/run-1"
    rm -rf "$dir"
    mkdir -p "$dir/home"
    rm -f trace-*.json
    echo "[$label trace] $auto, seed $SEED, close after ${close_after}s${FIXED_DT:+, fixed dt ${FIXED_DT} ms}"
    ${FIXED_DT:+env WOW_FIXED_DT="$FIXED_DT,0"} \
        env RUST_LOG="info,wgpu=error,naga=warn,bevy_ecs::schedule::executor=off,bevy_ecs::query=off,bevy_render::batching=off,bevy_render::renderer::graph_runner=off" \
        WOW_DATA="$PWD/wow-data/Data" \
        BENILLA_HOME="$PWD/$dir/home" \
        WOW_SURVIVORS_AUTO="$auto" \
        WOW_SURVIVORS_MAP=elwynn \
        WOW_SURVIVORS_SEED="$SEED" \
        WOW_BG=0 \
        WOW_WIN=1600x900 \
        WOW_NOVSYNC=1 \
        WOW_FPS_JOURNAL="$PWD/$dir/journal.csv" \
        WOW_SURVIVORS_FRAMES="$PWD/$dir/frames.csv" \
        "$exe" > "$dir/log.txt" 2>&1 &
    local pid=$!
    local image
    image=$(basename "$exe")
    sleep "$close_after"
    # By image name: `$!` is the `env` wrapper's pid, not the game's.
    echo "  asking $image to close"
    taskkill //IM "$image" > /dev/null 2>&1
    # The writer drains its queue before the process exits; give it up to 15 minutes.
    local waited=0
    while kill -0 "$pid" 2>/dev/null && [ $waited -lt 900 ]; do
        sleep 5
        waited=$((waited + 5))
    done
    if kill -0 "$pid" 2>/dev/null; then
        echo "  still running after 15 min; forcing it"
        taskkill //F //IM "$image" > /dev/null 2>&1
    fi
    mv trace-*.json "$dir/" 2>/dev/null
    ls -la "$dir"/trace-*.json 2>/dev/null
}

case "${1:-}" in
    run) shift; run "$@" ;;
    trace) shift; trace "$@" ;;
    bins) shift; bins "$@" ;;
    summary) shift; summary "$@" ;;
    *) sed -n '2,9p' "$0"; exit 2 ;;
esac
