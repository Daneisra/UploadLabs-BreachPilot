"""Build the mod zip into build/. Godot needs forward slashes in entry names, so zipfile is used directly."""
import json
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD_DIR = ROOT / "mods-unpacked" / "Daneisra-SmartAutomation"

manifest = json.loads((MOD_DIR / "manifest.json").read_text(encoding="utf-8"))
out = ROOT / "build" / f"Daneisra-SmartAutomation-{manifest['version_number']}.zip"
out.parent.mkdir(exist_ok=True)

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(MOD_DIR.rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(ROOT).as_posix())

with zipfile.ZipFile(out) as archive:
    print(out)
    print("\n".join(archive.namelist()))
