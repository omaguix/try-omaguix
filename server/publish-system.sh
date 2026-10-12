#!/bin/bash
# The builder VM fallback for roguixos/roguix's CI
# (docs/decisions/0005-who-builds-roguix-substitutes.md): build the aarch64
# reference system and publish on roguix.frolow.dev the package items neither
# bordeaux nor roguix.frolow.dev serves yet (server/README.md, "Publishing").
# The split is CI's own, roguix's scripts/desktop-split with its licence
# collector at ROGUIX_SCRIPTS_COMMIT, so both paths apply the same checks.
# Needs the builder VM (guest/guix/vm-run).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
export_dir=.build/guix-validation/export
commit=$(cat guest/guix/modules/roguix/guix-commit)
# roguixos/roguix's scripts; moving this pin is a reviewed change
# (docs/decisions/0006-one-roguix-release-step.md).
ROGUIX_SCRIPTS_COMMIT=e1e2d64f36bfd00cd020e2accab80aa14f321b60

mkdir -p "$export_dir/roguix-scripts"
for script in desktop-split reference-system-licenses.scm; do
  curl -fsSL -o "$export_dir/roguix-scripts/$script" \
    "https://raw.githubusercontent.com/roguixos/roguix/$ROGUIX_SCRIPTS_COMMIT/scripts/$script"
done
rm -f "$export_dir"/{closure,licenses,packages,package-closure,closure-status,vps-fetch,vps-has,publish}.txt

guest/guix/vm-run --poll 10 "set -e
cd /mnt/export
guix=\"guix time-machine --url=file:///root/guix.git --commit=$commit --\"
\$guix system build --no-grafts --system=aarch64-linux \
  -L /mnt/project/guest/guix/modules \
  -e '(@ (roguix system) %roguix-reference-system)' > /root/roguix-reference-outputs.txt
GUIX_SYSTEM=aarch64-linux \$guix repl -L /mnt/project/guest/guix/modules -- \
  roguix-scripts/reference-system-licenses.scm > licenses.txt
guix gc -R \$(cat /root/roguix-reference-outputs.txt) | sort -u > closure.txt
guix shell curl -- bash roguix-scripts/desktop-split /mnt/export"

if [[ ! -s $export_dir/publish.txt ]]; then
  echo "publish-system: nothing to publish"
  exit 0
fi

guest/guix/vm-run --poll 5 'cd /mnt/export && guix archive --export $(cat publish.txt) | zstd -T4 -12 -q > roguix.nar.zst'
server/publish.sh "$export_dir"
# HTTP status of each published item's narinfo on roguix.frolow.dev.
sed 's|/gnu/store/\([a-z0-9]*\)-.*|\1|' "$export_dir/publish.txt" |
  xargs -P 16 -I{} curl -s -o /dev/null -w 'served by roguix: %{http_code}\n' \
    'https://roguix.frolow.dev/{}.narinfo' | sort | uniq -c
rm -f "$export_dir/roguix.nar.zst"
