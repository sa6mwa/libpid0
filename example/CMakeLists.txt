add_executable(pid0-example main.c)

target_link_libraries(pid0-example PRIVATE pid0::pid0)
target_compile_options(pid0-example PRIVATE -Wall -Wextra -Wpedantic)

set_target_properties(
  pid0-example
  PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/example
)

add_executable(pid0-single-header-example single_header_main.c)
target_include_directories(
  pid0-single-header-example
  PRIVATE
    ${CMAKE_BINARY_DIR}/generated/include
)
target_compile_options(pid0-single-header-example PRIVATE -Wall -Wextra -Wpedantic)
add_dependencies(pid0-single-header-example package-single-header)
set_target_properties(
  pid0-single-header-example
  PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/example
)
