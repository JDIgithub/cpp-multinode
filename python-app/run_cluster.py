import os, sys, ray
from pathlib import Path
from ray.util.scheduling_strategies import NodeAffinitySchedulingStrategy

def pick_wheel_req() -> str:

    base = Path(os.environ.get("CPP_WHEEL_DIR", "/vllm-workspace/cpp-wheels"))
    tag = f"cp{sys.version_info.major}{sys.version_info.minor}"
    symlink = base / f"cpp_addon-latest-{tag}.whl"
    if symlink.exists():
        real = symlink.resolve()
        return str(real)
    raise FileNotFoundError(
        f"Wheel not found: {symlink}. Set CPP_WHEEL_DIR, stage wheels."
    )

wheel_req = pick_wheel_req()
print("Using C++ wheel requirement:", wheel_req)

# Only install the C++ wheel cluster-wide. Python app code is already on each node.
ray.init(address="auto", runtime_env={"pip": [wheel_req]})

@ray.remote
class NodeWorker:
    def run(self, i: int):
        import module as mod  # this file is present on each node
        return mod.process_request(i)

nodes = [n for n in ray.nodes() if n.get("Alive")]
actors = [
    NodeWorker.options(
        scheduling_strategy=NodeAffinitySchedulingStrategy(node_id=n["NodeID"], soft=False)
    ).remote()
    for n in nodes
]
print(ray.get([a.run.remote(i) for i, a in enumerate(actors, 1)]))
