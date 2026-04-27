if(NOT DEFINED PID0_ROOT)
  message(FATAL_ERROR "PID0_ROOT is required")
endif()
if(NOT DEFINED PID0_VERSION)
  message(FATAL_ERROR "PID0_VERSION is required")
endif()
if(NOT DEFINED PID0_PUBLIC_HEADER)
  message(FATAL_ERROR "PID0_PUBLIC_HEADER is required")
endif()
if(NOT DEFINED PID0_INTERNAL_HEADER)
  message(FATAL_ERROR "PID0_INTERNAL_HEADER is required")
endif()
if(NOT DEFINED PID0_SINGLE_HEADER_BUILD)
  message(FATAL_ERROR "PID0_SINGLE_HEADER_BUILD is required")
endif()
if(NOT DEFINED PID0_SINGLE_HEADER_BUILD_ALIAS)
  message(FATAL_ERROR "PID0_SINGLE_HEADER_BUILD_ALIAS is required")
endif()
if(NOT DEFINED PID0_SINGLE_HEADER_DIST_GZ)
  message(FATAL_ERROR "PID0_SINGLE_HEADER_DIST_GZ is required")
endif()
if(NOT DEFINED PID0_SINGLE_HEADER_SOURCES)
  message(FATAL_ERROR "PID0_SINGLE_HEADER_SOURCES is required")
endif()
if(NOT DEFINED PID0_CLANG_FORMAT_BIN OR PID0_CLANG_FORMAT_BIN STREQUAL "")
  message(FATAL_ERROR "PID0_CLANG_FORMAT_BIN is required to format the single-header artifact")
endif()

string(REPLACE "|" ";" PID0_SINGLE_HEADER_SOURCES "${PID0_SINGLE_HEADER_SOURCES}")

function(pid0_read_normalized out_var path)
  file(READ "${path}" content)
  string(REPLACE "\r\n" "\n" content "${content}")
  set(${out_var} "${content}" PARENT_SCOPE)
endfunction()

function(pid0_strip_guard out_var guard_macro content)
  set(stripped "${content}")
  string(REGEX REPLACE "^#ifndef ${guard_macro}\n#define ${guard_macro}\n\n?" "" stripped "${stripped}")
  string(REGEX REPLACE "\n#endif[ \t]*\n?$" "\n" stripped "${stripped}")
  set(${out_var} "${stripped}" PARENT_SCOPE)
endfunction()

pid0_read_normalized(public_header_raw "${PID0_PUBLIC_HEADER}")
pid0_strip_guard(public_header "PID0_PID0_H" "${public_header_raw}")

pid0_read_normalized(internal_header_raw "${PID0_INTERNAL_HEADER}")
pid0_strip_guard(internal_header "PID0_INTERNAL_H" "${internal_header_raw}")

pid0_read_normalized(license_text "${PID0_ROOT}/LICENSE")
string(REPLACE "\"" "\\\"" license_text "${license_text}")

pid0_read_normalized(preamble_template "${PID0_ROOT}/cmake/pid0_single_header_preamble.in")
get_filename_component(pid0_single_header_gz_filename "${PID0_SINGLE_HEADER_DIST_GZ}" NAME)
string(REGEX REPLACE "\\.gz$" "" pid0_single_header_filename "${pid0_single_header_gz_filename}")
set(PID0_LICENSE_TEXT "${license_text}")
set(PID0_SINGLE_HEADER_FILENAME "${pid0_single_header_filename}")
string(CONFIGURE "${preamble_template}" preamble @ONLY)

set(single_header "${preamble}\n\n#ifndef PID0_PID0_H\n#define PID0_PID0_H\n\n")
string(APPEND single_header "/* Public API */\n")
string(APPEND single_header "${public_header}\n")
string(APPEND single_header "#endif /* PID0_PID0_H */\n\n")
string(APPEND single_header "#ifdef PID0_IMPLEMENTATION\n")
string(APPEND single_header "#ifndef _POSIX_C_SOURCE\n")
string(APPEND single_header "#define _POSIX_C_SOURCE 200809L\n")
string(APPEND single_header "#endif\n\n")
string(APPEND single_header "/* Internal definitions */\n")
string(APPEND single_header "${internal_header}\n")

foreach(source_path IN LISTS PID0_SINGLE_HEADER_SOURCES)
  pid0_read_normalized(source_content "${source_path}")
  string(REPLACE "#include \"pid0/pid0.h\"\n\n" "" source_content "${source_content}")
  string(REPLACE "#include \"pid0/pid0.h\"\n" "" source_content "${source_content}")
  string(REPLACE "#include \"pid0_internal.h\"\n\n" "" source_content "${source_content}")
  string(REPLACE "#include \"pid0_internal.h\"\n" "" source_content "${source_content}")
  get_filename_component(source_name "${source_path}" NAME)
  string(APPEND single_header "\n/* Source: ${source_name} */\n")
  string(APPEND single_header "${source_content}\n")
endforeach()

string(APPEND single_header "\n#endif /* PID0_IMPLEMENTATION */\n")

get_filename_component(build_dir "${PID0_SINGLE_HEADER_BUILD}" DIRECTORY)
get_filename_component(build_alias_dir "${PID0_SINGLE_HEADER_BUILD_ALIAS}" DIRECTORY)
get_filename_component(dist_dir "${PID0_SINGLE_HEADER_DIST_GZ}" DIRECTORY)
set(pid0_uncompressed_dist_header "${dist_dir}/${pid0_single_header_filename}")
file(MAKE_DIRECTORY "${build_dir}" "${build_alias_dir}" "${dist_dir}")
file(WRITE "${PID0_SINGLE_HEADER_BUILD}" "${single_header}")
file(WRITE "${PID0_SINGLE_HEADER_BUILD_ALIAS}" "${single_header}")
file(REMOVE "${pid0_uncompressed_dist_header}")

execute_process(
  COMMAND "${PID0_CLANG_FORMAT_BIN}"
    -i
    "${PID0_SINGLE_HEADER_BUILD}"
    "${PID0_SINGLE_HEADER_BUILD_ALIAS}"
  RESULT_VARIABLE clang_format_result
)
if(NOT clang_format_result EQUAL 0)
  message(FATAL_ERROR "failed to clang-format single-header artifact")
endif()

find_program(PID0_GZIP_BIN NAMES gzip)
if(NOT PID0_GZIP_BIN)
  message(FATAL_ERROR "failed to find gzip for single-header artifact creation")
endif()

file(REMOVE "${PID0_SINGLE_HEADER_DIST_GZ}")
execute_process(
  COMMAND "${PID0_GZIP_BIN}" -9 -c "${PID0_SINGLE_HEADER_BUILD}"
  OUTPUT_FILE "${PID0_SINGLE_HEADER_DIST_GZ}"
  RESULT_VARIABLE gzip_result
)
if(NOT gzip_result EQUAL 0)
  message(FATAL_ERROR "failed to gzip single-header artifact")
endif()
