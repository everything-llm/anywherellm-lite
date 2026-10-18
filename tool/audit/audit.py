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
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
from collections.abc import Callable
from datetime import datetime
from pathlib import Path
from xml.etree import ElementTree

HERE = Path(__file__).parent
ROOT = HERE.parent.parent
PACKAGE = "local.anywherellm.lite"
ENTRYPOINT = "tool/audit_app.dart"
APK = ROOT / "build/app/outputs/flutter-apk/app-debug.apk"
SCALES = ("window_animation_scale", "transition_animation_scale", "animator_duration_scale")
# Lines in the log that an audit reader wants to see.
FINDINGS = {
    "overflow": re.compile(r"RenderFlex overflowed|overflowed by"),
    "exception": re.compile(r"EXCEPTION CAUGHT|FATAL EXCEPTION|Unhandled Exception"),
    "anr": re.compile(r"ANR in"),
}


class StepError(Exception):
    """A step could not do what it says; the walk goes on with the next step."""


def poll(test: Callable[[], object], seconds: float, every: float, failure: str) -> None:
    """Calls [test] every [every] seconds until it is true, or fails with [failure]."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        if test():
            return
        time.sleep(every)
    raise StepError(failure)


def sdk() -> Path:
    home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    return Path(home) if home else Path.home() / "Android/Sdk"


def tool(name: str, sub: str) -> str:
    return shutil.which(name) or str(sdk() / sub / name)


class Device:
    """One emulator, driven through adb."""

    def __init__(self, serial: str):
        self.serial = serial
        self.adb = tool("adb", "platform-tools")
        self.size = (0, 0)
        self.xml = ""  # the last dump's XML

    def run(self, *args: str, check: bool = True, timeout: float = 120, binary: bool = False):
        done = subprocess.run(
            [self.adb, "-s", self.serial, *args],
            capture_output=True, text=not binary, timeout=timeout,
        )
        if check and done.returncode != 0:
            raise StepError(f"adb {' '.join(args)}: {(done.stderr or done.stdout)!s:.500}")
        return done.stdout

    def shell(self, command: str, **kwargs) -> str:
        return self.run("shell", command, **kwargs)

    def night(self, mode: str) -> None:
        """Sets the device's dark theme: yes, no or auto."""
        self.shell(f"cmd uimode night {mode}", check=False)

    def prop(self, name: str) -> str:
        return self.shell(f"getprop {name}").strip()

    def screenshot(self, path: Path) -> None:
        png = self.run("exec-out", "screencap", "-p", binary=True)
        if not png.startswith(b"\x89PNG"):
            raise StepError("screencap returned no picture")
        path.write_bytes(png)

    def dump(self) -> list[dict]:
        """The nodes on screen: label, bounds, kind and whether they take a tap. A field's label
        is its hint while it is empty."""
        for _ in range(4):
            if "dumped" in self.shell("uiautomator dump /sdcard/audit.xml", check=False):
                break
            time.sleep(0.5)
        else:
            raise StepError("uiautomator could not dump the screen")
        self.xml = self.run("exec-out", "cat", "/sdcard/audit.xml")
        nodes = []
        w, h = self.size
        for node in ElementTree.fromstring(self.xml).iter("node"):
            m = re.match(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]", node.get("bounds", ""))
            if not m:
                continue
            l, t, r, b = map(int, m.groups())
            if r <= l or b <= t or r <= 0 or l >= w or b <= 0 or t >= h:
                continue
            nodes.append({
                "label": node.get("content-desc") or node.get("text") or node.get("hint") or "",
                "kind": node.get("class", "").rsplit(".", 1)[-1],
                "clickable": node.get("clickable") == "true",
                "package": node.get("package", ""),
                "box": (max(l, 0), max(t, 0), min(r, w), min(b, h)),
            })
        return nodes


def find(nodes: list[dict], wanted: str) -> dict | None:
    """The first node whose label is [wanted], tried exactly, ignoring case, as a start, then as
    a part."""
    labeled = [n for n in nodes if n["label"]]
    low = wanted.lower()
    for test in (
        lambda s: s == wanted,
        lambda s: s.lower() == low,
        lambda s: s.lower().startswith(low),
        lambda s: low in s.lower(),
    ):
        if hit := next((n for n in labeled if test(n["label"])), None):
            return hit
    return None


class Walk:
    """Runs steps on the device, taking each screenshot once in each of [themes]: the app follows
    the device's theme as it changes, so one walk serves them all."""

    def __init__(self, device: Device, out: Path, themes: list[str]):
        self.d = device
        self.out = out
        self.themes = themes
        self.theme = ""  # the device's theme, once this walk has set it
        self.step = {"index": 0, "name": "try"}
        self.shots: list[dict] = []
        # An input went in that the screen may still be answering. A dump waits for the screen
        # to settle (uiautomator waits for a second of quiet), so only an action that does not
        # dump first waits for it, in [settle].
        self.unsettled = False

    def stem(self) -> str:
        return f"{self.step['index']:02d}-{self.step['name']}"

    def use_theme(self, theme: str) -> bool:
        """Switches the device to [theme], and says whether it changed."""
        if theme == self.theme:
            return False
        self.d.night("yes" if theme == "dark" else "no")
        self.theme = theme
        return True

    def settle(self) -> None:
        if self.unsettled:
            time.sleep(0.6)
            self.unsettled = False

    def nodes(self) -> list[dict]:
        """The nodes on screen, once it has settled."""
        nodes = self.d.dump()
        self.unsettled = False
        return nodes

    def launch(self) -> None:
        self.d.shell(f"am force-stop {PACKAGE}")
        if self.themes:
            self.use_theme(self.themes[0])
        self.d.shell(f"monkey -p {PACKAGE} -c android.intent.category.LAUNCHER 1")

        def shows() -> bool:
            try:
                return any(n["package"] == PACKAGE and n["label"] for n in self.nodes())
            except StepError:
                return False

        poll(shows, 30, 0.5, "the app did not show anything within 30 s")
        self.unsettled = True

    def locate(self, wanted: str) -> dict:
        """The control labelled [wanted], scrolling up to four times to find it."""
        for _ in range(4):
            if node := find(self.nodes(), wanted):
                return node
            self.swipe("up")
        if node := find(self.nodes(), wanted):
            return node
        raise StepError(f"no control labelled {wanted!r}")

    def swipe(self, way: str) -> None:
        w, h = self.d.size
        x, y = w // 2, h // 2
        dx, dy = {"up": (0, -h // 4), "down": (0, h // 4), "left": (-w // 3, 0), "right": (w // 3, 0)}[way]
        self.d.shell(f"input swipe {x} {y} {x + dx} {y + dy} 250")
        self.unsettled = True

    def do(self, action: str) -> None:
        verb, _, arg = action.partition(" ")
        arg = arg.strip()
        match verb:
            case "tap" | "hold":
                l, t, r, b = self.locate(arg)["box"]
                x, y = (l + r) // 2, (t + b) // 2
                self.d.shell(f"input swipe {x} {y} {x} {y} {900 if verb == 'hold' else 40}")
                self.unsettled = True
            case "type":
                self.settle()
                self.d.shell("input text " + shlex.quote(arg.replace(" ", "%s")))
                time.sleep(0.4)
            case "swipe":
                self.settle()
                self.swipe(arg)
            case "wait":
                poll(lambda: find(self.nodes(), arg), 12, 0.6, f"{arg!r} never showed")
            case "sleep":
                time.sleep(float(arg))
                self.unsettled = False
            case "intent":
                self.settle()
                self.d.shell("am " + arg.replace("{pkg}", PACKAGE))
                time.sleep(1.5)
            case "shot":
                self.shoot(arg)
            case _:
                raise StepError(f"unknown action {action!r}")

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


def running_emulators() -> list[str]:
    out = subprocess.run([tool("adb", "platform-tools"), "devices"], capture_output=True, text=True).stdout
    return [line.split()[0] for line in out.splitlines()[1:] if line.startswith("emulator-") and "device" in line]


def boot(avd: str | None, headless: bool) -> tuple[str, subprocess.Popen]:
    emulator = tool("emulator", "emulator")
    if not avd:
        avds = subprocess.run([emulator, "-list-avds"], capture_output=True, text=True).stdout.split()
        if not avds:
            sys.exit("no emulator is running and no AVD exists; make one with avdmanager")
        avd = avds[0]
    args = [emulator, "-avd", avd, "-no-snapshot-save", "-no-audio", "-no-boot-anim"]
    if headless:
        args.append("-no-window")
    print(f"booting {avd}...")
    process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def booted() -> bool:
        if process.poll() is not None:
            sys.exit(f"the emulator exited with {process.returncode}")
        serials = running_emulators()
        return bool(serials) and Device(serials[0]).prop("sys.boot_completed") == "1"

    try:
        poll(booted, 300, 3, "the emulator did not boot within 5 minutes")
    except StepError as error:
        process.terminate()
        sys.exit(str(error))
    return running_emulators()[0], process


def build(signed_out: bool, target: Path) -> None:
    command = ["flutter", "build", "apk", "--debug", "-t", ENTRYPOINT, "--target-platform", "android-x64"]
    if signed_out:
        command.append("--dart-define=AUDIT_SIGNED_OUT=true")
    print("building:", " ".join(command))
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit(done.stdout[-3000:] + done.stderr[-3000:])
    shutil.copy(APK, target)


def install(device: Device, apk: Path) -> None:
    """Installs [apk] in place of whatever build is there; the fakes keep nothing worth keeping."""
    device.run("uninstall", PACKAGE, check=False)
    try:
        device.run("install", str(apk))
    except StepError as error:
        sys.exit(f"install failed: {error}")
    device.shell(f"pm grant {PACKAGE} android.permission.POST_NOTIFICATIONS", check=False)


def steady(device: Device) -> dict:
    """Animations off and the status bar fixed, so two runs of the same code draw the same
    pictures. Returns what to put back."""
    before = {k: device.shell(f"settings get global {k}").strip() for k in SCALES}
    for k in SCALES:
        device.shell(f"settings put global {k} 0")
    device.shell("settings put global sysui_demo_allowed 1", check=False)
    for extra in (
        "-e command enter",
        "-e command clock -e hhmm 1200",
        "-e command battery -e level 100 -e plugged false",
        "-e command network -e wifi show -e level 4",
        "-e command notifications -e visible false",
    ):
        device.shell(f"am broadcast -a com.android.systemui.demo {extra}", check=False)
    night = device.shell("cmd uimode night", check=False).strip().rsplit(" ", 1)[-1]
    return {"scales": before, "night": night}


def restore(device: Device, before: dict) -> None:
    for k, v in before["scales"].items():
        device.shell(f"settings put global {k} {v if v != 'null' else 1}", check=False)
    device.shell("am broadcast -a com.android.systemui.demo -e command exit", check=False)
    device.night(before["night"] if before["night"] in ("yes", "no") else "auto")


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

    booted = None
    serial = args.serial or next(iter(running_emulators()), None)
    if not serial:
        serial, booted = boot(args.avd, args.headless)
    device = Device(serial)
    if device.prop("ro.kernel.qemu") != "1":
        sys.exit(f"{serial} is not an emulator; the audit replaces the installed app")
    m = re.search(r"(\d+)x(\d+)", device.shell("wm size"))
    device.size = (int(m.group(1)), int(m.group(2)))
    if args.dump or args.try_:
        if args.try_:
            walk = Walk(device, Path(tempfile.gettempdir()), [])
            walk.launch()
            for action in args.try_.split(";"):
                walk.do(action.strip())
        for n in device.dump():
            if n["label"]:
                print(f"{n['kind']:<10} {'tap ' if n['clickable'] else '    '}{n['label']!r}  {n['box']}")
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
        if booted and not args.keep_emulator:
            device.run("emu", "kill", check=False)
            booted.wait(timeout=60)

    failed = [r for r in results if r["status"] != "ok"]
    noted = [r for r in results if r["findings"]]
    unlabelled = sum(s["unlabelled"] for r in results for s in r["shots"])
    manifest = {
        "commit": commit,
        "dirty": bool(git("status", "--porcelain")),
        "date": datetime.now().isoformat(timespec="seconds"),
        "device": {
            "serial": serial,
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
