"""Print only bundled privacy declarations and public app configuration."""
import json
import plistlib
from pathlib import Path

archive = Path("build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app")
if not archive.is_dir():
    raise SystemExit("The signed app archive was not found.")

lines = []
manifests = sorted(archive.rglob("PrivacyInfo.xcprivacy"))
if not manifests:
    raise SystemExit("No bundled privacy manifests were found.")
for path in manifests:
    lines.append(str(path.relative_to(archive)))
    with path.open("rb") as source:
        lines.append(json.dumps(plistlib.load(source), ensure_ascii=False, indent=2))

with (archive / "Info.plist").open("rb") as source:
    info = plistlib.load(source)
public_keys = ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
               "GADApplicationIdentifier", "GADDelayAppMeasurementInit",
               "NSUserTrackingUsageDescription")
lines.append(json.dumps({key: info.get(key) for key in public_keys}, indent=2))
report = "\n".join(lines) + "\n"
Path("build/ios/privacy-report.txt").write_text(report, encoding="utf-8")
print(report)
