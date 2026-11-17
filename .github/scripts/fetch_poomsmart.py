"""Download the newest rootful (iphoneos-arm) .deb of each package from PoomSmart's repo."""
import re
import sys
import urllib.request

REPO = "https://poomsmart.github.io/repo/"
# No com.ps.ytuhd: it links /usr/lib/libundirect.dylib, which exists only on
# jailbroken devices, so a sideloaded app crashes at launch.
PACKAGES = ["com.ps.youpip"]
ARCH = "iphoneos-arm"


def version_key(v):
    return [int(p) if p.isdigit() else 0 for p in re.split(r"[.\-+~:]", v)]


def main(out_dir):
    index = urllib.request.urlopen(REPO + "Packages").read().decode("utf-8", "replace")
    best = {}
    for block in re.split(r"\n\s*\n", index):
        f = dict(re.findall(r"^([A-Za-z-]+):\s*(.*)$", block, re.M))
        pkg = f.get("Package")
        if pkg not in PACKAGES or f.get("Architecture") != ARCH or "Filename" not in f:
            continue
        if pkg not in best or version_key(f["Version"]) > version_key(best[pkg]["Version"]):
            best[pkg] = f

    for pkg in PACKAGES:
        if pkg not in best:
            print(f"::warning::{pkg} not found in {REPO}")
            continue
        f = best[pkg]
        url = REPO + f["Filename"].lstrip("./")
        dest = f"{out_dir}/{pkg}_{f['Version']}.deb"
        urllib.request.urlretrieve(url, dest)
        print(f"ok   {pkg} {f['Version']} -> {dest}")


if __name__ == "__main__":
    main(sys.argv[1])
