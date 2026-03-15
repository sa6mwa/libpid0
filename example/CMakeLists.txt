add_executable(pid0-example main.c)

target_link_libraries(pid0-example PRIVATE pid0::pid0)
target_compile_options(pid0-example PRIVATE -Wall -Wextra -Wpedantic)

set_target_properties(
  pid0-example
  PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/example
)
