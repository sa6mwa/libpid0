cmake_minimum_required(VERSION 3.28)

set(PID0_DEFAULT_VERSION "0.0.0")
set(PID0_PACKAGE_VERSION "${PID0_DEFAULT_VERSION}")
set(PID0_VERSION_OVERRIDE "" CACHE STRING "Explicit release-candidate version override")
if(NOT PID0_VERSION_OVERRIDE AND DEFINED ENV{PID0_VERSION_OVERRIDE})
  set(PID0_VERSION_OVERRIDE "$ENV{PID0_VERSION_OVERRIDE}")
endif()

if(PID0_VERSION_OVERRIDE)
  if(NOT PID0_VERSION_OVERRIDE MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR "PID0_VERSION_OVERRIDE must match X.Y.Z")
  endif()
  set(PID0_PACKAGE_VERSION "${PID0_VERSION_OVERRIDE}")
endif()

find_package(Git QUIET)
if(NOT PID0_VERSION_OVERRIDE AND Git_FOUND)
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
if(NOT PID0_VERSION_OVERRIDE AND PID0_PACKAGE_VERSION STREQUAL PID0_DEFAULT_VERSION)
  if(NOT EXISTS "${CMAKE_CURRENT_LIST_DIR}/.git" AND EXISTS "${CMAKE_CURRENT_LIST_DIR}/VERSION")
    file(READ "${CMAKE_CURRENT_LIST_DIR}/VERSION" PID0_SOURCE_VERSION)
    string(STRIP "${PID0_SOURCE_VERSION}" PID0_SOURCE_VERSION)
    if(PID0_SOURCE_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
      set(PID0_PACKAGE_VERSION "${PID0_SOURCE_VERSION}")
    else()
      message(FATAL_ERROR "source archive VERSION must match X.Y.Z")
    endif()
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
include(CMakePackageConfigHelpers)

option(PID0_BUILD_EXAMPLES "Build the example applications" ON)
option(PID0_BUILD_TESTS "Build the test suite" ON)
option(PID0_ENABLE_ASAN "Build with AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

set(CMAKE_C_STANDARD 90)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_compile_definitions(_POSIX_C_SOURCE=200809L)

set(PID0_SOURCES src/pid0.c)
set(PID0_SINGLE_HEADER_BUILD "${CMAKE_CURRENT_BINARY_DIR}/generated/include/libpid0_single_header.h")
set(PID0_SINGLE_HEADER_ALIAS_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated/single-header/include")
set(PID0_SINGLE_HEADER_BUILD_ALIAS "${PID0_SINGLE_HEADER_ALIAS_INCLUDE_DIR}/pid0/pid0.h")
set(PID0_SINGLE_HEADER_DIST_GZ "${CMAKE_CURRENT_SOURCE_DIR}/dist/libpid0-${PROJECT_VERSION}.h.gz")
set(PID0_CONFIG_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated/cmake")
set(PID0_PKGCONFIG_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated/pkgconfig")
set(PID0_FORMAT_SOURCES
  include/pid0/pid0.h
  src/pid0.c
  src/pid0_internal.h
  example/main.c
  example/single_header_main.c
  tests/pid0_integration_test.c
  tests/pid0_single_header_unit_test.c
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
set(PID0_TARGET_ID "" CACHE STRING "Release target identifier")
set(PID0_TARGET_ARCH "" CACHE STRING "Release target architecture")
set(PID0_TARGET_OS "" CACHE STRING "Release target operating system")
set(PID0_TARGET_LIBC "" CACHE STRING "Release target libc ABI")

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
  "libpid0-${PROJECT_VERSION}-${PID0_PACKAGE_ARCH}-${PID0_PACKAGE_OS}-${PID0_PACKAGE_LIBC_NAME}"
)
if(PID0_TARGET_ID)
  set(PID0_PACKAGE_TARGET_ID "${PID0_TARGET_ID}")
else()
  set(PID0_PACKAGE_TARGET_ID "${PID0_PACKAGE_ARCH}-${PID0_PACKAGE_OS}-${PID0_PACKAGE_LIBC_NAME}")
endif()
set(PID0_PACKAGE_BASENAME "libpid0-${PROJECT_VERSION}-${PID0_PACKAGE_TARGET_ID}")

set(PID0_SINGLE_HEADER_SOURCE_PATHS "")
foreach(pid0_source IN LISTS PID0_SOURCES)
  list(APPEND PID0_SINGLE_HEADER_SOURCE_PATHS "${CMAKE_CURRENT_SOURCE_DIR}/${pid0_source}")
endforeach()
list(JOIN PID0_SINGLE_HEADER_SOURCE_PATHS "|" PID0_SINGLE_HEADER_SOURCE_PATHS_ARG)

function(pid0_configure_library target_name)
  target_include_directories(
    ${target_name}
    PUBLIC
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
      $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}/src
  )
  if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(
      ${target_name}
      PRIVATE
        -std=c89
        -Wall
        -Wextra
        -Wpedantic
        -pedantic-errors
        -Werror
    )
  endif()
  target_compile_definitions(${target_name} PUBLIC _POSIX_C_SOURCE=200809L)
  if(PID0_ENABLE_ASAN AND CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(${target_name} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target_name} PRIVATE -fsanitize=address,undefined)
  endif()
endfunction()

function(pid0_configure_c_executable target_name)
  if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(
      ${target_name}
      PRIVATE
        -std=c89
        -Wall
        -Wextra
        -Wpedantic
        -pedantic-errors
        -Werror
    )
  endif()
  target_compile_definitions(${target_name} PRIVATE _POSIX_C_SOURCE=200809L)
  if(PID0_ENABLE_ASAN AND CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(${target_name} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target_name} PRIVATE -fsanitize=address,undefined)
  endif()
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
)
install(
  TARGETS pid0_shared
  EXPORT pid0Targets
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
install(
  TARGETS pid0
  EXPORT pid0Targets
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
install(
  DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include/
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)
install(
  EXPORT pid0Targets
  FILE pid0Targets.cmake
  NAMESPACE pid0::
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/pid0
)
configure_package_config_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/pid0Config.cmake.in"
  "${PID0_CONFIG_BUILD_DIR}/pid0Config.cmake"
  INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/pid0
  NO_CHECK_REQUIRED_COMPONENTS_MACRO
)
write_basic_package_version_file(
  "${PID0_CONFIG_BUILD_DIR}/pid0ConfigVersion.cmake"
  VERSION ${PROJECT_VERSION}
  COMPATIBILITY SameMajorVersion
)
install(
  FILES
    "${PID0_CONFIG_BUILD_DIR}/pid0Config.cmake"
    "${PID0_CONFIG_BUILD_DIR}/pid0ConfigVersion.cmake"
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/pid0
)
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/pid0.pc.in"
  "${PID0_PKGCONFIG_BUILD_DIR}/pid0.pc"
  @ONLY
)
install(
  FILES "${PID0_PKGCONFIG_BUILD_DIR}/pid0.pc"
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig
)
install(
  FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/LICENSE
    ${CMAKE_CURRENT_SOURCE_DIR}/README.md
  DESTINATION ${CMAKE_INSTALL_DATADIR}/doc/libpid0
)

if(PID0_BUILD_EXAMPLES)
  add_subdirectory(example)
endif()

if(PID0_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()

set(CPACK_GENERATOR "TGZ")
set(CPACK_ARCHIVE_COMPONENT_INSTALL OFF)
set(CPACK_INCLUDE_TOPLEVEL_DIRECTORY OFF)
set(CPACK_PACKAGE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/dist")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_FILE_NAME "${PID0_PACKAGE_BASENAME}")

find_program(CLANG_FORMAT_BIN NAMES clang-format)
if(CLANG_FORMAT_BIN)
  add_custom_target(
    format
    COMMAND "${CLANG_FORMAT_BIN}" -i ${PID0_FORMAT_SOURCES}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Formatting libpid0 source files with clang-format"
  )
endif()

add_custom_target(
  package-single-header
  COMMAND
    ${CMAKE_COMMAND}
      -DPID0_ROOT=${CMAKE_CURRENT_SOURCE_DIR}
      -DPID0_VERSION=${PROJECT_VERSION}
      -DPID0_PUBLIC_HEADER=${CMAKE_CURRENT_SOURCE_DIR}/include/pid0/pid0.h
      -DPID0_INTERNAL_HEADER=${CMAKE_CURRENT_SOURCE_DIR}/src/pid0_internal.h
      -DPID0_SINGLE_HEADER_BUILD=${PID0_SINGLE_HEADER_BUILD}
      -DPID0_SINGLE_HEADER_BUILD_ALIAS=${PID0_SINGLE_HEADER_BUILD_ALIAS}
      -DPID0_SINGLE_HEADER_DIST_GZ=${PID0_SINGLE_HEADER_DIST_GZ}
      -DPID0_SINGLE_HEADER_SOURCES=${PID0_SINGLE_HEADER_SOURCE_PATHS_ARG}
      -DPID0_CLANG_FORMAT_BIN=${CLANG_FORMAT_BIN}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/package_single_header.cmake
  VERBATIM
)

add_custom_target(
  package-checksums
  COMMAND
    ${CMAKE_COMMAND}
      -DPID0_ROOT=${CMAKE_CURRENT_SOURCE_DIR}
      -DPID0_VERSION=${PROJECT_VERSION}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/package_checksums.cmake
  VERBATIM
)

include(CPack)
