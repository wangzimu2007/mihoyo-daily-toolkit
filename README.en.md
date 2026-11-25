# Genshin Artifact Toolkit

[中文](README.md) | English

![License](https://img.shields.io/badge/license-MIT-blue)
![Release](https://img.shields.io/github/v/release/wangzimu2007/genshin-artifact-toolkit)
![Platform](https://img.shields.io/badge/platform-Windows%2011%20%7C%20PowerShell%205.1-lightgrey)

Two problems this repository solves, both from real daily use:

1. **The artifact bag is full and there is no good way to decide what to keep.** Feed BetterGI's OCR scan log into an offline pipeline that scores every piece, assigns pieces to characters, and produces a keep/salvage list plus in-game lock-scheme suggestions.
2. **Unattended daily automation fails silently.** Provide verdicts, post-run audits and session keep-alive so "did it actually run?" becomes a queryable log line instead of a guess.

> Every tool here only **analyzes, reports and keeps the session awake**. Nothing is ever decomposed, spent or claimed automatically.

## Layout

| Directory | Contents | Requires |
|---|---|---|
| [`artifact/`](artifact/) | Artifact pipeline: parse → score → assign → lists → lock scheme | Python 3.8+, PyYAML |
| [`reliability/`](reliability/) | Keep-alive, post-run audit, lock diagnosis, input probe | Windows PowerShell 5.1+ |
| [`examples/`](examples/) | Real orchestration scripts for Genshin / ZZZ / HSR — **paths must be adapted** | BetterGI, ZZZ-OneDragon, March7thAssistant |
| [`docs/`](docs/) | Field-tested pitfalls | — |
| [`samples/`](samples/) | Example outputs | — |

## Quick start

### Artifacts: from scan log to keep/salvage list

```bash
export BGI_HOME="/path/to/BetterGI"       # Windows: set BGI_HOME=D:\software\BetterGI
cd artifact
python parse_artifact_log.py --latest     # log -> artifacts.json
python evaluate.py                        # rules -> keep / salvage / report
python build_characters.py                # infer character profiles from equipped gear
python assign.py                          # character x artifact assignment
python make_final_lists.py                # final list + lock-scheme suggestions
python four_star_rolling.py               # 4-star rolling eviction
```

### Reliability: make the 4 AM run actually happen

```powershell
.\reliability\keepawake.ps1 -Until 09:05 -AllowDisplayOff
.\reliability\post-run-audit.ps1 -Game genshin -SinceMinutes 45
.\reliability\lock-monitor.ps1 -UntilHour 12
```

## Scoring model

- **Useful-roll count** = Σ(substat value ÷ max value of one roll), counting only *useful* substats. A 5★ piece gets 9 rolls in total, so the ceiling is ~9. Community tiers: **S≥8 / A≥7 / B 5–6 / C≤4**.
- **Crit value** = CRIT DMG + 2 × CRIT Rate (substats only). 30–35 is acceptable, 40+ is good.
- **Salvage rule is a double condition**: a piece becomes a salvage candidate only if *the rules score it low* **and** *no character profile can use it*. This protects unleveled "potential" pieces and pieces reserved for future characters.

## Three pitfalls that cost the most time

1. **`SetCursorPos` does not count as user input.** To defeat the idle lock you must emit real input (`mouse_event` / `SendInput`); otherwise the idle timer keeps climbing and the session locks as if nothing was running. See [docs/pitfalls.md](docs/pitfalls.md#1-setcursorpos-不重置空闲计时).
2. **Nothing in user space can unlock a locked session.** The lock screen runs in a separate security context — Microsoft's own PowerToys Awake documentation states it cannot work while the lock screen is displayed. You can only *prevent* the lock.
3. **Verdicts must not read only the tail of a log.** Long flows write thousands of lines; filtering by a run start timestamp is required or the evidence gets scrolled away.

## Disclaimer

- Scripts under `examples/` control game windows and simulate input. Make sure that is acceptable under your game's terms of service.
- The artifact pipeline only produces suggestions. **Decomposition is irreversible** — review before acting.
- No account credentials, UIDs or cookies are included. `characters.yaml` is inferred from equipped artifacts and contains no account identifiers.

## License

MIT
