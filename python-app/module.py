def process_request(x: int):
    import cpp_addon as cpp  # from the wheel
    cpp.print_message()
    return {"x": x, "msg": cpp.message()}
