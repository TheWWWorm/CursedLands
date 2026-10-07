cmake_minimum_required(VERSION 3.22)
project(terrain_search LANGUAGES CXX)
set(GODOTCPP_DIR "" CACHE PATH "Checkout of godot-cpp at the documented revision")
set(GODOTCPP_TARGET "template_release" CACHE STRING "" FORCE)
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "" FORCE)
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/build_profile.json" CACHE FILEPATH "" FORCE)
set(GODOTCPP_USE_HOT_RELOAD OFF CACHE BOOL "" FORCE)
add_subdirectory("${GODOTCPP_DIR}" godot-cpp)
add_library(terrain_search SHARED nav_kernel.cpp)
target_link_libraries(terrain_search PRIVATE godot-cpp)
target_compile_features(terrain_search PRIVATE cxx_std_17)
set_target_properties(terrain_search PROPERTIES PREFIX "lib" CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
if(MINGW)
  target_link_options(terrain_search PRIVATE -static-libgcc -static-libstdc++ -static)
endif()

# Keep build-machine paths out of distributable diagnostics and binaries.
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  # Match Godot's math on ARM as well as x86. Fusing multiply/add changes
  # intermediate rounding in interpolation and feeds different future state.
  target_compile_options(terrain_search PRIVATE -ffp-contract=off)
  target_compile_options(godot-cpp PRIVATE -ffp-contract=off)
  target_compile_options(terrain_search PRIVATE
    "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=src/native/source"
    "-ffile-prefix-map=${GODOTCPP_DIR}=godot-cpp"
    "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build/native")
  target_compile_options(godot-cpp PRIVATE
    "-ffile-prefix-map=${GODOTCPP_DIR}=godot-cpp"
    "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build/native")
endif()
if(MINGW)
  target_link_options(terrain_search PRIVATE -Wl,--no-insert-timestamp)
endif()
