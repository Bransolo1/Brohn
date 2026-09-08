"""Verified immutable-byte preparation; Windows guards stay owned until release.

This process has no SQLite connection and cannot publish report metadata. It
copies complete expected bytes, atomically installs an absent content address,
then hashes through a Windows read handle denying both writes and deletion.
The parent must independently retain its job fence before committing metadata.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import time
import uuid

MAX_DOCUMENT = 1024 * 1024
BLOCK = 1024 * 1024


def require(ok, message):
    if not ok:
        raise ValueError(message)


def text(value, maximum=4096):
    return isinstance(value, str) and 0 < len(value.encode("utf-8")) <= maximum


def write_json(path, value):
    raw = json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode("utf-8")
    require(len(raw) <= MAX_DOCUMENT, "Publication control document exceeds its bound.")
    pending = path.with_name(path.name + "." + uuid.uuid4().hex + ".pending")
    try:
        with pending.open("xb") as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(pending, path)
    finally:
        pending.unlink(missing_ok=True)


def contained(root, path):
    require(path.is_absolute(), "Publication paths must be absolute.")
    normalized = Path(os.path.abspath(path))
    try:
        parts = normalized.relative_to(root).parts
    except ValueError:
        raise ValueError("Publication path leaves its workspace.") from None
    require(bool(parts), "Publication path cannot be the workspace root.")
    cursor = root
    for piece in parts:
        cursor = cursor / piece
        if cursor.exists() or cursor.is_symlink():
            info = cursor.lstat()
            require(not stat.S_ISLNK(info.st_mode) and not (getattr(info, "st_file_attributes", 0) & 0x400),
                    "Publication paths cannot traverse links or reparse points.")
    require(os.path.normcase(os.path.realpath(normalized)).startswith(os.path.normcase(str(root)) + os.sep),
            "Publication path resolves outside its workspace.")
    return normalized


class FileInformation(ctypes.Structure):
    _fields_ = [("attributes", wintypes.DWORD), ("creation", wintypes.FILETIME),
                ("access", wintypes.FILETIME), ("write", wintypes.FILETIME),
                ("volume", wintypes.DWORD), ("size_high", wintypes.DWORD),
                ("size_low", wintypes.DWORD), ("links", wintypes.DWORD),
                ("index_high", wintypes.DWORD), ("index_low", wintypes.DWORD)]


class WindowsReadSeal:
    def __init__(self, path):
        require(os.name == "nt", "Publication sealing is currently qualified only on Windows.")
        self.path = Path(path)
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self.kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                          wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        self.kernel.CreateFileW.restype = wintypes.HANDLE
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.kernel.GetFileInformationByHandle.argtypes = [wintypes.HANDLE, ctypes.POINTER(FileInformation)]
        self.kernel.ReadFile.argtypes = [wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD,
                                        ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
        self.kernel.GetFinalPathNameByHandleW.argtypes = [wintypes.HANDLE, wintypes.LPWSTR, wintypes.DWORD, wintypes.DWORD]
        self.kernel.GetFinalPathNameByHandleW.restype = wintypes.DWORD
        # GENERIC_READ, FILE_SHARE_READ only, OPEN_EXISTING, sequential scan.
        self.handle = self.kernel.CreateFileW(str(path), 0x80000000, 1, None, 3, 0x08000000, None)
        if self.handle == wintypes.HANDLE(-1).value:
            self.handle = None
            raise OSError(ctypes.get_last_error(), "Cannot acquire the immutable read seal.")
        try:
            resolved = ctypes.create_unicode_buffer(32768)
            n = self.kernel.GetFinalPathNameByHandleW(self.handle, resolved, len(resolved), 0)
            require(0 < n < len(resolved), "Cannot verify the held file path.")
            final = resolved.value
            if final.startswith("\\\\?\\"):
                final = final[4:]
            require(os.path.normcase(os.path.abspath(final)) == os.path.normcase(os.path.abspath(path)),
                    "Held file differs from the declared immutable path.")
            self.identity = self.information()
        except BaseException:
            self.close()
            raise

    def information(self):
        info = FileInformation()
        if not self.kernel.GetFileInformationByHandle(self.handle, ctypes.byref(info)):
            raise OSError(ctypes.get_last_error(), "Cannot inspect the held file identity.")
        require(not (info.attributes & (0x10 | 0x400)), "Held object is a directory or reparse point.")
        return {"volume": str(info.volume), "file_index": str((info.index_high << 32) | info.index_low),
                "bytes": (info.size_high << 32) | info.size_low, "links": info.links}

    def sha256(self, progress=None):
        digest = hashlib.sha256()
        buffer = ctypes.create_string_buffer(BLOCK)
        count = wintypes.DWORD()
        total = 0
        while True:
            if not self.kernel.ReadFile(self.handle, buffer, BLOCK, ctypes.byref(count), None):
                raise OSError(ctypes.get_last_error(), "Cannot verify bytes through their held handle.")
            if not count.value:
                break
            digest.update(buffer.raw[:count.value])
            total += count.value
            if progress:
                progress(total)
        require(self.information() == self.identity and total == self.identity["bytes"],
                "Held object identity or size changed during verification.")
        return digest.hexdigest()

    def close(self):
        if self.handle is not None:
            self.kernel.CloseHandle(self.handle)
            self.handle = None


def validate_request(request, request_path, receipt, status):
    require(os.name == "nt", "Publication sealing is currently qualified only on Windows.")
    require(isinstance(request, dict) and request.get("schema") == "brohn-publication-request/1.0", "Unsupported publication request.")
    root = Path(request["workspace_root"])
    require(root.is_absolute() and root.is_dir() and root == root.resolve(), "Workspace root is not canonical.")
    require(text(request.get("workspace_id"), 128) and isinstance(request.get("owner"), dict), "Publication ownership is absent.")
    owner = request["owner"]
    require(set(owner) == {"job_id", "worker", "attempt", "token", "nonce"} and
            all(text(owner.get(key), 256) for key in ("job_id", "worker", "token", "nonce")) and
            type(owner.get("attempt")) is int and owner["attempt"] > 0, "Publication attempt identity is invalid.")
    for path in (request_path, receipt, status):
        contained(root, path)
        require(path.parent == request_path.parent, "Control files must share this exact attempt directory.")
    require(request_path.parent.parent.name == "publication" and request_path.parent.parent.parent == root / "scratch",
            "Publication controls must use a private workspace scratch attempt.")
    specs = request.get("specifications")
    require(isinstance(specs, list) and 1 <= len(specs) <= 1024, "Publication needs one to 1,024 bounded artifacts.")
    seen = set()
    for item in specs:
        require(isinstance(item, dict) and set(item) == {"key", "kind", "path", "sha256", "bytes", "media_type"}, "Invalid publication specification.")
        require(text(item["key"], 256) and item["key"] not in seen and text(item["kind"], 96) and text(item["media_type"], 256), "Invalid artifact identity or media type.")
        require(isinstance(item["sha256"], str) and re.fullmatch("[a-f0-9]{64}", item["sha256"]) and
                type(item["bytes"]) in (int, float) and item["bytes"] == int(item["bytes"]) and 0 <= item["bytes"] <= 4 * 1024**3,
                "Invalid expected artifact hash or size.")
        source = contained(root, Path(item["path"]))
        require(source.is_file(), "Artifact source is unavailable.")
        seen.add(item["key"])
    require(sum(item["bytes"] for item in specs) <= 16 * 1024**3, "Publication exceeds its total byte bound.")
    return root, specs


def run(request_path, receipt_path, status_path):
    with request_path.open("rb") as request_file:
        raw = request_file.read(MAX_DOCUMENT + 1)
    require(len(raw) <= MAX_DOCUMENT, "Publication request exceeds its size bound.")
    request = json.loads(raw)
    root, specs = validate_request(request, request_path, receipt_path, status_path)
    request_hash = hashlib.sha256(raw).hexdigest()
    code_hash = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    seals, items = {}, []
    last_status = 0.0

    def progress(phase, index, count, force=False):
        nonlocal last_status
        now = time.monotonic()
        if force or now - last_status >= .5:
            write_json(status_path, {"schema": "brohn-publication-status/1.0", "phase": phase,
                       "request_sha256": request_hash, "artifact_index": index, "artifact_count": len(specs),
                       "processed_bytes": count, "pid": os.getpid()})
            last_status = now

    try:
        # Do not create bulk pending bytes until the parent has observed and
        # recorded this exact interpreter's identity. A crash during copying can
        # then be cleaned without inferring ownership from a dead PID or filename.
        progress("awaiting_owner", 0, 0, True)
        begin = sys.stdin.buffer.readline(MAX_DOCUMENT + 1)
        require(0 < len(begin) <= MAX_DOCUMENT, "The publication owner did not acknowledge this process.")
        acknowledgement = json.loads(begin)
        require(acknowledgement == {"request_sha256": request_hash, "nonce": request["owner"]["nonce"], "operation": "begin"},
                "The publication start acknowledgement does not match its owner.")
        for index, item in enumerate(specs, 1):
            source = contained(root, Path(item["path"]))
            destination = contained(root, root / "objects" / "sha256" / item["sha256"][:2] / item["sha256"])
            destination.parent.mkdir(parents=True, exist_ok=True)
            contained(root, destination)
            if item["sha256"] not in seals:
                if not destination.exists():
                    pending = request_path.parent / (uuid.uuid4().hex + ".object-pending")
                    try:
                        digest = hashlib.sha256()
                        total = 0
                        progress("copying", index, total, True)
                        with source.open("rb") as incoming, pending.open("xb") as outgoing:
                            while block := incoming.read(BLOCK):
                                total += len(block)
                                require(total <= item["bytes"], "Artifact source grew beyond its frozen byte count.")
                                outgoing.write(block)
                                digest.update(block)
                                progress("copying", index, total)
                            outgoing.flush()
                            os.fsync(outgoing.fileno())
                        require(total == item["bytes"] and digest.hexdigest() == item["sha256"], "Artifact source failed its frozen hash or size.")
                        contained(root, destination)
                        try:
                            # On Windows rename refuses an existing destination;
                            # a competing exact hash is verified below, never overwritten.
                            os.rename(pending, destination)
                        except OSError:
                            if not destination.is_file():
                                raise
                    finally:
                        pending.unlink(missing_ok=True)
                seal = WindowsReadSeal(destination)
                seals[item["sha256"]] = seal
                progress("verifying_sealed_bytes", index, 0, True)
                require(seal.identity["bytes"] == item["bytes"] and seal.sha256(lambda n: progress("verifying_sealed_bytes", index, n)) == item["sha256"],
                        "Existing or newly sealed object failed its content address.")
            seal = seals[item["sha256"]]
            require(seal.identity["bytes"] == item["bytes"], "Duplicate content address disagrees on byte count.")
            os.chmod(destination, stat.S_IREAD)
            items.append({key: item[key] for key in ("key", "kind", "sha256", "bytes", "media_type")} |
                         {"path": str(destination), "file_identity": seal.identity})
        receipt = {"schema": "brohn-publication-ready/1.0", "request_sha256": request_hash,
                   "implementation_sha256": code_hash, "workspace_root": str(root), "workspace_id": request["workspace_id"],
                   "owner": request["owner"], "pid": os.getpid(), "status": "sealed", "items": items,
                   "seal": "windows-share-read-deny-write-delete/1.0"}
        write_json(receipt_path, receipt)
        progress("sealed", len(specs), sum(item["bytes"] for item in specs), True)
        # EOF means the owning parent disconnected: release guards, never claim
        # SQL publication or remove shared content-addressed orphan bytes.
        line = sys.stdin.buffer.readline(MAX_DOCUMENT + 1)
        if line:
            require(len(line) <= MAX_DOCUMENT, "Publication release command exceeds its bound.")
            command = json.loads(line)
            require(command == {"request_sha256": request_hash, "nonce": request["owner"]["nonce"], "operation": "release"},
                    "Publication release does not belong to this attempt.")
        return 0
    finally:
        for seal in seals.values():
            try:
                os.chmod(seal.path, stat.S_IREAD)
            except OSError:
                pass
            seal.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--status", required=True, type=Path)
    args = parser.parse_args()
    try:
        return run(args.request, args.receipt, args.status)
    except Exception as error:
        # Status is written only beside the original caller-selected request.
        # No arbitrary request-specified file is used as an error destination.
        if args.status.parent == args.request.parent and args.request.is_file():
            try:
                write_json(args.status, {"schema": "brohn-publication-status/1.0", "phase": "failed",
                           "error": str(error)[:2000], "pid": os.getpid()})
            except OSError:
                pass
        print("Publication preparation failed: " + str(error)[:2000], file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
