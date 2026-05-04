"""Aggregate results.csv into summary.csv + an RTF-vs-length plot.

Usage: python bench/aggregate.py
"""
import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

RESULTS_DIR = Path("bench/results")


def main() -> None:
    df = pd.read_csv(RESULTS_DIR / "results.csv")
    if "error" in df.columns:
        df = df[df["error"].isna() | (df["error"] == "")]

    g = (
        df.groupby("engine")
        .agg(
            n=("rtf", "count"),
            median_rtf=("rtf", "median"),
            p95_rtf=("rtf", lambda s: s.quantile(0.95)),
            median_peak_mb=("peak_rss_mb", "median"),
            max_peak_mb=("peak_rss_mb", "max"),
            has_phoneme_timings=("has_phoneme_timings", "any"),
        )
        .reset_index()
    )
    g.to_csv(RESULTS_DIR / "summary.csv", index=False)
    print(g.to_markdown(index=False))

    length_map = {"s05": 12, "s15": 44, "s30": 100, "s60": 220, "s120": 520}
    df["chars"] = df["sentence_id"].map(length_map)
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for eng, sub in df.groupby("engine"):
        series = sub.groupby("chars")["rtf"].median()
        ax.plot(series.index, series.values, marker="o", label=eng)
    ax.axhline(1.0, ls="--", color="gray", label="real-time (RTF=1)")
    ax.set(
        xlabel="characters",
        ylabel="RTF (CPU)",
        title="RTF vs sentence length (median over repeats)",
    )
    ax.set_yscale("log")
    ax.legend()
    fig.tight_layout()
    fig.savefig(RESULTS_DIR / "rtf_vs_length.png", dpi=150)

    fig2, ax2 = plt.subplots(figsize=(7, 4.5))
    for eng, sub in df.groupby("engine"):
        series = sub.groupby("chars")["peak_rss_mb"].median()
        ax2.plot(series.index, series.values, marker="s", label=eng)
    ax2.set(
        xlabel="characters",
        ylabel="peak RSS (MB)",
        title="Peak memory vs sentence length (median over repeats)",
    )
    ax2.legend()
    fig2.tight_layout()
    fig2.savefig(RESULTS_DIR / "rss_vs_length.png", dpi=150)


if __name__ == "__main__":
    main()
