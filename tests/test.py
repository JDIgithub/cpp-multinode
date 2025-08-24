import ray_cpp_demo as m

def test_message_returns_string():
    s = m.message()
    assert isinstance(s, str)
    assert "Hello" in s

def test_print_message_runs():
    # Should not raise
    m.print_message()
