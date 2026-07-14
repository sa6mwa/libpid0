include(FetchContent)

check_c_source_compiles(
  "
  #include <stdint.h>
  int main(void) {
    uintptr_t value = 0;
    return (int)value;
  }
  "
  PID0_HAS_UINTPTR_T
)
if(NOT PID0_HAS_UINTPTR_T)
  message(FATAL_ERROR "The selected C toolchain must provide uintptr_t for cmocka")
endif()

pid0_acquire_verified_archive(
  cmocka
  "https://cmocka.org/files/2.0/cmocka-2.0.2.tar.xz"
  "39f92f366bdf3f1a02af4da75b4a5c52df6c9f7e736c7d65de13283f9f0ef416"
  PID0_CMOCKA_ARCHIVE
)
pid0_stage_verified_archive(
  cmocka
  "2.0.2"
  "39f92f366bdf3f1a02af4da75b4a5c52df6c9f7e736c7d65de13283f9f0ef416"
  "${PID0_CMOCKA_ARCHIVE}"
  PID0_CMOCKA_SOURCE
)
set(WITH_CMOCKERY_SUPPORT OFF CACHE BOOL "" FORCE)
set(WITH_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WITH_MALLOC_OVERRIDE OFF CACHE BOOL "" FORCE)
set(WITH_STATIC_LIB ON CACHE BOOL "" FORCE)
set(WITH_TESTS OFF CACHE BOOL "" FORCE)
# Cmocka 2.0.2 probes this with CheckTypeSize.  Supply the result from the
# project-owned capability check so a clean configure does not depend on that
# upstream generated-source probe.
set(HAVE_UINTPTR_T TRUE)
set(UINTPTR_T "${CMAKE_SIZEOF_VOID_P}")
FetchContent_Declare(cmocka SOURCE_DIR "${PID0_CMOCKA_SOURCE}")
FetchContent_MakeAvailable(cmocka)
unset(UINTPTR_T)
unset(HAVE_UINTPTR_T)

if(TARGET cmocka::cmocka)
  set(PID0_CMOCKA_TARGET cmocka::cmocka)
elseif(TARGET cmocka)
  set(PID0_CMOCKA_TARGET cmocka)
elseif(TARGET cmocka-static)
  add_library(pid0_cmocka ALIAS cmocka-static)
  set(PID0_CMOCKA_TARGET pid0_cmocka)
else()
  message(FATAL_ERROR "Unable to determine the cmocka target name")
endif()
set(PID0_CMOCKA_SYSTEM_INCLUDE_DIR "${PID0_CMOCKA_SOURCE}/include")

add_executable(pid0-test-helper pid0_test_helper.c)
target_link_libraries(pid0-test-helper PRIVATE pid0::pid0)
target_include_directories(pid0-test-helper PRIVATE ${CMAKE_SOURCE_DIR}/src)
pid0_configure_c_executable(pid0-test-helper)
target_link_libraries(pid0-test-helper PRIVATE util)
set_target_properties(
  pid0-test-helper
  PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)

add_executable(pid0-unit-tests pid0_unit_test.c)
target_link_libraries(pid0-unit-tests PRIVATE pid0::pid0 ${PID0_CMOCKA_TARGET})
target_include_directories(pid0-unit-tests PRIVATE ${CMAKE_SOURCE_DIR}/src)
if(PID0_CMOCKA_SYSTEM_INCLUDE_DIR)
  target_include_directories(pid0-unit-tests SYSTEM PRIVATE ${PID0_CMOCKA_SYSTEM_INCLUDE_DIR})
endif()
target_compile_definitions(pid0-unit-tests PRIVATE inline=)
pid0_configure_c_executable(pid0-unit-tests)
set_target_properties(
  pid0-unit-tests
  PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)
add_test(NAME pid0-unit-tests COMMAND $<TARGET_FILE:pid0-unit-tests>)
set_tests_properties(pid0-unit-tests PROPERTIES LABELS "unit;local" TIMEOUT 10)

add_executable(pid0-single-header-unit-tests pid0_single_header_unit_test.c)
target_link_libraries(pid0-single-header-unit-tests PRIVATE ${PID0_CMOCKA_TARGET})
target_include_directories(
  pid0-single-header-unit-tests
  PRIVATE
    ${CMAKE_BINARY_DIR}/generated/include
)
if(PID0_CMOCKA_SYSTEM_INCLUDE_DIR)
  target_include_directories(pid0-single-header-unit-tests SYSTEM PRIVATE ${PID0_CMOCKA_SYSTEM_INCLUDE_DIR})
endif()
target_compile_definitions(pid0-single-header-unit-tests PRIVATE inline=)
pid0_configure_c_executable(pid0-single-header-unit-tests)
add_dependencies(pid0-single-header-unit-tests package-single-header)
set_target_properties(
  pid0-single-header-unit-tests
  PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)
add_test(
  NAME pid0-single-header-unit-tests
  COMMAND $<TARGET_FILE:pid0-single-header-unit-tests>
)
set_tests_properties(pid0-single-header-unit-tests PROPERTIES LABELS "unit;local" TIMEOUT 10)

add_test(
  NAME pid0-single-header-artifact-test
  COMMAND
    ${CMAKE_COMMAND}
      -DPID0_SINGLE_HEADER_BUILD=${PID0_SINGLE_HEADER_BUILD}
      -DPID0_SINGLE_HEADER_BUILD_ALIAS=${PID0_SINGLE_HEADER_BUILD_ALIAS}
      -DPID0_SINGLE_HEADER_DIST_GZ=${PID0_SINGLE_HEADER_DIST_GZ}
      -DPID0_VERSION=${PROJECT_VERSION}
      -P ${CMAKE_SOURCE_DIR}/tests/pid0_single_header_artifact_test.cmake
)
set_tests_properties(pid0-single-header-artifact-test PROPERTIES LABELS "packaging;local" TIMEOUT 10)

add_executable(pid0-integration-tests pid0_integration_test.c)
target_link_libraries(pid0-integration-tests PRIVATE ${PID0_CMOCKA_TARGET})
if(PID0_CMOCKA_SYSTEM_INCLUDE_DIR)
  target_include_directories(pid0-integration-tests SYSTEM PRIVATE ${PID0_CMOCKA_SYSTEM_INCLUDE_DIR})
endif()
target_compile_definitions(pid0-integration-tests PRIVATE inline=)
pid0_configure_c_executable(pid0-integration-tests)
target_compile_definitions(
  pid0-integration-tests
  PRIVATE
    PID0_TEST_HELPER_PATH="$<TARGET_FILE:pid0-test-helper>"
)
set_target_properties(
  pid0-integration-tests
  PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)
add_test(NAME pid0-integration-tests COMMAND $<TARGET_FILE:pid0-integration-tests>)
set_tests_properties(pid0-integration-tests PROPERTIES LABELS "integration;offline;local" TIMEOUT 20)

add_test(NAME pid0-container-smoke-test COMMAND ${CMAKE_SOURCE_DIR}/scripts/container-smoke-test.sh)
set_tests_properties(
  pid0-container-smoke-test
  PROPERTIES
    LABELS "example-smoke;local"
    SKIP_RETURN_CODE 77
    TIMEOUT 120
)

if(TARGET pid0-single-header-example)
  add_test(
    NAME pid0-single-header-example
    COMMAND
      ${CMAKE_COMMAND} -E env
        PID0_EXAMPLE_SLEEP_SECONDS=0
        $<TARGET_FILE:pid0-single-header-example>
        Example
  )
  set_tests_properties(pid0-single-header-example PROPERTIES LABELS "example-smoke;local" TIMEOUT 10)
endif()
