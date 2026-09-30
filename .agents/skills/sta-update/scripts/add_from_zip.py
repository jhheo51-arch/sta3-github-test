#!/usr/bin/env python3
"""Compare course ZIP contents and optionally add missing files only."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tempfile
import zipfile


DAY = re.compile(r"day\d+(?:[-_].+)?\Z")
GENERATED = {"output", "projects", "site", "my-game", "tetris"}
IGNORED = {".git", "__MACOSX", ".DS_Store", "node_modules", ".venv", "__pycache__"}


def safe_parts(name):
    parts = PurePosixPath(name).parts
    if not parts or name.startswith("/") or "\\" in name or ".." in parts or any(":" in p for p in parts):
        raise ValueError(f"허용되지 않은 ZIP 경로: {name}")
    return parts


def allowed(parts):
    if not parts or any(p in IGNORED for p in parts):
        return False
    if any(p == "작업일지.md" or (p.startswith(".env") and p != ".env.example") for p in parts):
        return False
    course = bool(DAY.fullmatch(parts[0])) and len(parts) >= 2
    skill = len(parts) >= 4 and parts[:2] == (".agents", "skills")
    if not (course or skill):
        return False
    return not any(p in GENERATED for p in parts[:-1]) or parts[-1] == ".gitkeep"


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.digest()


def blocked(target, relative):
    current = target
    for part in relative.parts[:-1]:
        current = current / part
        if current.is_symlink() or (current.exists() and not current.is_dir()):
            return True
    destination = target / relative
    return destination.is_symlink() or (destination.exists() and not destination.is_file())


def update(archive_path, target, apply=False, source_root=None):
    target = Path(target).resolve(strict=True)
    if not target.is_dir():
        raise ValueError("현재 실습 폴더 경로가 필요합니다.")
    result = {key: [] for key in ("add", "changed", "same", "blocked", "excluded", "added")}
    with zipfile.ZipFile(archive_path) as archive, tempfile.TemporaryDirectory(prefix="sta-update-") as temporary:
        entries = []
        seen = set()
        for info in archive.infolist():
            parts = safe_parts(info.filename)
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError(f"ZIP의 심볼릭 링크는 지원하지 않습니다: {info.filename}")
            if info.is_dir():
                continue
            if parts in seen:
                raise ValueError(f"ZIP에 같은 경로가 중복되어 있습니다: {info.filename}")
            seen.add(parts)
            entries.append((info, parts))
        useful = [p for _, p in entries if not any(v in IGNORED for v in p)]
        prefix = safe_parts(source_root) if source_root else ()
        if not source_root:
            # Strip a single wrapper folder, retaining actual day/skill roots.
            roots = {p[0] for p in useful}
            if len(roots) == 1:
                root = next(iter(roots))
                if root != ".agents" and not DAY.fullmatch(root) and all(len(p) > 1 for p in useful):
                    prefix = (root,)
        result["source_root"] = "/".join(prefix) or "."
        staged = {}
        for info, parts in entries:
            if parts[:len(prefix)] != prefix:
                result["excluded"].append(info.filename)
                continue
            relative_parts = parts[len(prefix):]
            if not allowed(relative_parts):
                result["excluded"].append(info.filename)
                continue
            relative = Path(*relative_parts)
            name = relative.as_posix()
            staging = Path(temporary) / relative
            staging.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as source, staging.open("xb") as destination:
                shutil.copyfileobj(source, destination)
            staged[name] = staging
            if blocked(target, relative):
                result["blocked"].append(name)
            elif (target / relative).exists():
                category = "same" if digest(target / relative) == digest(staging) else "changed"
                result[category].append(name)
            else:
                result["add"].append(name)
        if not staged:
            raise ValueError("추가 대상인 일자별 자료나 스킬이 없습니다. ZIP 구조와 --source-root를 확인하세요.")
        if apply:
            for name in result["add"]:
                relative = Path(name)
                destination = target / relative
                if blocked(target, relative) or destination.exists():
                    result["blocked"].append(name)
                    continue
                destination.parent.mkdir(parents=True, exist_ok=True)
                # Exclusive creation also prevents overwriting files created after comparison.
                try:
                    output = destination.open("xb")
                except FileExistsError:
                    result["blocked"].append(name)
                    continue
                try:
                    with output, staged[name].open("rb") as source:
                        shutil.copyfileobj(source, output)
                except BaseException:
                    destination.unlink()
                    raise
                result["added"].append(name)
    result["mode"] = "apply" if apply else "compare"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip_path", type=Path)
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--source-root", help="ZIP 내부의 수업 자료 루트 경로")
    args = parser.parse_args()
    try:
        result = update(args.zip_path, args.target, args.apply, args.source_root)
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
