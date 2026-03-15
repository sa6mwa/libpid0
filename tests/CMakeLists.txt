include(FetchContent)

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
  pkg_check_modules(CMOCKA QUIET cmocka>=2.0)
endif()

if(CMOCKA_FOUND)
  add_library(pid0_cmocka INTERFACE)
  target_include_directories(pid0_cmocka SYSTEM INTERFACE ${CMOCKA_INCLUDE_DIRS})
  target_link_libraries(pid0_cmocka INTERFACE ${CMOCKA_LINK_LIBRARIES})
  target_link_options(pid0_cmocka INTERFACE ${CMOCKA_LDFLAGS_OTHER})
  set(PID0_CMOCKA_TARGET pid0_cmocka)
else()
  set(WITH_CMOCKERY_SUPPORT OFF CACHE BOOL "" FORCE)
  set(WITH_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(WITH_MALLOC_OVERRIDE OFF CACHE BOOL "" FORCE)
  set(WITH_STATIC_LIB ON CACHE BOOL "" FORCE)
  set(WITH_TESTS OFF CACHE BOOL "" FORCE)

  FetchContent_Declare(
    cmocka
    GIT_REPOSITORY https://gitlab.com/cmocka/cmocka.git
    GIT_TAG cmocka-2.0.2
    GIT_SHALLOW TRUE
  )
  FetchContent_MakeAvailable(cmocka)

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
endif()

add_executable(pid0-test-helper pid0_test_helper.c)
target_link_libraries(pid0-test-helper PRIVATE pid0::pid0)
target_include_directories(pid0-test-helper PRIVATE ${CMAKE_SOURCE_DIR}/src)
target_compile_options(pid0-test-helper PRIVATE -Wall -Wextra -Wpedantic)
target_link_libraries(pid0-test-helper PRIVATE util)
set_target_properties(
  pid0-test-helper
  PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)

add_executable(pid0-unit-tests pid0_unit_test.c)
target_link_libraries(pid0-unit-tests PRIVATE pid0::pid0 ${PID0_CMOCKA_TARGET})
target_include_directories(pid0-unit-tests PRIVATE ${CMAKE_SOURCE_DIR}/src)
target_compile_options(pid0-unit-tests PRIVATE -Wall -Wextra -Wpedantic)
set_target_properties(
  pid0-unit-tests
  PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)
add_test(NAME pid0-unit-tests COMMAND $<TARGET_FILE:pid0-unit-tests>)

add_executable(pid0-integration-tests pid0_integration_test.c)
target_link_libraries(pid0-integration-tests PRIVATE ${PID0_CMOCKA_TARGET})
target_compile_options(pid0-integration-tests PRIVATE -Wall -Wextra -Wpedantic)
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

add_test(NAME pid0-container-smoke-test COMMAND ${CMAKE_SOURCE_DIR}/scripts/container-smoke-test.sh)
set_tests_properties(pid0-container-smoke-test PROPERTIES SKIP_RETURN_CODE 77)
