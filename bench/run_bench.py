"""Benchmark orchestrator. Runs each adapter against the fixed corpus and
writes one row per (engine, sentence, repeat) to bench/results/results.csv."""
import argparse
import csv
import json
from pathlib import Path

from bench.measure import run_in_subprocess

ENGINES = ["bookbot_adapter", "zipvoice_adapter", "pockettts_adapter"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", choices=ENGINES + ["all"], default="all")
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument(
        "--append",
        action="store_true",
        help="Append to existing results.csv instead of overwriting it.",
    )
    args = ap.parse_args()

    corpus = json.loads(Path("bench/corpus.json").read_text())
    out_dir = Path("bench/results")
    out_dir.mkdir(exist_ok=True)
    csv_path = out_dir / "results.csv"

    rows: list[dict] = []
    if args.append and csv_path.exists():
        with csv_path.open() as f:
            rows.extend(csv.DictReader(f))

    engines = ENGINES if args.engine == "all" else [args.engine]
    for eng in engines:
        for s in corpus["sentences"]:
            for r in range(args.repeats):
                wav = out_dir / f"{eng}_{s['id']}_r{r}.wav"
                row: dict = {
                    "engine": eng,
                    "sentence_id": s["id"],
                    "repeat": r,
                }
                try:
                    res = run_in_subprocess(eng, s["text"], str(wav))
                    rtf = res["wall_seconds"] / max(res["audio_seconds"], 1e-6)
                    row.update(
                        {
                            "wall_s": res["wall_seconds"],
                            "audio_s": res["audio_seconds"],
                            "rtf": rtf,
                            "peak_rss_mb": res["peak_rss_mb"],
                            "voice_id": res.get("voice_id"),
                            "has_phoneme_timings": res.get("phoneme_timings") is not None,
                        }
                    )
                except Exception as e:
                    row["error"] = f"{type(e).__name__}: {e}"
                rows.append(row)
                print(f"[{eng}] {s['id']} r{r}: {row}")

    fieldnames = sorted({k for r in rows for k in r})
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
    print(f"\nWrote {len(rows)} rows -> {csv_path}")


if __name__ == "__main__":
    main()
