"""Bounded, non-executing validation of a Brohn design ZIP into quarantine.

Only standard-library modules are used. No network or subprocess execution is
performed here. The R caller validates domain semantics before catalog writes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import sys
import unicodedata
import zipfile

ARCHIVE_LIMIT = 512 * 1024**2
EXPANDED_LIMIT = 2 * 1024**3
FILE_LIMIT = 512 * 1024**2
JSON_LIMIT = 16 * 1024**2
ENTRY_LIMIT = 10_000
RATIO_LIMIT = 100
VERSION = "brohn-study-package/1.0"
REQUIRED = {"design.json", "aoi.json", "recipes.json", "dependencies.json"}
FORMATS = {
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp",
    ".wav": "audio/wav", ".mp3": "audio/mpeg", ".ogg": "audio/ogg",
    ".mp4": "video/mp4", ".webm": "video/webm",
}


class InvalidPackage(ValueError):
    pass


def require(ok: bool, message: str) -> None:
    if not ok:
        raise InvalidPackage(message)


def strict_object(pairs):
    obj = {}
    for key, value in pairs:
        require(key not in obj, "Duplicate JSON object field: " + key)
        obj[key] = value
    return obj


def check_tree(value, depth=0):
    require(depth < 64, "JSON nesting exceeds 64 levels.")
    if isinstance(value, dict):
        for item in value.values():
            check_tree(item, depth + 1)
    elif isinstance(value, list):
        for item in value:
            check_tree(item, depth + 1)


def decode_json(data: bytes):
    require(len(data) <= JSON_LIMIT, "Package JSON exceeds 16 MiB.")
    result = json.loads(data.decode("utf-8"), object_pairs_hook=strict_object,
                        parse_constant=lambda _: (_ for _ in ()).throw(InvalidPackage("Nonfinite JSON value.")))
    check_tree(result)
    return result


def fields(value, names, description):
    require(isinstance(value, dict) and set(value) == set(names),
            description + " has missing or unsupported fields.")


def integer(value, minimum=0, maximum=FILE_LIMIT):
    return type(value) is int and minimum <= value <= maximum


def safe_name(name: str) -> str:
    require(isinstance(name, str) and 0 < len(name) <= 240, "Invalid ZIP entry name length.")
    require("\\" not in name and ":" not in name and "\x00" not in name,
            "ZIP paths cannot contain backslashes, drives, streams or nulls.")
    require(not name.startswith("/") and not name.endswith("/"),
            "ZIP entries must be relative regular files, not directories.")
    require(not any(ord(c) < 32 or ord(c) == 127 for c in name), "ZIP path contains a control character.")
    parts = name.split("/")
    require(all(p and p not in (".", "..") and p == p.rstrip(" .") for p in parts),
            "ZIP path contains traversal, empty or Windows-aliased components.")
    for part in parts:
        base = unicodedata.normalize("NFKC", part).split(".")[0].upper()
        require(not re.fullmatch(r"(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])", base),
                "ZIP path contains a reserved Windows device name.")
    require(not PurePosixPath(name).is_absolute(), "Absolute ZIP path is not allowed.")
    return unicodedata.normalize("NFC", name).casefold()


def permitted_name(name: str) -> bool:
    return name in REQUIRED | {"manifest.json"} or bool(
        re.fullmatch(r"assets/[0-9a-f]{64}\.(png|jpe?g|webp|wav|mp3|ogg|mp4|webm)", name))


def check_signature(path: Path, media_type: str) -> None:
    with path.open("rb") as stream:
        head = stream.read(4096)
    size = path.stat().st_size
    require(size > 0, "An included asset is empty.")
    # Reject nested archives/executables even if their extension is disguised.
    require(not head.startswith((b"MZ", b"\x7fELF", b"PK\x03\x04", b"PK\x05\x06")),
            "Executable or nested archive asset is not allowed.")
    valid = False
    if media_type == "image/png":
        valid = len(head) >= 24 and head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR"
        if valid:
            width, height = struct.unpack(">II", head[16:24])
            valid = 1 <= width <= 32768 and 1 <= height <= 32768 and width * height <= 100_000_000
    elif media_type == "image/jpeg":
        valid = head.startswith(b"\xff\xd8\xff")
    elif media_type == "image/webp":
        valid = head[:4] == b"RIFF" and head[8:12] == b"WEBP" and head[12:16] in (b"VP8 ", b"VP8L", b"VP8X")
    elif media_type == "audio/wav":
        valid = head[:4] == b"RIFF" and head[8:12] == b"WAVE"
    elif media_type == "audio/mpeg":
        valid = head.startswith(b"ID3") or (len(head) >= 2 and head[0] == 255 and head[1] & 0xE0 == 0xE0)
    elif media_type == "audio/ogg":
        valid = head.startswith(b"OggS")
    elif media_type == "video/mp4":
        valid = len(head) >= 12 and head[4:8] == b"ftyp"
    elif media_type == "video/webm":
        valid = head.startswith(b"\x1a\x45\xdf\xa3") and b"webm" in head[:512]
    require(valid, "Asset bytes do not match the supported " + media_type + " signature.")


def validate_manifest(manifest, names):
    fields(manifest, ("schema_version", "design_schema_version", "product", "exported_at", "source", "files", "rights"), "Manifest")
    require(manifest["schema_version"] == VERSION, "Unsupported Brohn package version.")
    require(manifest["design_schema_version"] == "brohn-design/1.0.0", "Unsupported design schema version.")
    require(manifest["product"] == "Brohn", "Unsupported package product.")
    require(isinstance(manifest["exported_at"], str) and len(manifest["exported_at"]) <= 80, "Invalid export time.")
    require(manifest["rights"] == "researcher_review_required", "Unsupported asset rights declaration.")
    fields(manifest["source"], ("study_id", "revision", "design_hash"), "Source lineage")
    require(isinstance(manifest["source"]["study_id"], str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,95}", manifest["source"]["study_id"]) is not None, "Invalid source study identity.")
    require(integer(manifest["source"]["revision"], 1, 2**31 - 1), "Invalid source revision.")
    require(isinstance(manifest["source"]["design_hash"], str) and re.fullmatch(r"[a-f0-9]{64}", manifest["source"]["design_hash"]) is not None, "Invalid source design hash.")
    require(isinstance(manifest["files"], list) and 4 <= len(manifest["files"]) < ENTRY_LIMIT, "Invalid manifest file count.")
    records = {}
    for record in manifest["files"]:
        fields(record, ("path", "sha256", "size", "media_type"), "Manifest file")
        name = record["path"]
        safe_name(name)
        require(name != "manifest.json" and permitted_name(name), "Manifest lists an unsupported file.")
        require(name not in records, "Manifest lists a duplicate file.")
        require(isinstance(record["sha256"], str) and re.fullmatch(r"[a-f0-9]{64}", record["sha256"]) is not None, "Invalid file hash.")
        require(integer(record["size"], 1), "Invalid manifest file size.")
        if name in REQUIRED:
            require(record["media_type"] == "application/json" and record["size"] <= JSON_LIMIT, "Invalid JSON file manifest.")
        else:
            suffix = Path(name).suffix
            require(record["media_type"] == FORMATS[suffix], "Asset media type does not match its extension.")
            require(Path(name).stem == record["sha256"], "Asset filename does not match its content hash.")
        records[name] = record
    require(REQUIRED.issubset(records), "Package is missing a required design document.")
    require(set(records) | {"manifest.json"} == set(names), "ZIP contains missing or unlisted files.")
    return records


def validate_directory(directory: Path):
    directory = directory.resolve(strict=True)
    all_files = list(directory.rglob("*"))
    require(not any(p.is_symlink() for p in all_files), "Package directory contains a symbolic link.")
    files = [p for p in all_files if p.is_file()]
    names = [p.relative_to(directory).as_posix() for p in files]
    require(len(names) <= ENTRY_LIMIT and len(set(names)) == len(names), "Invalid package entry count.")
    for name in names:
        safe_name(name)
        require(permitted_name(name), "Unsupported package file: " + name)
    manifest_path = directory / "manifest.json"
    require(manifest_path.exists() and manifest_path.stat().st_size <= JSON_LIMIT, "Missing or oversized manifest.")
    manifest = decode_json(manifest_path.read_bytes())
    records = validate_manifest(manifest, names)
    total = manifest_path.stat().st_size
    for name, record in records.items():
        path = directory / name
        require(path.stat().st_size == record["size"], "File size disagrees with manifest: " + name)
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            while block := stream.read(1024 * 1024):
                digest.update(block)
        require(digest.hexdigest() == record["sha256"], "File failed SHA-256 integrity: " + name)
        total += record["size"]
        require(total <= EXPANDED_LIMIT, "Expanded package exceeds 2 GiB.")
        if name in REQUIRED:
            decode_json(path.read_bytes())
        else:
            check_signature(path, record["media_type"])
    return manifest


def extra_fields_are_safe(data: bytes):
    position = 0
    while position < len(data):
        require(position + 4 <= len(data), "Malformed ZIP extra metadata.")
        field_id, length = struct.unpack_from("<HH", data, position)
        position += 4
        require(position + length <= len(data), "Truncated ZIP extra metadata.")
        # ZIP64 sizes and timestamps cannot redirect filesystem extraction.
        require(field_id in (0x0001, 0x5455), "Unsupported ZIP path/link metadata.")
        position += length


def check_archive_envelope(path: Path):
    size = path.stat().st_size
    require(22 <= size <= ARCHIVE_LIMIT, "Archive must be between 22 bytes and 512 MiB.")
    with path.open("rb") as stream:
        require(stream.read(4) in (b"PK\x03\x04", b"PK\x05\x06"), "Only a plain ZIP design package is accepted.")
        stream.seek(max(0, size - 65557))
        tail = stream.read()
    offset = tail.rfind(b"PK\x05\x06")
    require(offset >= 0 and offset + 22 <= len(tail), "ZIP directory terminator is missing.")
    end = struct.unpack_from("<4s4H2IH", tail, offset)
    require(end[1] == 0 and end[2] == 0 and end[3] == end[4], "Multi-disk ZIP is unsupported.")
    require(end[4] <= ENTRY_LIMIT, "ZIP has more than 10,000 entries.")
    require(offset + 22 + end[7] == len(tail), "Trailing or malformed ZIP content.")


def extract_validated(archive: Path, quarantine: Path):
    require(archive.is_file(), "Design package file does not exist.")
    require(not quarantine.exists() or (quarantine.is_dir() and not any(quarantine.iterdir())), "Quarantine must be a new empty directory.")
    require(not quarantine.is_symlink(), "Quarantine cannot be a symbolic link.")
    quarantine.mkdir(parents=False, exist_ok=True)
    quarantine = quarantine.resolve(strict=True)
    check_archive_envelope(archive)
    with zipfile.ZipFile(archive) as package:
        entries = package.infolist()
        require(len(entries) <= ENTRY_LIMIT, "ZIP entry limit exceeded.")
        names, normalized = [], set()
        declared_size = 0
        for entry in entries:
            require(entry.orig_filename == entry.filename, "ZIP entry contains an altered/null filename.")
            identity = safe_name(entry.filename)
            require(identity not in normalized, "ZIP path collision after case or Unicode normalization.")
            normalized.add(identity)
            require(permitted_name(entry.filename), "Unsupported ZIP file: " + entry.filename)
            require(not entry.is_dir() and stat.S_IFMT(entry.external_attr >> 16) in (0, stat.S_IFREG), "ZIP links and special files are not allowed.")
            require(not entry.flag_bits & 1, "Encrypted ZIP entries are not supported.")
            require(entry.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), "Unsupported ZIP compression.")
            extra_fields_are_safe(entry.extra)
            require(0 <= entry.file_size <= FILE_LIMIT, "ZIP entry exceeds 512 MiB.")
            require(entry.file_size <= RATIO_LIMIT * max(1, entry.compress_size), "ZIP expansion ratio exceeds 100:1.")
            if entry.filename.endswith(".json"):
                require(entry.file_size <= JSON_LIMIT, "JSON entry exceeds 16 MiB.")
            declared_size += entry.file_size
            require(declared_size <= EXPANDED_LIMIT, "Expanded package exceeds 2 GiB.")
            names.append(entry.filename)
        require("manifest.json" in names, "Package has no manifest.")
        # Reading the small manifest checks its CRC before extraction.
        manifest = decode_json(package.read("manifest.json"))
        records = validate_manifest(manifest, names)
        actual_total = 0
        for entry in entries:
            destination = quarantine.joinpath(*entry.filename.split("/"))
            destination.parent.mkdir(parents=True, exist_ok=True)
            require(destination.resolve().is_relative_to(quarantine), "ZIP destination leaves quarantine.")
            require(not destination.exists(), "ZIP would overwrite a quarantine file.")
            digest, actual = hashlib.sha256(), 0
            with package.open(entry) as source, destination.open("xb") as target:
                while block := source.read(1024 * 1024):
                    actual += len(block)
                    actual_total += len(block)
                    require(actual <= FILE_LIMIT and actual <= entry.file_size and actual_total <= EXPANDED_LIMIT, "Streamed ZIP data exceeds declared limits.")
                    digest.update(block)
                    target.write(block)
            require(actual == entry.file_size, "Streamed ZIP size is inconsistent.")
            if entry.filename != "manifest.json":
                expected = records[entry.filename]
                require(actual == expected["size"] and digest.hexdigest() == expected["sha256"], "ZIP file failed size/hash integrity: " + entry.filename)
        # Includes signatures and strict duplicate-field/nonfinite JSON handling.
        validate_directory(quarantine)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    extracting = sub.add_parser("extract")
    extracting.add_argument("--archive", required=True)
    extracting.add_argument("--quarantine", required=True)
    directory = sub.add_parser("validate-directory")
    directory.add_argument("--directory", required=True)
    args = parser.parse_args()
    try:
        if args.command == "extract":
            result = extract_validated(Path(args.archive), Path(args.quarantine))
        else:
            result = validate_directory(Path(args.directory))
        print(json.dumps({"status": "validated", "schema_version": result["schema_version"], "files": len(result["files"])}))
        return 0
    except (InvalidPackage, OSError, ValueError, RuntimeError, zipfile.BadZipFile, UnicodeError, RecursionError) as error:
        print(json.dumps({"status": "rejected", "error": str(error)[:1800]}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
