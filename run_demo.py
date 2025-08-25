import os, socket, time, sys
import ray
from ray.util.scheduling_strategies import NodeAffinitySchedulingStrategy

# Set this to the served wheel URL from your head node (step 3 in README).
# Example:
# WHEEL_URL = "http://10.0.1.40:8000/ray_cpp_demo-0.1.0-cp311-cp311-manylinux2014_x86_64.whl"
WHEEL_URL = os.environ.get("RAY_CPP_DEMO_WHEEL_URL", "http://10.0.1.40:7777/ray_cpp_demo-0.1.0-cp312-cp312-linux_x86_64.whl")

print(f"Using wheel: {WHEEL_URL}")

ray.init(address="auto", runtime_env={"pip": [f"ray-cpp-demo @ {WHEEL_URL}"]})

@ray.remote
class Printer:
    def __init__(self):
        import ray_cpp_demo as demo
        self.demo = demo

    def run(self):
        import socket
        host = socket.gethostname()
        # Print from C++ (goes to worker stdout/logs) and from Python
        self.demo.print_message()
        py_line = f"[py ] node={host} demo.message() -> {self.demo.message()}"
        print(py_line)
        return {"host": host, "cpp_message": self.demo.message(), "py_print": py_line}

# Spawn one actor per alive node via NodeAffinity
nodes = [n for n in ray.nodes() if n.get("Alive")]
print(f"Found {len(nodes)} nodes:")
for n in nodes:
    print(" -", n["NodeManagerAddress"], n["NodeID"])

actors = []
for n in nodes:
    node_id = n["NodeID"]
    strat = NodeAffinitySchedulingStrategy(node_id=node_id, soft=False)
    actors.append(Printer.options(scheduling_strategy=strat).remote())

results = ray.get([a.run.remote() for a in actors])

print("\n=== Driver summary ===")
for r in results:
    print(f"node={r['host']} cpp_message='{r['cpp_message']}'")
print("Done.")
