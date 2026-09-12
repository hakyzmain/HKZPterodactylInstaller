#!/bin/bash
# HKZ: fix Wings config before start.
# Panel auto-deploy resets docker.network.dns to 1.1.1.1 / 1.0.0.1 which often fail on RU VPS.
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
text = cfg.read_text(encoding="utf-8")

# --- Docker DNS ---
text = re.sub(
    r"(?ms)^[ \t]*dns:[ \t]*\n(?:[ \t]*-[ \t]*.*\n)+",
    "",
    text,
    count=1,
)
block = (
    "    dns:\n"
    f"      - {os.environ['DNS1']}\n"
    f"      - {os.environ['DNS2']}\n"
    f"      - {os.environ['DNS3']}\n"
)
if re.search(r"(?m)^  network:\s*$", text):
    text = re.sub(r"(?m)^(  network:\s*\n)", r"\1" + block, text, count=1)
elif re.search(r"(?m)^docker:\s*$", text):
    text = re.sub(r"(?m)^(docker:\s*\n)", r"\1  network:\n" + block, text, count=1)
else:
    text = text.rstrip() + "\n\ndocker:\n  network:\n" + block

# --- SSL: if LE cert exists, force enable ---
cert_m = re.search(r"(?m)^[ \t]*cert:[ \t]*(.+)$", text)
cert_path = cert_m.group(1).strip().strip("'\"") if cert_m else ""
key_path = ""
if not cert_path or not pathlib.Path(cert_path).is_file():
    live = pathlib.Path("/etc/letsencrypt/live")
    if live.is_dir():
        for d in sorted(live.iterdir()):
            fc = d / "fullchain.pem"
            pk = d / "privkey.pem"
            if fc.is_file() and pk.is_file() and d.name != "README":
                cert_path = str(fc)
                key_path = str(pk)
                break
else:
    key_path = str(pathlib.Path(cert_path).with_name("privkey.pem"))
    if not pathlib.Path(key_path).is_file():
        key_path = cert_path.replace("fullchain.pem", "privkey.pem")

if cert_path and pathlib.Path(cert_path).is_file() and key_path and pathlib.Path(key_path).is_file():
    lines = text.splitlines(keepends=True)
    in_api = False
    ssl_start = ssl_end = api_idx = port_idx = None
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(r"^api:\s*$", line):
            in_api, api_idx = True, i
            i += 1
            continue
        if in_api:
            if re.match(r"^[a-zA-Z]", line):
                in_api = False
            elif re.match(r"^  ssl:\s*$", line):
                ssl_start = i
                i += 1
                while i < len(lines) and (lines[i].startswith("    ") or lines[i].strip() == ""):
                    i += 1
                ssl_end = i
                continue
            elif re.match(r"^  port:", line):
                port_idx = i
        i += 1
    new_ssl = [
        "  ssl:\n",
        "    enabled: true\n",
        f"    cert: {cert_path}\n",
        f"    key: {key_path}\n",
    ]
    if ssl_start is not None:
        lines = lines[:ssl_start] + new_ssl + lines[ssl_end:]
    elif port_idx is not None:
        lines = lines[: port_idx + 1] + new_ssl + lines[port_idx + 1 :]
    elif api_idx is not None:
        lines = lines[: api_idx + 1] + new_ssl + lines[api_idx + 1 :]
    text = "".join(lines)

cfg.write_text(text, encoding="utf-8")
PY
fi

docker network rm pterodactyl_nw >/dev/null 2>&1 || true
exit 0
