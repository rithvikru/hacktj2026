from __future__ import annotations

import json
import shutil
import ssl
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path


DEFAULT_TIMEOUT_SECONDS = 60
CHUNK_SIZE = 1024 * 1024


@dataclass(slots=True)
class DownloadResult:
    source_url: str
    resolved_url: str
    destination: Path
    bytes_written: int
    used_http_fallback: bool


def ensure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def relative_to(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def resolve_coco_url(url: str, *, allow_http_fallback: bool) -> tuple[str, bool]:
    if not allow_http_fallback:
        return url, False
    if not url.startswith("https://images.cocodataset.org/"):
        return url, False
    return url.replace("https://", "http://", 1), True


def download_file(
    url: str,
    destination: Path,
    *,
    overwrite: bool = False,
    allow_http_fallback: bool = False,
) -> DownloadResult:
    if destination.exists() and not overwrite:
        return DownloadResult(
            source_url=url,
            resolved_url=url,
            destination=destination,
            bytes_written=destination.stat().st_size,
            used_http_fallback=False,
        )

    ensure_directory(destination.parent)
    request_url = url
    used_http_fallback = False

    try:
        return _download_file_once(
            source_url=url,
            request_url=request_url,
            destination=destination,
            used_http_fallback=used_http_fallback,
        )
    except urllib.error.URLError as exc:
        should_fallback = isinstance(exc.reason, ssl.SSLCertVerificationError)
        if not should_fallback or not allow_http_fallback:
            raise
        request_url, used_http_fallback = resolve_coco_url(url, allow_http_fallback=True)
        return _download_file_once(
            source_url=url,
            request_url=request_url,
            destination=destination,
            used_http_fallback=used_http_fallback,
        )


def _download_file_once(
    *,
    source_url: str,
    request_url: str,
    destination: Path,
    used_http_fallback: bool,
) -> DownloadResult:
    temporary_path = destination.with_suffix(destination.suffix + ".part")
    bytes_written = 0
    with urllib.request.urlopen(request_url, timeout=DEFAULT_TIMEOUT_SECONDS) as response:
        with temporary_path.open("wb") as handle:
            while True:
                chunk = response.read(CHUNK_SIZE)
                if not chunk:
                    break
                handle.write(chunk)
                bytes_written += len(chunk)
    temporary_path.replace(destination)
    return DownloadResult(
        source_url=source_url,
        resolved_url=request_url,
        destination=destination,
        bytes_written=bytes_written,
        used_http_fallback=used_http_fallback,
    )


def probe_url(url: str, *, allow_http_fallback: bool = False) -> tuple[str, int, bool]:
    try:
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request, timeout=DEFAULT_TIMEOUT_SECONDS) as response:
            return url, response.status, False
    except urllib.error.URLError as exc:
        should_fallback = isinstance(exc.reason, ssl.SSLCertVerificationError)
        if not should_fallback or not allow_http_fallback:
            raise
        fallback_url, used_http_fallback = resolve_coco_url(url, allow_http_fallback=True)
        request = urllib.request.Request(fallback_url, method="HEAD")
        with urllib.request.urlopen(request, timeout=DEFAULT_TIMEOUT_SECONDS) as response:
            return fallback_url, response.status, used_http_fallback


def extract_zip(archive_path: Path, destination_dir: Path, *, overwrite: bool = False) -> None:
    ensure_directory(destination_dir)
    with zipfile.ZipFile(archive_path) as archive:
        for member in archive.infolist():
            output_path = destination_dir / member.filename
            if output_path.exists() and not overwrite:
                continue
            archive.extract(member, path=destination_dir)


def write_json(path: Path, payload: dict) -> None:
    ensure_directory(path.parent)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)


def copy_file(source: Path, destination: Path, *, overwrite: bool = False) -> None:
    ensure_directory(destination.parent)
    if destination.exists() and not overwrite:
        return
    shutil.copy2(source, destination)
