#!/usr/bin/env python3
"""Copy and relink the native emulator runtime into a macOS app bundle."""

import pathlib
import shutil
import subprocess
import sys


def dependencies(binary: pathlib.Path) -> list[str]:
    output = subprocess.check_output(["otool", "-L", str(binary)], text=True)
    return [
        line.strip().split(" (compatibility version", 1)[0]
        for line in output.splitlines()[1:]
        if " (compatibility version" in line
    ]


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent
    frameworks = pathlib.Path(sys.argv[1]).resolve()
    frameworks.mkdir(parents=True, exist_ok=True)
    roots = [
        root / "src/cloudpilot/libcloudpilot-embed.dylib",
        pathlib.Path("/opt/homebrew/lib/libSDL3.dylib"),
    ]
    copied: dict[str, pathlib.Path] = {}
    queue: list[pathlib.Path] = []
    for source in roots:
        if not source.exists():
            raise SystemExit(f"Missing runtime library: {source}")
        target = frameworks / source.name
        target.unlink(missing_ok=True)
        shutil.copy2(source.resolve(), target)
        copied[target.name] = target
        queue.append(target)

    system_prefixes = ("/System/Library/", "/usr/lib/")
    while queue:
        binary = queue.pop()
        for dep in dependencies(binary):
            if dep == binary.name or dep == f"@rpath/{binary.name}":
                continue
            if dep.startswith(system_prefixes):
                continue
            name = pathlib.Path(dep).name
            if name in copied:
                continue
            if dep.startswith("@rpath/"):
                candidates = list(pathlib.Path("/opt/homebrew/opt").glob(f"*/lib/{name}"))
                candidates += list(pathlib.Path("/opt/homebrew/lib").glob(name))
                if not candidates:
                    raise SystemExit(f"Unable to resolve runtime library: {dep} (required by {binary})")
                source = candidates[0]
            elif dep.startswith("@loader_path/"):
                source = binary.parent / dep.removeprefix("@loader_path/")
            elif dep.startswith("@executable_path/"):
                source = frameworks.parent / "MacOS" / dep.removeprefix("@executable_path/")
            else:
                source = pathlib.Path(dep)
            if not source.resolve().exists():
                raise SystemExit(f"Missing dynamic library: {dep} (required by {binary})")
            target = frameworks / name
            target.unlink(missing_ok=True)
            shutil.copy2(source.resolve(), target)
            copied[name] = target
            queue.append(target)

    for binary in copied.values():
        for dep in dependencies(binary):
            name = pathlib.Path(dep).name
            if name in copied and not dep.startswith(system_prefixes) and dep != f"@rpath/{name}":
                subprocess.check_call(["install_name_tool", "-change", dep, f"@rpath/{name}", str(binary)])
        subprocess.run(["install_name_tool", "-id", f"@rpath/{binary.name}", str(binary)], check=False)
        subprocess.run(["install_name_tool", "-add_rpath", "@loader_path", str(binary)], check=False)
        subprocess.check_call(["codesign", "--force", "--sign", "-", str(binary)])


if __name__ == "__main__":
    main()
