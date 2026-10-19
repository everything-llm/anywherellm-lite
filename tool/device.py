"""An Android emulator driven through adb, shared by `tool/audit` and `tool/e2e`.

A script under `tool/` imports it after putting this folder on `sys.path`. It finds or boots the
emulator, installs an APK, steadies the screen, and runs step actions that find each control by
its accessibility label, or an empty field by its hint.
"""

import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from collections.abc import Callable
from pathlib import Path
from xml.etree import ElementTree

PACKAGE = "local.anywherellm.lite"
SCALES = ("window_animation_scale", "transition_animation_scale", "animator_duration_scale")


class StepError(Exception):
    """A step could not do what it says."""


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
    """The node whose label is [wanted], tried exactly, ignoring case, as a start, then as a part.
    Of several that match alike, the last: it is drawn over the others, as a sheet's button is
    over the page's under its scrim."""
    labeled = [n for n in reversed(nodes) if n["label"]]
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


class Driver:
    """Runs step actions on the device. `{name}` in an action is replaced by [values]' `name`,
    and `{pkg}` by the app's id."""

    def __init__(self, device: Device, out: Path, values: dict[str, str] | None = None):
        self.d = device
        self.out = out
        self.values = {"pkg": PACKAGE, **(values or {})}
        # An input went in that the screen may still be answering. A dump waits for the screen
        # to settle (uiautomator waits for a second of quiet), so only an action that does not
        # dump first waits for it, in [settle].
        self.unsettled = False

    def settle(self) -> None:
        if self.unsettled:
            time.sleep(0.6)
            self.unsettled = False

    def nodes(self) -> list[dict]:
        """The nodes on screen, once it has settled."""
        nodes = self.d.dump()
        self.unsettled = False
        return nodes

    def before_launch(self) -> None:
        """What a walk does once the app has stopped and before it starts again."""

    def launch(self) -> None:
        self.d.shell(f"am force-stop {PACKAGE}")
        self.before_launch()
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
        for name, value in self.values.items():
            action = action.replace("{" + name + "}", value)
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
            case "key":
                self.settle()
                self.d.shell(f"input keyevent KEYCODE_{arg.upper()}")
                self.unsettled = True
            case "wait" | "gone":
                m = re.fullmatch(r"(.*) within (\d+) s", arg)
                label, seconds = (m.group(1), m.group(2)) if m else (arg, "12")
                shown = verb == "wait"
                poll(lambda: bool(find(self.nodes(), label)) == shown, float(seconds), 0.6,
                     f"{label!r} never {'showed' if shown else 'went'} within {seconds} s")
            case "sleep":
                time.sleep(float(arg))
                self.unsettled = False
            case "intent":
                self.settle()
                self.d.shell("am " + arg)
                time.sleep(1.5)
            case "shot":
                self.shoot(arg)
            case _:
                raise StepError(f"unknown action {action!r}")

    def shoot(self, name: str) -> None:
        """A screenshot and the screen's dump, named [name]."""
        self.nodes()
        (self.out / f"{name}.xml").write_text(self.d.xml)
        self.d.screenshot(self.out / f"{name}.png")


def running_emulators() -> list[str]:
    out = subprocess.run([tool("adb", "platform-tools"), "devices"], capture_output=True, text=True).stdout
    return [line.split()[0] for line in out.splitlines()[1:] if line.startswith("emulator-") and "device" in line]


def boot(avd: str | None, headless: bool, port: int | None = None, wipe: bool = False) -> tuple[str, subprocess.Popen]:
    """Boots [avd], or the first AVD, on [port] when it is given, from fresh data when [wipe]."""
    emulator = tool("emulator", "emulator")
    if not avd:
        avds = subprocess.run([emulator, "-list-avds"], capture_output=True, text=True).stdout.split()
        if not avds:
            sys.exit("no emulator is running and no AVD exists; make one with avdmanager")
        avd = avds[0]
    args = [emulator, "-avd", avd, "-no-snapshot-save", "-no-audio", "-no-boot-anim"]
    if headless:
        args.append("-no-window")
    if port:
        args += ["-port", str(port)]
    if wipe:
        args.append("-wipe-data")
    print(f"booting {avd}...")
    process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    mine = f"emulator-{port}" if port else None

    def serial() -> str | None:
        serials = running_emulators()
        return mine if mine in serials else None if mine else next(iter(serials), None)

    def booted() -> bool:
        if process.poll() is not None:
            sys.exit(f"the emulator exited with {process.returncode}")
        found = serial()
        return bool(found) and Device(found).prop("sys.boot_completed") == "1"

    try:
        poll(booted, 300, 3, "the emulator did not boot within 5 minutes")
    except StepError as error:
        process.terminate()
        sys.exit(str(error))
    return serial(), process


def open_device(serial: str | None, avd: str | None, headless: bool, why: str) -> tuple[Device, subprocess.Popen | None]:
    """The emulator [serial], else the first running, else one booted from [avd]; and the
    process when it was booted here. Refuses a real phone, naming [why]."""
    booted = None
    serial = serial or next(iter(running_emulators()), None)
    if not serial:
        serial, booted = boot(avd, headless)
    return ready(serial, why), booted


def own_device(avd: str, port: int, headless: bool, why: str) -> tuple[Device, subprocess.Popen | None]:
    """[avd] on [port], an emulator of this caller's own beside any other running: the one there,
    or booted afresh from wiped data; and the process when it was booted here."""
    serial = f"emulator-{port}"
    booted = None
    if serial not in running_emulators():
        serial, booted = boot(avd, headless, port=port, wipe=True)
    return ready(serial, why), booted


def ready(serial: str, why: str) -> Device:
    """The emulator [serial], with its screen's size. Refuses a real phone, naming [why]."""
    device = Device(serial)
    if device.prop("ro.kernel.qemu") != "1":
        sys.exit(f"{serial} is not an emulator; {why}")
    m = re.search(r"(\d+)x(\d+)", device.shell("wm size"))
    device.size = (int(m.group(1)), int(m.group(2)))
    return device


def close_device(device: Device, booted: subprocess.Popen | None, keep: bool) -> None:
    """Shuts down an emulator this run booted, unless [keep]."""
    if booted and not keep:
        device.run("emu", "kill", check=False)
        booted.wait(timeout=60)


def install(device: Device, apk: Path) -> None:
    """Installs [apk] in place of whatever build is there, with what it keeps."""
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


def print_labels(device: Device) -> None:
    """The labelled controls on screen, as a step names them."""
    for n in device.dump():
        if n["label"]:
            print(f"{n['kind']:<10} {'tap ' if n['clickable'] else '    '}{n['label']!r}  {n['box']}")
