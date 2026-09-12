#!/bin/bash
# HKZ: replace ONLY docker.network.dns list items (line-based, safe).
# Does not rewrite SSL or other sections.
set +e
CFG="/etc/pterodactyl/config.yml"
[ -f "$CFG" ] || exit 0

DNS1="${HKZ_DNS_1:-76.76.2.0}"
DNS2="${HKZ_DNS_2:-80.80.80.80}"
DNS3="${HKZ_DNS_3:-4.2.2.1}"
export DNS1 DNS2 DNS3 CFG

if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
import os, pathlib, re
cfg = pathlib.Path(os.environ["CFG"])
dns = [os.environ["DNS1"], os.environ["DNS2"], os.environ["DNS3"]]
lines = cfg.read_text(encoding="utf-8").splitlines(keepends=True)
out = []
i = 0
replaced = False
while i < len(lines):
    if re.match(r"^[ \t]*dns:[ \t]*$", lines[i]):
        indent = re.match(r"^([ \t]*)", lines[i]).group(1) or "    "
        item = indent + "  "
        out.append(f"{indent}dns:\n")
        for d in dns:
            out.append(f"{item}- {d}\n")
        i += 1
        while i < len(lines) and re.match(r"^[ \t]+-[ \t].*$", lines[i].rstrip("\n")):
            i += 1
        replaced = True
        continue
    out.append(lines[i])
    i += 1
text = "".join(out)
if not replaced:
    block = (
        "    dns:\n"
        f"      - {dns[0]}\n"
        f"      - {dns[1]}\n"
        f"      - {dns[2]}\n"
    )
    if re.search(r"(?m)^  network:\s*$", text):
        text = re.sub(r"(?m)^(  network:\s*\n)", r"\1" + block, text, count=1)
    elif re.search(r"(?m)^docker:\s*$", text):
        text = re.sub(r"(?m)^(docker:\s*\n)", r"\1  network:\n" + block, text, count=1)
cfg.write_text(text, encoding="utf-8")
PY
fi

docker network rm pterodactyl_nw >/dev/null 2>&1 || true
exit 0
