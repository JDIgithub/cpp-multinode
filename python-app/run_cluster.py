import os, ray
from ray.util.scheduling_strategies import NodeAffinitySchedulingStrategy

WHEEL_URL = os.environ["CPP_WHEEL_URL"]
print("Using C++ wheel:", WHEEL_URL)

# Only install the C++ wheel cluster-wide. Python app code is already on each node.
ray.init(address="auto", runtime_env={"pip": [WHEEL_URL]})

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
