#!/usr/bin/env python3
import argparse, hashlib, os, re, socket, sys, urllib.request
from pathlib import Path
import ray
from ray.util.scheduling_strategies import NodeAffinitySchedulingStrategy

def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1<<20), b""):
            h.update(chunk)
    return h.hexdigest()

@ray.remote(num_cpus=0)
def fetch(url: str, dst_dir: str, sha_exp: str) -> str:
    d = Path(dst_dir); d.mkdir(parents=True, exist_ok=True)
    fname = url.rsplit("/", 1)[-1]
    dst = d / fname

    # quick skip if already identical
    if dst.exists():
        try:
            if sha256_file(dst) == sha_exp:
                return f"{socket.gethostname()}: up-to-date ({dst})"
        except Exception:
            pass

    # download -> tmp -> verify -> move
    tmp = dst.with_suffix(".tmp")
    req = urllib.request.Request(url, headers={"User-Agent": "wheel-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r, open(tmp, "wb") as f:
        while True:
            b = r.read(1<<20)
            if not b: break
            f.write(b)

    if sha256_file(tmp) != sha_exp:
        try: tmp.unlink()
        except Exception: pass
        raise RuntimeError(f"{socket.gethostname()}: SHA mismatch for {dst.name}")

    tmp.replace(dst)

    # refresh convenience symlink
    try:
        m = re.search(r"-(cp\d+)-", fname)
        cp = m.group(1) if m else "cpXX"
        link = d / f"cpp_addon-latest-{cp}.whl"
        if link.exists() or link.is_symlink():
            link.unlink()
        link.symlink_to(dst.name)  # relative symlink
    except Exception:
        pass

    return f"{socket.gethostname()}: staged {dst}"

def main() -> int:
    ap = argparse.ArgumentParser(description="Distribute a wheel to all Ray nodes")
    ap.add_argument("--url", required=True, help="HTTP URL of the wheel")
    ap.add_argument("--dst", required=True, help="Destination dir on each node")
    ap.add_argument("--sha256", required=True, help="Expected SHA256 of the wheel")
    ap.add_argument("--show-nodes", action="store_true", help="Print Ray node list")
    args = ap.parse_args()

    ray.init(address="auto")
    nodes = [n for n in ray.nodes() if n.get("Alive")]
    if args.show_nodes:
        for n in nodes:
            print("Node:", n["NodeManagerAddress"], "Alive:", n["Alive"], "ID:", n["NodeID"])
    if not nodes:
        print("No alive Ray nodes. Start the cluster first.", file=sys.stderr)
        return 2

    # pin one fetch per node, to that node
    refs = []
    for n in nodes:
        strat = NodeAffinitySchedulingStrategy(node_id=n["NodeID"], soft=False)
        refs.append(fetch.options(scheduling_strategy=strat).remote(args.url, args.dst, args.sha256))

    for line in ray.get(refs):
        print(" -", line)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
