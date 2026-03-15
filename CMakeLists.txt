cmake_minimum_required(VERSION 3.28)

set(PID0_DEFAULT_VERSION "0.0.0")
set(PID0_PACKAGE_VERSION "${PID0_DEFAULT_VERSION}")

find_package(Git QUIET)
if(Git_FOUND)
  execute_process(
    COMMAND "${GIT_EXECUTABLE}" describe --tags --exact-match --match "v*" HEAD
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    RESULT_VARIABLE PID0_GIT_TAG_RESULT
    OUTPUT_VARIABLE PID0_GIT_TAG
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  if(PID0_GIT_TAG_RESULT EQUAL 0 AND PID0_GIT_TAG MATCHES "^v[0-9]+\\.[0-9]+\\.[0-9]+$")
    string(SUBSTRING "${PID0_GIT_TAG}" 1 -1 PID0_PACKAGE_VERSION)
  endif()
endif()

project(
  libpid0
  VERSION ${PID0_PACKAGE_VERSION}
  DESCRIPTION "Tiny PID1 helper for Linux containers and VMs"
  LANGUAGES C
)

include(GNUInstallDirs)
include(CheckCSourceCompiles)

option(PID0_BUILD_EXAMPLE "Build the example application" ON)
option(PID0_BUILD_TESTS "Build the test suite" ON)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_compile_definitions(_POSIX_C_SOURCE=200809L)

set(PID0_SOURCES src/pid0.c)
set(PID0_FORMAT_SOURCES
  include/pid0/pid0.h
  src/pid0.c
  src/pid0_internal.h
  example/main.c
  tests/pid0_integration_test.c
  tests/pid0_test_helper.c
  tests/pid0_unit_test.c
)

check_c_source_compiles(
  "
  #include <features.h>
  #ifdef __GLIBC__
  int main(void) { return 0; }
  #else
  #error not glibc
  #endif
  "
  PID0_USING_GLIBC
)

set(PID0_PACKAGE_LIBC "auto" CACHE STRING "libc ABI label for package naming")
set_property(CACHE PID0_PACKAGE_LIBC PROPERTY STRINGS auto musl gnu)

if(PID0_PACKAGE_LIBC STREQUAL "auto")
  if(PID0_USING_GLIBC)
    set(PID0_PACKAGE_LIBC_NAME "gnu")
  else()
    set(PID0_PACKAGE_LIBC_NAME "musl")
  endif()
else()
  set(PID0_PACKAGE_LIBC_NAME "${PID0_PACKAGE_LIBC}")
endif()

string(TOLOWER "${CMAKE_SYSTEM_NAME}" PID0_PACKAGE_OS)
set(PID0_PACKAGE_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
if(PID0_PACKAGE_ARCH STREQUAL "amd64")
  set(PID0_PACKAGE_ARCH "x86_64")
elseif(PID0_PACKAGE_ARCH MATCHES "^(x86_64|x64)$")
  set(PID0_PACKAGE_ARCH "x86_64")
elseif(PID0_PACKAGE_ARCH MATCHES "^(aarch64|arm64)$")
  set(PID0_PACKAGE_ARCH "aarch64")
elseif(PID0_PACKAGE_ARCH MATCHES "^(armhf|armv7l|armv7-a|arm)$")
  set(PID0_PACKAGE_ARCH "armhf")
endif()
set(PID0_PACKAGE_BASENAME
  "libpid0-${PROJECT_VERSION}-${PID0_PACKAGE_OS}-${PID0_PACKAGE_ARCH}-${PID0_PACKAGE_LIBC_NAME}"
)

function(pid0_configure_library target_name)
  target_include_directories(
    ${target_name}
    PUBLIC
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
      $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}/src
  )
  target_compile_options(${target_name} PRIVATE -Wall -Wextra -Wpedantic)
  target_compile_definitions(${target_name} PUBLIC _POSIX_C_SOURCE=200809L)
endfunction()

add_library(pid0_static STATIC ${PID0_SOURCES})
add_library(pid0_shared SHARED ${PID0_SOURCES})
add_library(pid0 INTERFACE)

add_library(pid0::pid0 ALIAS pid0)
add_library(pid0::pid0_static ALIAS pid0_static)
add_library(pid0::pid0_shared ALIAS pid0_shared)

pid0_configure_library(pid0_static)
pid0_configure_library(pid0_shared)

target_include_directories(
  pid0
  INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)
target_link_libraries(pid0 INTERFACE pid0_static)

set_target_properties(
  pid0_static
  PROPERTIES
    OUTPUT_NAME pid0
    POSITION_INDEPENDENT_CODE ON
)
set_target_properties(
  pid0_shared
  PROPERTIES
    OUTPUT_NAME pid0
    VERSION ${PROJECT_VERSION}
    SOVERSION 0
)

install(
  TARGETS pid0_static
  EXPORT pid0Targets
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  COMPONENT dev
)
install(
  TARGETS pid0_shared
  EXPORT pid0Targets
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  COMPONENT runtime
  NAMELINK_COMPONENT runtime
)
install(
  TARGETS pid0
  EXPORT pid0Targets
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
  COMPONENT dev
)
install(
  DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include/
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
  COMPONENT dev
)
install(
  EXPORT pid0Targets
  FILE pid0Targets.cmake
  NAMESPACE pid0::
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/pid0
  COMPONENT dev
)
install(
  FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/LICENSE
    ${CMAKE_CURRENT_SOURCE_DIR}/README.md
  DESTINATION ${CMAKE_INSTALL_DATADIR}/libpid0
  COMPONENT runtime
)
install(
  FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/LICENSE
    ${CMAKE_CURRENT_SOURCE_DIR}/README.md
  DESTINATION ${CMAKE_INSTALL_DATADIR}/libpid0
  COMPONENT dev
)

if(PID0_BUILD_EXAMPLE)
  add_subdirectory(example)
endif()

if(PID0_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()

set(CPACK_GENERATOR "TGZ")
set(CPACK_ARCHIVE_COMPONENT_INSTALL ON)
set(CPACK_COMPONENTS_GROUPING IGNORE)
set(CPACK_INCLUDE_TOPLEVEL_DIRECTORY OFF)
set(CPACK_PACKAGE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/dist")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_FILE_NAME "${PID0_PACKAGE_BASENAME}")
set(CPACK_ARCHIVE_RUNTIME_FILE_NAME "${PID0_PACKAGE_BASENAME}")
set(CPACK_ARCHIVE_DEV_FILE_NAME "${PID0_PACKAGE_BASENAME}-dev")
set(CPACK_COMPONENTS_ALL runtime dev)
set(CPACK_COMPONENT_RUNTIME_DISPLAY_NAME "libpid0 runtime")
set(CPACK_COMPONENT_DEV_DISPLAY_NAME "libpid0 development files")
set(CPACK_COMPONENT_DEV_DESCRIPTION "Headers, static library, CMake metadata, and documentation for libpid0")
set(CPACK_COMPONENT_RUNTIME_DESCRIPTION "Runtime shared libraries for libpid0")
set(CPACK_COMPONENT_DEV_DEPENDS runtime)

find_program(CLANG_FORMAT_BIN NAMES clang-format)
if(CLANG_FORMAT_BIN)
  add_custom_target(
    format
    COMMAND "${CLANG_FORMAT_BIN}" -i ${PID0_FORMAT_SOURCES}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Formatting libpid0 source files with clang-format"
  )
endif()

include(CPack)
