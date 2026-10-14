# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy>=2.0,<3"]
# ///
"""Harness for the Muse parity test in docs/protocols/muse-parity-process.md.

It owns what a script does better than an agent: the probe prompts, the fixture files
and their right answers, the answer checks, the timing log and Chrome's launch.
Driving the two sites is the agent's job, through any tool that speaks CDP.
"""

import argparse
import csv
import json
import random
import re
import subprocess
import sys
import time
import tomllib
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).parent
PROFILE = Path.home() / ".cache" / "parity-chrome"
SIDES = ("muse", "allm")
SIDE_NAMES = {"muse": "Muse", "allm": "AnythingLLM"}
CATEGORIES = {"groceries": (80, 450), "restaurants": (120, 600), "utilities": (300, 1200), "transport": (30, 400)}


def probes() -> list[dict]:
    return tomllib.loads((HERE / "probes.toml").read_text())["probe"]


def probe_of(probe_id: str) -> dict:
    for p in probes():
        if p["id"] == probe_id:
            return p
    sys.exit(f"no probe '{probe_id}'; `parity.py probes` lists them")


def expenses() -> tuple[list[tuple[str, str, float]], dict[str, float]]:
    """The September expense rows, and each category's total."""
    random.seed(7)
    rows = [("2026-09-01", "rent", 9800.00)]
    for _ in range(44):
        c = random.choice(list(CATEGORIES))
        lo, hi = CATEGORIES[c]
        rows.append((f"2026-09-{random.randint(1, 30):02d}", c, round(random.uniform(lo, hi), 2)))
    rows.sort()
    totals: dict[str, float] = {}
    for _, c, a in rows:
        totals[c] = round(totals.get(c, 0) + a, 2)
    totals["total"] = round(sum(a for _, _, a in rows), 2)
    return rows, totals


def dice() -> list[list[int]]:
    """Seed 42 has two valid answers: both dice drawn together, or one after the other."""
    import numpy as np

    g = np.random.default_rng(42)
    together = np.bincount(g.integers(1, 7, (10000, 2)).sum(1), minlength=13)[2:]
    g = np.random.default_rng(42)
    a, b = g.integers(1, 7, 10000), g.integers(1, 7, 10000)
    in_turn = np.bincount(a + b, minlength=13)[2:]
    return [together.tolist(), in_turn.tolist()]


def numbers_in(text: str) -> set[str]:
    """Every number in the text, read with and without a thousands separator, since 9,800.00
    and 9 800 are one number while '294 538' is two."""
    found = set(re.findall(r"\d+(?:\.\d+)?", text))
    for sep in (",", r"[\u00a0\u202f ]"):
        found |= set(re.findall(r"\d+(?:\.\d+)?", re.sub(rf"(?<=\d){sep}(?=\d{{3}}\b)", "", text)))
    return found


def has(found: set[str], value: float) -> bool:
    return f"{value:.2f}" in found or (value == int(value) and str(int(value)) in found)


def cmd_probes(_: argparse.Namespace) -> None:
    for p in probes():
        extra = " ".join(f"[{k} {p[k]}]" for k in ("group", "after", "attach", "sides") if k in p)
        print(f"{p['id']:16}{p['name']:26}{p['measures']} {extra}".rstrip())


def cmd_probe(a: argparse.Namespace) -> None:
    """The prompt alone on stdout, so it can be sent as printed; `do` goes to stderr, or to stdout when it is all there is."""
    p = probe_of(a.id)
    if "prompt" in p:
        print(p["prompt"])
    if "do" in p:
        print(f"DO: {p['do']}", file=sys.stderr if "prompt" in p else sys.stdout)


def cmd_fixtures(a: argparse.Namespace) -> None:
    out = Path(a.dir)
    out.mkdir(parents=True, exist_ok=True)
    rows, totals = expenses()
    with open(out / "scratch-expenses.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["date", "category", "amount_sek"])
        w.writerows(rows)
    biggest = max(rows, key=lambda r: r[2])
    print(f"wrote {out / 'scratch-expenses.csv'} ({len(rows)} rows)")
    print(f"right totals: {json.dumps(totals)}; biggest single expense: {biggest[1]} {biggest[2]:.2f}")


def cmd_check(a: argparse.Namespace) -> None:
    p = probe_of(a.id)
    found = numbers_in(Path(a.answer).read_text())
    if p.get("check") == "expenses":
        rows, totals = expenses()
        missing = [k for k, v in totals.items() if not has(found, v)]
        biggest = max(rows, key=lambda r: r[2])[1]
        flagged = biggest in Path(a.answer).read_text().lower()
        print(f"totals missing: {missing or 'none'}; biggest expense '{biggest}' named: {flagged}")
        sys.exit(1 if missing or not flagged else 0)
    if p.get("check") == "dice":
        for name, counts in zip(("together", "in turn"), dice()):
            missing = [c for c in counts if str(c) not in found]
            print(f"dice drawn {name}: {len(counts) - len(missing)} of {len(counts)} counts present")
            if not missing:
                sys.exit(0)
        sys.exit(1)
    sys.exit(f"probe '{a.id}' has no automatic check; judge it by reading")


def cmd_chrome(a: argparse.Namespace) -> None:
    """Chrome refuses a debugging port on its default profile, so the harness has its own."""
    url = f"http://127.0.0.1:{a.port}"
    try:
        urllib.request.urlopen(f"{url}/json/version", timeout=1)
        print(f"already up: {url}")
        return
    except OSError:
        pass
    PROFILE.mkdir(parents=True, exist_ok=True)
    subprocess.Popen(
        ["google-chrome", f"--remote-debugging-port={a.port}", "--remote-debugging-address=127.0.0.1",
         f"--user-data-dir={PROFILE}", "--no-first-run", "--window-size=1280,900", *a.urls],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
    )
    for _ in range(30):
        try:
            urllib.request.urlopen(f"{url}/json/version", timeout=1)
            print(f"CDP endpoint: {url}\nprofile: {PROFILE} (sign in to both sites once; it is kept)")
            return
        except OSError:
            time.sleep(0.5)
    sys.exit("Chrome did not open its debugging port")


def log_path(run: str) -> Path:
    return Path(run) / "log.jsonl"


def cmd_mark(a: argparse.Namespace) -> None:
    probe_of(a.probe)
    Path(a.run).mkdir(parents=True, exist_ok=True)
    event = {"t": datetime.now(timezone.utc).isoformat(timespec="seconds"), "probe": a.probe,
             "side": a.side, "kind": a.kind, "text": " ".join(a.text)}
    with open(log_path(a.run), "a") as f:
        f.write(json.dumps(event) + "\n")
    print(f"{event['t']} {a.side} {a.probe} {a.kind}")


def cmd_table(a: argparse.Namespace) -> None:
    events = [json.loads(line) for line in log_path(a.run).read_text().splitlines()]
    print("| Probe | Muse | AnythingLLM |\n| --- | --- | --- |")
    for p in probes():
        if p.get("group") and not any(e["probe"] == p["id"] for e in events):
            continue
        cells = []
        for side in SIDES:
            mine = [e for e in events if e["probe"] == p["id"] and e["side"] == side]
            sent = [datetime.fromisoformat(e["t"]) for e in mine if e["kind"] == "sent"]
            ended = [datetime.fromisoformat(e["t"]) for e in mine if e["kind"] == "ended"]
            parts = []
            if sent and ended:
                parts.append(f"{(ended[-1] - sent[-1]).total_seconds():.0f} s")
            parts += [e["text"].replace("|", "/") for e in mine if e["kind"] == "note" and e["text"]]
            cells.append(". ".join(parts) or "not run")
        print(f"| {p['name']} | {cells[0]} | {cells[1]} |")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(required=True)
    sub.add_parser("probes", help="list the probes").set_defaults(fn=cmd_probes)
    s = sub.add_parser("probe", help="print one prompt, word for word")
    s.add_argument("id")
    s.set_defaults(fn=cmd_probe)
    s = sub.add_parser("fixtures", help="write the probe files and print their right answers")
    s.add_argument("dir")
    s.set_defaults(fn=cmd_fixtures)
    s = sub.add_parser("check", help="check an answer saved as text against the right one (code, file)")
    s.add_argument("id")
    s.add_argument("answer")
    s.set_defaults(fn=cmd_check)
    s = sub.add_parser("chrome", help="start the Chrome that the driving tool attaches to")
    s.add_argument("--port", type=int, default=9222)
    s.add_argument("urls", nargs="*", default=["https://muse.ai"])
    s.set_defaults(fn=cmd_chrome)
    s = sub.add_parser("mark", help="log that a probe was sent or ended, or a note about it")
    s.add_argument("run", help="the run's folder, such as build/parity/2026-10-14")
    s.add_argument("probe")
    s.add_argument("side", choices=SIDES)
    s.add_argument("kind", choices=("sent", "ended", "note"))
    s.add_argument("text", nargs="*", help="the note")
    s.set_defaults(fn=cmd_mark)
    s = sub.add_parser("table", help="print the probe table from a run's log (grouped probes only once logged)")
    s.add_argument("run")
    s.set_defaults(fn=cmd_table)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
