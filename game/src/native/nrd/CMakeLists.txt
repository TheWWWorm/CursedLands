cmake_minimum_required(VERSION 3.22)
project(path_nrd LANGUAGES CXX)
set(NRD_DIR "" CACHE PATH "NRD v4.18.0 checkout")
set(MATHLIB_DIR "" CACHE PATH "MathLib v11 checkout")
set(SHADERMAKE_DIR "" CACHE PATH "Pinned ShaderMake checkout (headers only)")
set(GODOTCPP_DIR "" CACHE PATH "Qualified godot-cpp checkout")
option(NRD_METADATA_ONLY "Build the host shader inventory tool only" OFF)

# Use the upstream sources unchanged. The renderer consumes separate SPIR-V
# files, so the CPU library needs neither embedded bytecode nor NRI.
configure_file(NRDConfig.hlsli "${NRD_DIR}/Shaders/NRDConfig.hlsli" COPYONLY)
add_library(nrd_cpu STATIC
  ${NRD_DIR}/Source/InstanceImpl.cpp ${NRD_DIR}/Source/Reblur.cpp
  ${NRD_DIR}/Source/Relax.cpp ${NRD_DIR}/Source/Sigma.cpp
  ${NRD_DIR}/Source/Reference.cpp ${NRD_DIR}/Source/Timer.cpp
  ${NRD_DIR}/Source/Wrapper.cpp)
target_include_directories(nrd_cpu PUBLIC ${NRD_DIR}/Include PRIVATE
  ${MATHLIB_DIR} ${SHADERMAKE_DIR} ${NRD_DIR}/Shaders)
target_compile_features(nrd_cpu PUBLIC cxx_std_17)
target_compile_definitions(nrd_cpu PUBLIC NRD_STATIC_LIBRARY=1 PRIVATE
  NRD_EMBEDS_SPIRV_SHADERS=0 NRD_EMBEDS_DXIL_SHADERS=0 NRD_EMBEDS_DXBC_SHADERS=0
  SPIRV_SREG_OFFSET=0 SPIRV_BREG_OFFSET=2 SPIRV_UREG_OFFSET=3 SPIRV_TREG_OFFSET=20
  NOMINMAX WIN32_LEAN_AND_MEAN USE_MONOTONIC_TIMER)
set_target_properties(nrd_cpu PROPERTIES POSITION_INDEPENDENT_CODE ON
  CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(nrd_cpu PRIVATE -mssse3)
endif()
if(MINGW)
  target_compile_options(nrd_cpu PRIVATE -include "${CMAKE_CURRENT_SOURCE_DIR}/mingw_math.hpp")
endif()

if(NRD_METADATA_ONLY)
  add_executable(nrd_shaders nrd_shaders.cpp)
  target_link_libraries(nrd_shaders PRIVATE nrd_cpu)
else()
  set(GODOTCPP_TARGET "template_release" CACHE STRING "" FORCE)
  set(GODOTCPP_API_VERSION "4.7" CACHE STRING "" FORCE)
  set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/build_profile.json" CACHE FILEPATH "" FORCE)
  set(GODOTCPP_USE_HOT_RELOAD OFF CACHE BOOL "" FORCE)
  add_subdirectory("${GODOTCPP_DIR}" godot-cpp)
  add_library(path_nrd SHARED path_nrd.cpp)
  target_link_libraries(path_nrd PRIVATE godot-cpp nrd_cpu)
  set_target_properties(path_nrd PROPERTIES PREFIX "lib" CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
  if(MINGW)
    target_link_options(path_nrd PRIVATE -static-libgcc -static-libstdc++ -static -Wl,--no-insert-timestamp)
  endif()
endif()
