#!/usr/bin/env python3
"""Package a built Guix EFI disk image as the launcher's guest artifact.

The raw image comes from build.py on a Linux Guix host (dereference its GC-root
symlink when copying it to the Mac). The output directory holds exactly
disk.raw.zst, guix-manifest.json and SHA256SUMS; it is written beside the
target and renamed into place only after a full validation, decompression
included.
"""

import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile

import artifact


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ZSTD = ROOT / "macos/.build/qemu-gpu-runtime/bin/zstd"


def _builder():
    spec = importlib.util.spec_from_file_location("guix_image_build", HERE / "build.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = _builder()


def guix_commit():
    return builder.COMMIT


def system_files_sha256(system=builder.SYSTEM, load_path=builder.LOAD_PATH):
    """Digest of the image's build inputs (build.py's `inputs`: the system
    definition and the files Git tracks under its load path), recorded as
    the packager declares them. Each file's executable bit counts, since
    Guix's recursive local-file keeps it."""
    digest = hashlib.sha256()
    try:
        files = builder.inputs(system, load_path)
    except ValueError as error:
        raise artifact.ArtifactError(str(error)) from None
    for name, path in sorted(files.items()):
        mode = "755" if path.stat().st_mode & 0o100 else "644"
        digest.update(f"{name}\0{mode}\0{artifact.sha256_file(path)}\n".encode())
    return digest.hexdigest()


def package(image, output, zstd, credentials, system=builder.SYSTEM,
            load_path=builder.LOAD_PATH):
    image = Path(image).resolve(strict=True)
    output = Path(output).absolute()
    if os.path.lexists(output):
        raise artifact.ArtifactError(f"output already exists; choose a new --output: {output}")
    if not Path(zstd).is_file():
        raise artifact.ArtifactError(f"zstd is missing; run `make runtime`: {zstd}")
    layout = artifact.inspect_disk(image)
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".guix-package.", dir=output.parent))
    try:
        compressed = staging / artifact.DISK
        raw_sha256 = artifact.compress_and_hash(image, compressed, zstd)
        manifest = artifact.manifest_for(layout, raw_sha256, compressed,
                                         guix_commit(),
                                         system_files_sha256(system, load_path),
                                         credentials)
        (staging / artifact.MANIFEST).write_text(artifact.canonical_json(manifest),
                                                 encoding="utf-8")
        (staging / artifact.SUMS).write_text(artifact.sums_text(staging),
                                             encoding="ascii")
        artifact.validate_artifacts(staging, zstd)
        for entry in staging.iterdir():
            entry.chmod(0o444)
        staging.chmod(0o755)  # mkdtemp creates it private
        os.rename(staging, output)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True,
                        help="raw efi-raw disk image produced by build.py")
    parser.add_argument("--output", type=Path, default=ROOT / "build/guix")
    parser.add_argument("--zstd", type=Path, default=ZSTD)
    parser.add_argument("--credentials", default="first-boot",
                        choices=sorted(artifact.CREDENTIALS),
                        help="how the guest gets its account's password "
                             "(artifact.CREDENTIALS; default: %(default)s)")
    parser.add_argument("--system", type=Path, default=builder.SYSTEM,
                        help="the system definition the image was built from "
                             "(build.py --system; default: %(default)s)")
    parser.add_argument("--load-path", type=Path, default=builder.LOAD_PATH,
                        help="its module directory (build.py --load-path; "
                             "default: %(default)s)")
    args = parser.parse_args()
    try:
        manifest = package(args.image, args.output, args.zstd, args.credentials,
                           args.system, args.load_path)
    except (OSError, artifact.ArtifactError) as error:
        parser.exit(1, f"guix-package: {error}\n")
    disk = manifest["disk"]
    print(f"Packaged {args.output}: {disk['bytes']} raw bytes "
          f"({disk['sha256']}), {disk['compressedBytes']} compressed")


if __name__ == "__main__":
    main()
