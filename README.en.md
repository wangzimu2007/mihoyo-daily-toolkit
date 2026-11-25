# MiHoYo Daily Toolkit

[中文](README.md) | English

Daily-automation reliability toolkit for three HoYoverse games — **Genshin Impact**, **Zenless Zone Zero**,
**Honkai: Star Rail** — plus an offline **artifact sorting pipeline** for Genshin.

The three games share one idea: a run is only "done" when a **verdict** says so, not when a process exits.
Everything else (keep-alive, post-run audit, lock diagnosis) exists to make that verdict trustworthy.

> Every tool here only **analyzes, reports and keeps the session awake**. Nothing is ever decomposed, spent or claimed automatically.

## Layout

| Path | Contents | Requires |
|---|---|---|
| [`artifact/`](artifact/) | Genshin artifact pipeline: parse → score → assign → lists → lock scheme | Python 3.8+, PyYAML |
| [`games/genshin/`](games/genshin/) | Genshin daily chain (BetterGI one-dragon wrapper) | BetterGI |
| [`games/zzz/`](games/zzz/) | ZZZ daily chain, virtual gamepad service, backend start/stop | ZZZ-OneDragon |
| [`games/hsr/`](games/hsr/) | HSR daily chain and stamina fallback | March7thAssistant |
| [`reliability/`](reliability/) | Keep-alive, post-run audit, lock diagnosis, input probe | Windows PowerShell 5.1+ |
| [`scripts/`](scripts/) | Install/uninstall Windows scheduled tasks | Windows |
| [`examples/`](examples/) | Cross-game orchestration (dispatcher, weekly scan) — **paths must be adapted** | — |
| [`docs/`](docs/) | Field-tested pitfalls | — |
| [`samples/`](samples/) | Example outputs + **offline self-test sample log** | — |

## Why three games need three different setups

| | Genshin | ZZZ | HSR |
|---|---|---|---|
| Driver | BetterGI | ZZZ-OneDragon | March7thAssistant |
| Needs foreground window | yes | yes | **no** (background mode) |
| Needs unlocked session | yes | yes | **no** (works while locked) |
| Verdict source | BGI log keywords | `app_run_record/*.yml` | M7A `runs/*.log` |
| Typical failure | window not foregrounded / missing combat-strategy file | backend down / gamepad service killed | inventory full blocks stamina spending |

**Consequence**: the anti-lock keep-alive only has to cover Genshin + ZZZ windows; HSR runs fine while locked.

## Quick start

### Artifacts

```bash
export BGI_HOME="/path/to/BetterGI"       # Windows: set BGI_HOME=D:\software\BetterGI
cd artifact
pip install -r requirements.txt
python parse_artifact_log.py --latest
python evaluate.py
python build_characters.py
python assign.py
python make_final_lists.py
python four_star_rolling.py
```

One command on Windows: `.\artifact\run-pipeline.ps1 -BgiHome "D:\software\BetterGI"`

**No game needed** — the repo ships a sample scan log:

```powershell
.\samples\offline-test.ps1
```

### Daily automation

```powershell
.\scripts\install-tasks.ps1 -KeepAwake -DailyAll -WeeklyScan -ToolkitRoot "D:\tools\bgi-scan"
.\examples\run-daily-all.ps1        # Genshin → ZZZ
```

Optional environment overrides: `BGI_HOME` (BetterGI install dir), `ZZZ_OD_ROOT` (ZZZ-OneDragon dir).

### Reliability

```powershell
.\reliability\keepawake.ps1 -Until 09:05 -AllowDisplayOff
.\reliability\post-run-audit.ps1 -Game genshin -SinceMinutes 45
.\reliability\lock-monitor.ps1 -UntilHour 12
```

## Scoring model (artifacts)

- **Useful rolls** = Σ(substat value ÷ one-roll max), only counting *useful* substats. A 5★ piece gets 9 rolls total, so the ceiling is ~9. Tiers: **S≥8 / A≥7 / B 5–6 / C≤4**.
- **Crit value** = CRIT DMG + 2 × CRIT Rate (substats only). 30–35 acceptable, 40+ good.
- **Salvage is a double condition**: low rule score **and** no character can use it — protecting unleveled "potential" pieces.

## Three pitfalls worth the read

1. **`SetCursorPos` does not count as user input** — anti-lock scripts must emit real input (`mouse_event` / `SendInput`), otherwise the idle timer keeps climbing. See [docs/pitfalls.md](docs/pitfalls.md).
2. **Nothing in user space can unlock a locked session** — Microsoft's own PowerToys Awake docs confirm it; you can only *prevent* the lock.
3. **Verdicts must not read only the log tail** — long flows write thousands of lines and scroll the evidence away; filter by run start timestamp.

## Disclaimer

- Scripts under `games/` and `examples/` control game windows and simulate input. Make sure that is acceptable under your game's terms of service.
- The artifact pipeline only produces suggestions. **Decomposition is irreversible.**
- No account credentials, UIDs or cookies are included.

## License

MIT
