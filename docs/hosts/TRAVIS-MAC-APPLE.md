# Travis-Mac_Apple

Display name: **Travis-Mac_Apple** (`travis-mac-apple`). Apple Silicon M3 daily driver.

This host’s live scripts are **frozen**. Daily start stays:

```bash
~/start-ai-brain.sh
cd ~/Github/agentic-os-dashboard && ./scripts/health-check-travis.sh --quick
cd ~/Github/agentic-os-dashboard && ./run-container-travis.sh
```

Operational dashboard runbook (unchanged): [`agentic-os-dashboard/docs/TRAVIS-MACOS-SETUP.md`](../../../agentic-os-dashboard/docs/TRAVIS-MACOS-SETUP.md).

Open Brain multi-machine sync is **manual** `brain-sync` (do not wire Apple `hooks.json` to Fedora/Intel ensure scripts):

```bash
cd ~/Github/my_ai_brain
./scripts/brain-sync.sh status
./scripts/brain-sync.sh push   # when leaving this Mac, LiveSync idle, you watching
./scripts/brain-sync.sh pull   # when returning, after LiveSync has thoughts.json
```

Apple `backup.sh` remains the **legacy dump**. Do not use it as the three-machine sync.

See [MULTI-MACHINE.md](../MULTI-MACHINE.md) and [TRAVIS-FEDORA.md](TRAVIS-FEDORA.md).
