# AGENTS.md

## Build Artifacts and Worktrees

SwiftPM writes build artifacts to `native/MuesliNative/.build` inside the active worktree by default. That can consume several GB per worktree when multiple feature worktrees are used.

For local app builds, set `MUESLI_SWIFTPM_SCRATCH_PATH` so `scripts/build_native_app.sh` passes a shared `--scratch-path` to SwiftPM:

```bash
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/dev" ./scripts/dev-test.sh
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/preprod" ./scripts/build_native_app.sh release
```

Caveat: do not run concurrent builds from different worktrees into the same scratch path. Use separate paths per channel, agent, or simultaneous build, such as `dev`, `preprod`, `test`, or `agent-1`.

Deleting a scratch path only removes rebuildable SwiftPM artifacts. It does not delete installed app bundles or app data under `~/Library/Application Support/`.

For direct SwiftPM test runs, pass the scratch path yourself:

```bash
swift test --package-path native/MuesliNative --scratch-path "$HOME/Library/Caches/muesli-spm/test"
```
