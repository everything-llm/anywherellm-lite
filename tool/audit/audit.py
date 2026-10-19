# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Walks AnywhereLLM Lite on an Android emulator and packages what it saw for auditing.

It builds `tool/audit_app.dart` (the real UI over the test fakes and the prototype's sample
data), installs it, then runs the steps in `steps.toml`: each step launches the app, taps
through it by accessibility label, and takes each screenshot once in each theme, switching the
device's theme there. The result is a folder and a zip holding the screenshots, each screen's
UI dump, the log lines each step produced, a manifest and an `index.html` contact sheet.

    uv run tool/audit/audit.py                 # reuse a running emulator, or boot one
    uv run tool/audit/audit.py --only chat     # steps whose name or group matches
    uv run tool/audit/audit.py --dump          # print the labels on the screen now
"""

import argparse
import html
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "tool"))
from device import (
    PACKAGE,
    Device,
    Driver,
    StepError,
    close_device,
    install,
    open_device,
    print_labels,
    restore,
    steady,
)

ENTRYPOINT = "tool/audit_app.dart"
APK = ROOT / "build/app/outputs/flutter-apk/app-debug.apk"
# Lines in the log that an audit reader wants to see.
FINDINGS = {
    "overflow": re.compile(r"RenderFlex overflowed|overflowed by"),
    "exception": re.compile(r"EXCEPTION CAUGHT|FATAL EXCEPTION|Unhandled Exception"),
    "anr": re.compile(r"ANR in"),
}


class Walk(Driver):
    """Runs steps on the device, taking each screenshot once in each of [themes]: the app follows
    the device's theme as it changes, so one walk serves them all. A failed step does not stop
    the walk; the next step goes on."""

    def __init__(self, device: Device, out: Path, themes: list[str]):
        super().__init__(device, out)
        self.themes = themes
        self.theme = ""  # the device's theme, once this walk has set it
        self.step = {"index": 0, "name": "try"}
        self.shots: list[dict] = []

    def stem(self) -> str:
        return f"{self.step['index']:02d}-{self.step['name']}"

    def use_theme(self, theme: str) -> bool:
        """Switches the device to [theme], and says whether it changed."""
        if theme == self.theme:
            return False
        self.d.night("yes" if theme == "dark" else "no")
        self.theme = theme
        return True

    def before_launch(self) -> None:
        if self.themes:
            self.use_theme(self.themes[0])

    def shoot(self, suffix: str = "", failed: bool = False) -> None:
        """A screenshot in each theme, starting in the device's own, and the screen's dump."""
        stem = self.stem() + (f"-{suffix}" if suffix else "") + ("-FAILED" if failed else "")
        # What a screen reader reaches is the same in every theme, so one dump serves them all.
        nodes = self.nodes()
        labels = [n["label"] for n in nodes if n["label"]]
        # A control a screen reader reaches but cannot name.
        unlabelled = sum(
            1 for n in nodes if n["clickable"] and not n["label"] and n["package"] == PACKAGE
        )
        for theme in sorted(self.themes, key=lambda t: t != self.theme):
            if self.use_theme(theme):
                # The app redraws in the new theme, which the theme's 200 ms change follows.
                time.sleep(0.8)
            (self.out / f"{stem}-{theme}.xml").write_text(self.d.xml)
            self.d.screenshot(self.out / f"{stem}-{theme}.png")
            self.shots.append({"theme": theme, "file": f"{stem}-{theme}.png", "dump": f"{stem}-{theme}.xml",
                               "labels": labels, "unlabelled": unlabelled})

    def run(self, step: dict, actions: list[str]) -> dict:
        self.step, self.shots = step, []
        record = {"name": step["name"], "group": step["group"], "signed_out": bool(step.get("signed_out")),
                  "status": "ok", "shots": self.shots, "findings": {}}
        started = time.time()
        self.d.shell("logcat -c", check=False)
        try:
            self.launch()
            for action in actions:
                self.do(action)
            if not self.shots:
                self.shoot()
        except (StepError, subprocess.TimeoutExpired) as error:
            record["status"] = "failed"
            record["error"] = str(error)
            try:
                self.shoot(failed=True)
            except StepError:
                pass
        log = self.d.shell("logcat -d -v time", check=False)
        for name, pattern in FINDINGS.items():
            count = sum(1 for line in log.splitlines() if pattern.search(line))
            if count:
                record["findings"][name] = count
        if record["findings"]:
            record["log"] = f"{self.stem()}.log"
            (self.out / record["log"]).write_text(log)
        record["seconds"] = round(time.time() - started, 1)
        return record


# --- Device, build and packaging ---------------------------------------------------------


def build(signed_out: bool, target: Path) -> None:
    command = ["flutter", "build", "apk", "--debug", "-t", ENTRYPOINT, "--target-platform", "android-x64"]
    if signed_out:
        command.append("--dart-define=AUDIT_SIGNED_OUT=true")
    print("building:", " ".join(command))
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit(done.stdout[-3000:] + done.stderr[-3000:])
    shutil.copy(APK, target)


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def contact_sheet(manifest: dict) -> str:
    rows = sorted(manifest["steps"], key=lambda s: s["status"] == "ok")
    parts = [
        "<!doctype html><meta charset=utf-8><title>AnywhereLLM audit</title>",
        "<style>body{font:14px system-ui;margin:24px;background:#fafafa;color:#111}"
        "section{margin:0 0 32px}h2{font-size:15px;margin:0 0 8px}.bad{color:#b00020}"
        ".row{display:flex;gap:12px;flex-wrap:wrap}figure{margin:0}"
        "img{width:240px;border:1px solid #ccc;border-radius:6px}figcaption{font-size:12px;color:#555}"
        "</style>",
        f"<h1>AnywhereLLM audit</h1><p>{html.escape(manifest['commit'])}"
        f"{' (uncommitted changes)' if manifest['dirty'] else ''} &middot; "
        f"{html.escape(manifest['device']['model'])}, API {manifest['device']['api']}, "
        f"{manifest['device']['size']} &middot; {manifest['date']}</p>",
        f"<p>{manifest['summary']}</p>",
    ]
    for s in rows:
        bad = s["status"] != "ok" or s["findings"]
        parts.append(f"<section><h2 class={'bad' if bad else 'ok'}>{html.escape(s['group'])} / {html.escape(s['name'])}</h2><div class=row>")
        for shot in s["shots"]:
            parts.append(
                f"<figure><a href='{shot['file']}'><img loading=lazy src='{shot['file']}'></a>"
                f"<figcaption>{html.escape(shot['file'])}</figcaption></figure>"
            )
        parts.append("</div>")
        if s["status"] != "ok":
            parts.append(f"<p class=bad>{html.escape(s.get('error', ''))}</p>")
        if s["findings"]:
            parts.append(f"<p class=bad>{html.escape(json.dumps(s['findings']))}</p>")
        parts.append("</section>")
    for skip in manifest["skipped"]:
        parts.append(f"<p>Skipped {html.escape(skip['name'])}: {html.escape(skip['reason'])}</p>")
    return "\n".join(parts)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--avd", help="the AVD to boot when no emulator is running (default: the first)")
    p.add_argument("--serial", help="the emulator to use, such as emulator-5554")
    p.add_argument("--headless", action="store_true", help="boot without a window")
    p.add_argument("--themes", default="light,dark", help="comma list of light, dark")
    p.add_argument("--only", help="comma list; runs steps whose name or group contains one")
    p.add_argument("--no-build", action="store_true", help="install the APKs from the last run")
    p.add_argument("--keep-emulator", action="store_true", help="leave an emulator this tool booted running")
    p.add_argument("--out", type=Path, default=ROOT / "build/audit", help="where the folder and zip go")
    p.add_argument("--dump", action="store_true", help="print the labels on the screen now and exit")
    p.add_argument("--try", dest="try_", metavar="ACTIONS",
                   help="launch, run these actions (separated by ';') and print the labels, to write steps")
    args = p.parse_args()

    device, booted = open_device(args.serial, args.avd, args.headless, "the audit replaces the installed app")
    if args.dump or args.try_:
        if args.try_:
            walk = Walk(device, Path(tempfile.gettempdir()), [])
            walk.launch()
            for action in args.try_.split(";"):
                walk.do(action.strip())
        print_labels(device)
        return 0

    plan = tomllib.loads((HERE / "steps.toml").read_text())
    starts = plan.get("from", {})
    themes = args.themes.split(",")
    only = [s for s in (args.only or "").split(",") if s]
    steps = []
    for i, step in enumerate(plan["step"], 1):
        step["index"] = i
        if not only or any(o in step["name"] or o in step["group"] for o in only):
            steps.append(step)

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    commit = git("rev-parse", "--short", "HEAD") or "nogit"
    folder = args.out / f"anywherellm-audit-{commit}-{stamp}"
    folder.mkdir(parents=True)
    apks = {}
    for signed_out in {bool(s.get("signed_out")) for s in steps}:
        apks[signed_out] = args.out / ("app-signed-out.apk" if signed_out else "app.apk")
        if not args.no_build:
            build(signed_out, apks[signed_out])
        elif not apks[signed_out].exists():
            sys.exit(f"{apks[signed_out]} does not exist; run once without --no-build")
    before = steady(device)
    walk = Walk(device, folder, themes)
    results = []
    try:
        for signed_out, apk in apks.items():
            install(device, apk)
            for step in (s for s in steps if bool(s.get("signed_out")) == signed_out):
                print(f"{step['group']}/{step['name']}", end=" ", flush=True)
                record = walk.run(step, starts.get(step.get("from"), []) + step["do"])
                print(record["status"], record["findings"] or "")
                results.append(record)
    finally:
        restore(device, before)
        close_device(device, booted, args.keep_emulator)

    failed = [r for r in results if r["status"] != "ok"]
    noted = [r for r in results if r["findings"]]
    unlabelled = sum(s["unlabelled"] for r in results for s in r["shots"])
    manifest = {
        "commit": commit,
        "dirty": bool(git("status", "--porcelain")),
        "date": datetime.now().isoformat(timespec="seconds"),
        "device": {
            "serial": device.serial,
            "model": device.prop("ro.product.model"),
            "api": device.prop("ro.build.version.sdk"),
            "size": f"{device.size[0]}x{device.size[1]} @ {device.shell('wm density').split()[-1]} dpi",
        },
        "themes": themes,
        "summary": f"{len(results)} steps in {' and '.join(themes)}, {len(failed)} failed, "
                   f"{len(noted)} with log findings, "
                   f"{unlabelled} unlabelled controls",
        "skipped": plan.get("skipped", []),
        "steps": results,
    }
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2))
    (folder / "index.html").write_text(contact_sheet(manifest))
    archive = shutil.make_archive(str(folder), "zip", folder.parent, folder.name)
    print(manifest["summary"])
    print(archive)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
