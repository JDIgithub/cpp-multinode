#include <pybind11/pybind11.h>
#include <string>
#include <iostream>

namespace py = pybind11;

// Edit this message and rebuild to see it propagate cluster-wide
static const char* kMessage = "Hello from C++ --------------------------------------------";

std::string message() {
    return std::string(kMessage);
}

void print_message() {
    std::cout << "[C++] " << kMessage << std::endl;
    std::cout.flush();
}

PYBIND11_MODULE(_core, m) {
    m.doc() = "ray_cpp_demo C++ core";
    m.def("message", &message, "Return the C++ message");
    m.def("print_message", &print_message, "Print the message from C++");
}
