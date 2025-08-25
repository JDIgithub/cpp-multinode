import os, socket

def process_request(worker_num: int):
    # Import the C++ addon on the worker
    import cpp_addon as cpp

    host = socket.gethostname()

    # C++ print
    cpp.print_message()

    # Python print
    print("Hello From Python", flush=True)

    return {"worker_num": worker_num, "host": host}
