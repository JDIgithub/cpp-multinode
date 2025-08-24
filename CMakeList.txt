cmake_minimum_required(VERSION 3.18)
project(ray_cpp_demo_proj LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(pybind11 CONFIG REQUIRED)

pybind11_add_module(ray_cpp_demo_core src/cpp/core.cpp)
set_target_properties(ray_cpp_demo_core PROPERTIES OUTPUT_NAME "_core")
install(TARGETS ray_cpp_demo_core DESTINATION ray_cpp_demo)
