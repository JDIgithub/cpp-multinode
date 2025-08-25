cmake_minimum_required(VERSION 3.18)
project(cpp_addon_proj LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(pybind11 CONFIG REQUIRED)

pybind11_add_module(cpp_addon_core src/cpp/core.cpp)
set_target_properties(cpp_addon_core PROPERTIES OUTPUT_NAME "_core")

# Install the built .so inside the Python package directory
install(TARGETS cpp_addon_core DESTINATION cpp_addon)
