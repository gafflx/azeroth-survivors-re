# Survivors testing checklist

The durable checklist for every survivors gameplay change. Record automated results and manual
playtest results **separately**, with the date and the commit. Never record a pass for something
that was not actually run.

## Environment status

| Requirement | Needed for | Status on the main dev machine (Windows 11, 2026-10-24) |
|---|---|---|
| Rust 1.98.1 + clippy + rustfmt (pinned in `rust-toolchain.toml`) | everything | installed |
| MSVC Build Tools (C++ workload) | native link, Lua C build | installed (VS Build Tools 2022) |
| `make` | Makefile shortcuts | missing; run the scripts directly from Git Bash |
| WoW 1.12.1 `Data` (`scripts/fetch-data.sh` → `wow-data/Data`, ~5.5 GB) | running the game, data-gated tests | present since 2026-10-25: 14 MPQs, 5.1 GB; the zip's SHA-1 matched archive.org's (`b72598b3…5a62`). The game has not been launched yet |
| wasm32 target + wasm-bindgen-cli 0.2.122 + wasi-sdk 27 | browser build | wasm32 target installed; wasm-bindgen-cli and wasi-sdk missing; `scripts/web-setup.sh` does not support Git Bash (Linux/Darwin only), so install wasi-sdk by hand and set `WASI_SDK`, or rely on CI |
| Node | `web/tests/*.test.mjs` | missing |
| WebGPU browser | running the browser build | not checked |

## Baseline record

Automated only; no manual playtest has been done (no WoW data on the machine). Windows 11, rustc
1.98.1, MSVC. Times are cold builds.

| Date | Commit | Check | Result |
|---|---|---|---|
| 2026-10-24 | dd5e330 | `cargo fmt --all -- --check` | **fails (pre-existing)**: 16 diffs in 13 upstream files (benilla-protocol, benilla-world, benilla-ui, benilla-assets, `ui_chat/settings.rs`); none in `survivors/` |
| 2026-10-24 | dd5e330 | `cargo check -p warcraft-survivors` | pass, 0 warnings (4m 12s) |
| 2026-10-24 | dd5e330 | `cargo check -p warcraft-survivors --no-default-features` | pass (2m 39s) |
| 2026-10-24 | dd5e330 | `cargo clippy -p benilla-app -p warcraft-survivors --all-targets -- -D warnings` | **fails (pre-existing)**: `needless_borrow` at `benilla-world/src/rig_anim/compose.rs:198` stops the run before `benilla-app` |
| 2026-10-24 | dd5e330 | same clippy without `-D warnings` | completes: 1 warning in benilla-world, 7 in benilla-app; 2 of them in survivors (`hud.rs:1648` empty line after doc comment; `grade.rs:77` type_complexity) |
| 2026-10-24 | dd5e330 | `cargo test -p benilla-app --lib survivors` | ok, **0 tests** (none exist); test build ~15 min cold |
| 2026-10-24 | dd5e330 | `cargo test -p benilla-world --lib rig_anim::compose --no-default-features` | 7 passed |
| 2026-10-24 | dd5e330 | `cargo test -p benilla-world --lib web_budget --no-default-features` | 2 passed |
| 2026-10-24 | dd5e330 | `cargo test -p wenilla-host` | 12 passed (unit + 3 integration files) |
| 2026-10-24 | dd5e330 | `cargo test -p benilla-ui --lib script::tests::events` | 10 passed |
| 2026-10-24 | dd5e330 | `cargo test -p benilla-ui --lib wenilla_listener` | 2 passed |
| 2026-10-24 | dd5e330 | wasm `cargo check … -p wenilla --features webgpu` | **blocked**: mlua-sys build script needs wasi-sdk (`WASI_SDK` unset, `tools/wasi-sdk` absent) |
| 2026-10-24 | dd5e330 | `WOW_DATA= cargo test --workspace` | not run (long; optional) |
| 2026-10-24 | dd5e330 | running the game | not run: no `wow-data/` |

## M1 record

Automated, local only (Windows 11, rustc 1.98.1, MSVC), on branch `docs/megabonk-roadmap` with the
M1 changes uncommitted on top of dd5e330. **The new CI job has not run on GitHub yet.** No manual
playtest has been done (no WoW data on the machine).

| Date | Check | Result |
|---|---|---|
| 2026-10-24 | `cargo check -p warcraft-survivors` | pass, 0 warnings |
| 2026-10-24 | `cargo check -p warcraft-survivors --no-default-features` | pass; 4 unused-import warnings in `entities.rs`, `loading_screen.rs`, `net.rs`, identical to the baseline (not survivors) |
| 2026-10-24 | `scripts/survivors-lint.sh` | clean (the 2 baseline survivors lints are fixed) |
| 2026-10-24 | `scripts/survivors-lint.sh --no-default-features` | clean |
| 2026-10-24 | `rustfmt --edition 2021 --check crates/benilla-app/src/survivors/mod.rs crates/warcraft-survivors/src/main.rs` | pass |
| 2026-10-24 | `cargo test -p benilla-app --lib survivors` | **26 passed**, 0 failed (incremental test build 7m 10s; cold ~13–15 min) |
| 2026-10-24 | CI-filter tests: `rig_anim::compose` 7, `web_budget` 2, `wenilla-host` 12, `script::tests::events` 10, `wenilla_listener` 2 | **33 passed**, 0 failed; same counts as the baseline (earlier summaries said "32"; the per-suite counts add to 33) |
| 2026-10-24 | `cargo clippy -p benilla-app -p warcraft-survivors --all-targets -- -D warnings` | still fails on the baseline `benilla-world` `needless_borrow` (unchanged, not ours) |
| 2026-10-24 | `cargo fmt --all -- --check` | unchanged baseline: the same 13 upstream files; survivors files clean |
| 2026-10-24 | wasm check | blocked locally (no wasi-sdk); covered by CI's `wasm` job, not yet run on this change |
| 2026-10-24 | `.github/workflows/check.yml` | not machine-validated: no YAML parser, actionlint or Node on this machine. Checked by hand only (no tabs, mirrors the existing jobs' structure) |

## Commands

Run from Git Bash at the repo root.

```bash
# If a fresh Git Bash can't find cargo, add rustup's bin dir for the session
export PATH="$HOME/.cargo/bin:$PATH"

# One-time: after installing rustup + MSVC Build Tools, rustup reads rust-toolchain.toml
rustup show

# A. Static checks (no game data needed)
cargo check -p warcraft-survivors                       # dev features (default)
cargo check -p warcraft-survivors --no-default-features # the player build
scripts/survivors-lint.sh                               # strict clippy, survivors scope (see below)
rustfmt --edition 2021 --check crates/benilla-app/src/survivors/mod.rs crates/warcraft-survivors/src/main.rs
cargo fmt --all -- --check                              # workspace-wide: fails on upstream files today

# B. Data-free tests: survivors, then the 32 CI-filter tests
cargo test -p benilla-app --lib survivors
cargo test -p benilla-world --lib rig_anim::compose --no-default-features
cargo test -p benilla-world --lib web_budget --no-default-features
cargo test -p wenilla-host
cargo test -p benilla-ui --lib script::tests::events
cargo test -p benilla-ui --lib wenilla_listener

# C. wasm check (what CI's check.yml runs; needs the wasm32 target and WASI_SDK; see below)
rustup target add wasm32-unknown-unknown
cargo check --target wasm32-unknown-unknown -p wenilla --no-default-features --features webgpu

# D. Full workspace (long; data-gated tests skip without WOW_DATA)
WOW_DATA= cargo test --workspace

# Run the game natively (needs wow-data)
scripts/fetch-data.sh
WOW_DATA=wow-data/Data cargo survivors                  # = cargo run --profile play -p warcraft-survivors

# Browser build and serve (needs the wasm toolchain)
scripts/web-setup.sh
scripts/web-build.sh
cargo run --release -p wenilla-host -- --www web/dist --data wow-data/Data   # http://127.0.0.1:8090/

# Hands-off run for smoke and perf (native)
WOW_DATA=wow-data/Data WOW_SURVIVORS_AUTO=mage WOW_SURVIVORS_MAP=elwynn cargo survivors
WOW_DATA=wow-data/Data WOW_SURVIVORS_AUTO=mage:late WOW_FPS_JOURNAL=fps.csv WOW_GPU_MS=1 cargo survivors

# The same, with a fixed run seed
WOW_DATA=wow-data/Data WOW_SURVIVORS_SEED=1234 WOW_SURVIVORS_AUTO=mage cargo survivors
```

### Survivors strict clippy
`scripts/survivors-lint.sh` runs
`cargo clippy -p benilla-app -p warcraft-survivors --no-deps --all-targets --message-format=short`
and fails if any warning or error points into `crates/benilla-app/src/survivors/` or
`crates/warcraft-survivors/`. Extra arguments go to cargo (e.g. `--no-default-features`).

Why not plain `cargo clippy … -- -D warnings`:
- Without `--no-deps`, clippy also lints the workspace crates benilla-app depends on, and
  upstream's `needless_borrow` at `benilla-world/src/rig_anim/compose.rs:198` stops the run.
- benilla-app itself has 5 warnings outside survivors (`webbridge/nearby.rs`,
  `webbridge/snapshot.rs` ×3, `realmlist.rs`). They are not this mode's to fix, so they stay
  warnings, and the strict check is limited to the survivors paths.

Nothing is allowed or suppressed globally. The script runs the same way locally (Git Bash) and in
CI (Linux); its path filter accepts both `\` and `/`.

### Seeded runs
Every run starts from an explicit seed, `Run.seed`, and `start_run` resets the survivors `Rng` to
it.
- **Fixed seed:** set `WOW_SURVIVORS_SEED=<u64>` natively. On the web, use `?survivors_seed=<u64>`
  or `__wenilla_env.survivors_seed`. Both go through `crate::webenv::var`, so this is wasm-safe.
- **No seed set:** the run is seeded from the clock, as before.
- The seed is logged at run start (`survivors: run seed N`) and in the auto-run banner line, so any
  run can be replayed with that seed.
- **In tests:** build the generator with `Rng::seeded(n)`, or pass the seed to
  `hud::start_run(&mut run, &mut selection, &mut rng, seed)`.

Every gameplay roll goes through that one generator: crits, DoT targets, totem placement, spawn
picks and positions, heal drops, level-up offers, and the auto driver's card picks. The menu's
Randomize button has its own generator (`Local<Rng>`), so browsing the menu never shifts the run's
sequence.

**What the seed does not make deterministic.** The seed fixes the sequence of rolls. It does not
fix *which* roll each event consumes in a live run. Two runs with the same seed can still differ,
because these inputs are not seeded:
- **Frame timing:** every system steps by the real frame `dt`. Cooldowns, the 0.12 s spawn timer,
  hit landing times and movement all depend on it, which changes how many rolls happen and in what
  order.
- **Player input:** movement and card choices, and when they happen.
- **Loading:** asset and terrain streaming time, and the loading screen that holds the gameplay
  systems.
- **Entity iteration order:** the order in which queries visit enemies decides targeting ties, the
  order of loot rolls and which XP gem absorbs a capped drop.
- **Floating point:** native and wasm may round differently.

Bit-for-bit replay is guaranteed only for the pure logic covered by the unit tests (offers, picks,
the generator). A live seeded run is only *reproducible in tendency*, not frame-exact. A fixed
timestep would be needed for more, and that is not in M1.

### WebAssembly check prerequisite
The wasm `cargo check` needs **wasi-sdk 27**, even without linking: the Lua VM's build script
(`third_party/mlua-sys`) compiles C with wasi-sdk's clang and sysroot (it looks for
`share/wasi-sysroot/lib/wasm32-wasip1/libsetjmp.a` under `WASI_SDK`, else `tools/wasi-sdk`).
`scripts/web-setup.sh` installs it on **Linux and macOS** only. Its `uname` switch has no
Windows/Git Bash branch.

Supported environments:
- **CI:** the `wasm` job of `.github/workflows/check.yml` on `ubuntu-latest`. It runs
  `scripts/web-setup.sh`, then the check, on every pull request and every push to `main`. It
  already covers the survivors code, because `wenilla` boots `run_survivors`. Reuse it as is.
- **Locally:** Linux, macOS or WSL2 with `scripts/web-setup.sh`. On plain Windows the check is not
  supported. No workaround has been tried.

## M3 record

Automated, local only (Windows 11, rustc 1.98.1, MSVC), on `docs/megabonk-roadmap` with the M3
changes uncommitted on top of b60f004. Not run on GitHub CI, and no manual playtest (the WoW data
is present, but the game has not been launched).

| Date | Check | Result |
|---|---|---|
| 2026-10-25 | golden tables recorded before the refactor | `abilities.golden` (657 lines) recorded from the unchanged code. A regeneration on a clean b60f004 checkout was **byte-identical** (SHA-1 `136663c7…420c`). `cards.golden` (666 lines) recorded on that b60f004 checkout |
| 2026-10-25 | `cargo test -p benilla-app --lib survivors` | **36 passed**, 0 failed: the 26 M1 tests, 2 golden tables, 8 field/level-table/rarity tests |
| 2026-10-25 | `cargo check -p warcraft-survivors` | pass |
| 2026-10-25 | `cargo check -p warcraft-survivors --no-default-features` | pass; the same 4 baseline upstream warnings |
| 2026-10-25 | `scripts/survivors-lint.sh` (and with `--no-default-features`) | clean |
| 2026-10-25 | survivors rustfmt check | pass |
| 2026-10-25 | CI-filter tests (`rig_anim::compose` 7, `web_budget` 2, `wenilla-host` 12, `script::tests::events` 10, `wenilla_listener` 2) | 33 passed. Run on the M3 tree before the two review fixes, which touched only survivors files these crates don't depend on |
| 2026-10-25 | wasm check | blocked locally (wasi-sdk); CI's `wasm` job covers it, not yet run |
| 2026-10-25 | **first native launch**: `cargo build --profile play -p warcraft-survivors` (6m 52s), then `WOW_DATA=…/wow-data/Data WOW_SURVIVORS_SEED=1234 WOW_SURVIVORS_AUTO=mage WOW_SURVIVORS_MAP=elwynn WOW_SURVIVORS_SHOTS=<dir>`, stopped by a 300 s `timeout` | **runs.** Boot → menu → `run seed 1234` → Elwynn loading screen (23 s) → play. Reached run time 205 s: level 27, 929 kills, up to 97 alive. HP never hit 0, so no death. About 60 fps in play. No panic and no error. Screenshots show the WoW pick screen, rarity cards (Pyroblast reads "toughest enemy in range") and the horde fight with spell visuals |

| 2026-10-25 | seeded auto run for each of the other 8 classes: the same binary and command with `WOW_SURVIVORS_AUTO=<class>`, Elwynn, seed 1234, `timeout 150` | **all 8 run**: no panic or error, and each log's "run begins as …" names the requested class. Run time reached 112–132 s. Ended at: Warrior lv 17 (409 kills), Hunter lv 14 (380), Priest lv 9, Shaman lv 9, Druid lv 7, Paladin lv 5, Rogue lv 5, Warlock lv 5 (hp 28). Abilities M3 touched that came up in play: Hunter's `aimed_shot` (toughest target), Shaman's `magma_totem` (pulse), `searing_totem` (no pulse) and `lightning_shield` (hero visual, impact 403). `pyroblast`, `exorcism` and `starfire` were not picked in any run. 2–6 frame-hitch warnings per run, mostly behind the loading screen |

## First CI run (GitHub, 2026-10-25)

[gafflx/azeroth-survivors-re#1](https://github.com/gafflx/azeroth-survivors-re/pull/1) (head
30e0c3b, base `gafflx:main` = dd5e330), `check.yml` on `ubuntu-latest`:

| Job | Result | Cause |
|---|---|---|
| `wasm` | pass (5 min) | first wasm check of the M1/M3 code |
| `client-carries` | pass (15 min) | |
| `host-and-ui` | **fail** at "browser startup and journal regressions" (`node --test web/tests/*.test.mjs`), exit 1 | **pre-existing**: upstream's own `check` run on `main` at dd5e330 fails at the same step. M1/M3 never touch `web/`. Not investigated |
| `survivors` | **fail** at "survivors unit tests" (rustfmt and strict clippy passed): 35 passed, 1 failed | `ability_numbers_match_the_golden_table` line 6: Frostbolt rank 5. Every column matched except the cooldowns, which differed in the last bits: Linux `0.97246754/0.58348054/0.34036362` vs the Windows-recorded `0.97246766/0.5834806/0.34036368` |
| `CI / gates` | skipped | `ci.yml` runs only for PRs from another repository |

**Why the cooldowns differ:** `Owned::cooldown` uses `0.93f32.powi(level - 1)`. `f32::powi` does
not promise the same rounding on every platform, so Windows and Linux disagree by an ulp or two.
Every other golden number is plain `*` and `+`, which IEEE floating point keeps bit-identical
everywhere, and all of those matched. This is a property of the game (about 1e-7 s of cooldown
between platforms, possibly the browser build too), not an M3 change.

**The fix is test-only:** `same_line` in `tests.rs` holds every golden word exact, except the
`cd=` values, which match within a 1e-6 relative tolerance (about 8 ulps). The recorded file is
unchanged, and `golden_lines_forgive_only_the_cooldown_bits` pins the tolerance. Locally: 37
passed, lint clean. The fix has not been re-run on CI yet. Removing `powi` from the cooldown
formula would make the platforms agree exactly, but it changes game values on one platform. That
is left as a possible follow-up, relevant only if cross-platform replay must be exact.

**Notes from the first launch** (observations, not measurements; M2 does the measuring):
- **Frame hitches:** 340–1357 ms hitches happen behind both loading screens. Five more, of 410–430 ms, happened during play, a minute or more apart. Their cause has not been investigated.
- **Audio:** one "zone music stream starved" warning right after the Elwynn loading screen.
- **Run-time pace:** the run clock advanced 205 s over about 4.4 min of play, because each level-up card screen pauses it. The fps column in the auto log averages over 10 s of real time.
- **Replay:** a second run with the same seed has not been compared (see § Seeded runs for the limits).

Process note: the b60f004 checkout shared `target/` with the main tree. Cargo then reused that
checkout's test binary and Lua build-script output for the main tree. That run was discarded,
`cargo clean -p` was run on the path packages, and all results above come from a clean rebuild.
Don't share `target/` across worktrees.

### Golden tables
`crates/benilla-app/src/survivors/testdata/abilities.golden` and `cards.golden` pin every
ability's numbers at every rank, and every level-up card's text and rarity. `.gitattributes` keeps
`*.golden` at LF.
- **They run with the survivors tests.** A mismatch names the file and line.
- **To re-record** (only for a change *meant* to move numbers or text, never for a refactor):
  `SURVIVORS_BLESS=1 cargo test -p benilla-app --lib survivors`. It rewrites the files and then
  fails on purpose, so review `git diff -- '*/testdata/*'`. It refuses to run when `CI` is set.

## Per-change checklist

### Automated (every PR)
- [ ] A: both native checks, `scripts/survivors-lint.sh`, survivors rustfmt check
- [ ] B: `cargo test -p benilla-app --lib survivors` (and any crate touched)
- [ ] CI `check.yml` green: `wasm`, `host-and-ui`, `client-carries`, `survivors`
- [ ] C: wasm check, locally or green in CI's `check.yml`
- [ ] No new `std::time::Instant`/`SystemTime`/`std::env` in survivors code (use `web_time`,
      `bevy::platform::time`, `crate::webenv::var`)
- [ ] No reordering or removal in `data::CLASSES` / `data::MAPS` (the saved pick stores indices)
- [ ] Changes stay inside `survivors/` or new files; any upstream-file edit is justified and
      `#[cfg]`-gated or listed in `docs/UPSTREAM.md`
- [ ] New page-side web files are added to the `cp` line in `scripts/web-build.sh`

### Performance (any change to spawning, combat, visuals or pickups)
- [ ] Stress mode (from M2) before and after: p50/p95/p99, live enemies, `RigStarved`, live texts
- [ ] Native p95 ≤ 16.7 ms at peak horde; zero starved rigs
- [ ] If a browser build is available: FPS journal at peak, p95 ≤ 33 ms

### Manual playtest (record class, zone and result)
- [ ] Menu: the pick (race, gender, class, zone) persists across a restart; Randomize works
- [ ] Enter World: the loading screen, then the run starts; the hero moves with WASD, jumps with Space
- [ ] Camera: locked by default, hero faces the cursor; C unlocks and drag orbits; the wheel zooms
- [ ] Abilities auto-cast with the right WoW visuals and sounds; damage numbers are readable
- [ ] Level-up: 3 cards, keys 1/2/3 and clicks work, the time is paused
- [ ] F movement spell from level 5
- [ ] Bosses arrive on schedule with a banner
- [ ] Esc pauses and resumes
- [ ] Death → results; victory → results; Enter → menu; a second run starts clean
- [ ] Sample at least: one caster (Mage), one melee (Warrior), one pet/totem class (Shaman or
      Hunter), in a starting zone and a late zone
- [ ] Browser build (when available): boots on WebGPU, sound starts on the first click
