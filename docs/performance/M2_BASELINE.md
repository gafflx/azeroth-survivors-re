# M2 baseline: survivors frame time

Captured 2026-10-25, before any M2 optimization.

**No gameplay or engine code changed before this baseline.** One change was made first, with
approval: an env-gated per-frame logger in the test driver (`survivors/auto.rs`,
`WOW_SURVIVORS_FRAMES`). It is off unless that variable is set. It reads only state the driver
already used, draws nothing from the run RNG and writes no gameplay state. It is present,
identically, in every run below and every later comparison.

## Reproduction

```bash
cargo build --profile play -p warcraft-survivors
FIXED_DT=16.667 scripts/survivors-bench.sh run <label> late 3 300   # the reference workload
scripts/survivors-bench.sh summary <label>
```

`scripts/survivors-bench.sh` launches each run with these settings:

| Setting | Value |
|---|---|
| Class, zone | Mage, Elwynn Forest (`WOW_SURVIVORS_AUTO=mage:late`, `WOW_SURVIVORS_MAP=elwynn`) |
| Seed | `WOW_SURVIVORS_SEED=1234` |
| Workload | `:late`: run clock starts at 10:00, every Mage spell at rank 8, bosses and rings on the late schedule. 150–190 enemies alive |
| Simulation step | `WOW_FIXED_DT=16.667,0` (the reference). Real-dt runs are kept below as supplementary data |
| Display | 1600×900 window in the foreground (`WOW_WIN=1600x900`, `WOW_BG=0`), vsync off (`WOW_NOVSYNC=1`) |
| State | a fresh `BENILLA_HOME` per run (no saved settings or pick) |
| Instruments | `WOW_SURVIVORS_FRAMES` (per frame), `WOW_FPS_JOURNAL` (per second: CPU/main-thread/GPU ms, entities). No screenshots |
| Length | 300 s wall per run, killed by `timeout`; one cold process per repetition |
| Build | `play` profile (release + incremental, LTO off), default features (includes `dev` instruments) |
| Machine | AMD Ryzen 7 7800X3D (8C/16T), NVIDIA RTX 3070 (Vulkan, driver 610.88), 31 GB RAM, Windows 11, 1920×1080 144 Hz display |

**Every run's log confirms the start:** `run begins as Mage at Elwynn Forest, seed 1234`.

**Measured window:** `Playing` frames that are not under the loading screen, from 10 s of run
clock after play starts, up to the first GameOver. `LevelUp` frames (game paused on the card
screen) are excluded and counted separately. Frame time is `wall_ms`, the real duration of each
frame from a wall clock, which stays correct under a fixed step. CPU, main-thread and GPU ms come
from the journal over the same window.

## Reference baseline: `:late`, fixed step (3 runs)

| Run | Frames | Mean | Median | p95 | p99 | Worst | >33 ms | >100 ms | Alive avg/max | CPU (all threads) | Main thread | GPU |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 9,992 | 14.66 | 14.12 | 19.89 | 25.79 | 39.51 | 6 | 0 | 175 / 266 | 22.81 | 12.43 | 2.13 |
| 2 | 10,360 | 14.29 | 13.56 | 19.54 | 25.25 | 44.71 | 41 | 0 | 175 / 270 | 22.44 | 12.14 | 2.04 |
| 3 | 10,057 | 14.35 | 13.77 | 19.57 | 25.91 | 36.18 | 6 | 0 | 172 / 265 | 22.24 | 12.16 | 2.12 |
| **Median** | | **14.35** | **13.77** | **19.57** | **25.79** | 39.51 | | | 175 | 22.44 | **12.16** | 2.12 |
| Spread (max/min) | | 2.6% | 4.1% | 1.8% | 2.6% | | | | | | | |

All times are in ms. Entities at 200–260 s real: 32,970 / 31,788 / 31,718, of which 320 / 299 /
308 are network-style units (enemies, gems, areas, totems).

**Load over the run (run clock after 10:00), averaged over the three runs:**

| Run-clock minute | Alive | Mean frame time |
|---|---|---|
| 0 | ~155 | 12.6–12.8 ms |
| 1 | ~173 | 13.6–14.4 ms |
| 2 | ~188 | 15.6–16.3 ms |

**What this says:**
- **Frame time is CPU-bound, on the main thread.** About 12 of the roughly 14 ms per frame is
  main-thread time; the GPU needs about 2 ms. `Update` and `PostUpdate` run single-threaded
  (`lib.rs`), so main-thread work is the target.
- **Frame time grows with the crowd,** about +3 ms from 155 to 188 alive.
- At this load the game runs at about 70 fps, with a 95th percentile near 50 fps and a 99th near
  39 fps. There were no frames over 100 ms in the measured window.

## Supplementary: `:late`, real simulation step (5 runs)

Same settings without `WOW_FIXED_DT`, which is how the game actually plays.

| Run | Mean | Median | p95 | p99 | Worst | >100 ms | Alive avg/max | Main | Entities / units (200–260 s) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 14.22 | 13.55 | 20.10 | 24.18 | 56.68 | 0 | 169 / 216 | 12.93 | 30,230 / 277 |
| 2 | 16.30 | 16.26 | 19.75 | 21.83 | 41.35 | 0 | 169 / 246 | 13.46 | 49,759 / 626 |
| 3 | 16.33 | 16.11 | 20.80 | 23.79 | 123.66 | 1 | 169 / 207 | 13.36 | 49,435 / 601 |
| 4 | 17.90 | 17.47 | 22.63 | 25.31 | 257.06 | 12 | 168 / 200 | 14.25 | 50,943 / 625 |
| 5 | 14.23 | 13.69 | 17.55 | 19.95 | 268.46 | 9 | 168 / 201 | 11.77 | 33,547 / 323 |

**Why these are not the reference:** the median spreads 29% between runs (13.55 vs 17.47 ms) at
the same enemy count. The difference follows the **entity load**, not the crowd. Runs 2–4
carried about 300 more network-style units and about 18,000 more ECS entities than runs 1 and 5.
The enemy counts were the same, so the extra units are almost certainly **XP gems left on the
ground** (capped at 350, `enemies.rs` `MAX_GEMS`). Each gem is a full wisp model with emitters,
which works out to about 60 entities per gem. How many pile up depends on the auto-pilot's path,
which drifts with frame timing. The fixed step makes the path repeat, and in all three fixed runs
the gems stay at the low level (about 300 units).

Run 1 reached a GameOver near its end; its window stops there.

## Supplementary: normal mode, real step (3 runs)

| Run | Mean | Median | p95 | p99 | Worst | >100 ms | Alive avg/max | Main | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 6.98 | 6.56 | 9.45 | 10.57 | **824.18** | 5 | 40 / 104 | 6.60 | the hero died around 4 min |
| 2 | 8.21 | 7.46 | 12.73 | 13.85 | 33.20 | 0 | 43 / 99 | 7.95 | survived to level 34 |
| 3 | 6.83 | 6.62 | 9.19 | 10.58 | **326.15** | 2 | 41 / 103 | 6.52 | the hero died |

**Normal mode is not a repeatable workload.** The auto-pilot hero died in 2 of 3 runs, at
different times. It is useful only to observe hitches: frames of 300–824 ms happen *during
play*, as also seen in the first M3 launch. Their cause is not yet identified.

## Hitches and loading

- **Engine warnings:** its own "frame hitch" check (>250 ms) logged 1–2 per `:late` real-step run
  and 1–5 per normal run. Most came from loading; some came from play (see the tables).
- **Blind spot:** under `WOW_FIXED_DT` that check cannot see stalls, because its clock is fixed
  too. Use `frames.csv`'s `wall_ms` (the `>100 ms` and Worst columns) instead.
- **Loading:** a fresh `BENILLA_HOME` means two loading screens (the default zone, then Elwynn),
  about 30 s wall before play.
- **Excluded from the measurement:** the startup pipeline compiles (`ui_gradient_pipeline`,
  `box_shadow_pipeline`, compiled live once per run) and a few "ambience stream starved"
  audio warnings.

## Limitations

- **Repetitions:** three per configuration in the reference. The fixed-step spread (2–4%)
  is small enough to judge changes of about 5% or more. Smaller effects need more runs.
- **Fixed step is not identical play:** even with `WOW_FIXED_DT`, kills and levels at a given
  run time still differ between runs. The load statistics converge, the exact simulation does
  not.
- **Level-up frames are excluded:** `:late` starts at level 1 against late enemies, so it opens
  with a long run of level-up card screens. In fixed-step runs, about half of all frames are
  `LevelUp`. They are game-paused and excluded from the measured window.
- **Low-gem state only:** the fixed-step workload represents the low-gem state. The high-gem
  state (+2–4 ms) appears only in real-step runs and is a candidate, not part of the reference.
- **Not measured:** memory and allocation activity (no tool for them in this toolchain without
  new dependencies); per-system timings (that is the next step, Phase 4).
- **Not checked:** the browser (wasm) build and other GPUs or resolutions.
- **Measurement overhead:** the frame logger counts live enemies every frame and formats one
  short string. It is identical in all compared runs.

## Raw data

The per-run `frames.csv`, `journal.csv` and `log.txt` are in `target/survivors-bench/<label>/`
(git-ignored, about 15 MB in total): `baseline-late`, `baseline-normal`, `fixed-late`.
