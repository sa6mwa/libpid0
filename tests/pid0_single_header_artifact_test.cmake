foreach(required_var IN ITEMS
  PID0_SINGLE_HEADER_BUILD
  PID0_SINGLE_HEADER_BUILD_ALIAS
  PID0_SINGLE_HEADER_DIST_GZ
  PID0_VERSION
)
  if(NOT DEFINED ${required_var})
    message(FATAL_ERROR "${required_var} is required")
  endif()
endforeach()

foreach(path IN ITEMS
  "${PID0_SINGLE_HEADER_BUILD}"
  "${PID0_SINGLE_HEADER_BUILD_ALIAS}"
  "${PID0_SINGLE_HEADER_DIST_GZ}"
)
  if(NOT EXISTS "${path}")
    message(FATAL_ERROR "missing single-header artifact: ${path}")
  endif()
endforeach()

file(READ "${PID0_SINGLE_HEADER_BUILD}" build_header)
file(READ "${PID0_SINGLE_HEADER_BUILD_ALIAS}" alias_header)

if(NOT build_header STREQUAL alias_header)
  message(FATAL_ERROR "single-header build output and alias output differ")
endif()

get_filename_component(dist_dir "${PID0_SINGLE_HEADER_DIST_GZ}" DIRECTORY)
set(forbidden_dist_header "${dist_dir}/libpid0-${PID0_VERSION}.h")
if(EXISTS "${forbidden_dist_header}")
  message(FATAL_ERROR "unexpected uncompressed dist single-header artifact: ${forbidden_dist_header}")
endif()

foreach(required_text IN ITEMS
  "libpid0 single-header distribution"
  "Version: ${PID0_VERSION}"
  "Artifact: libpid0-${PID0_VERSION}.h"
  "#ifdef PID0_IMPLEMENTATION"
  "int pid0_run(pid0_submain_fn submain, int argc, char **argv)"
  "MIT License"
)
  string(FIND "${build_header}" "${required_text}" required_text_offset)
  if(required_text_offset EQUAL -1)
    message(FATAL_ERROR "single-header artifact is missing expected text: ${required_text}")
  endif()
endforeach()

foreach(forbidden_text IN ITEMS
  "#include \"pid0/pid0.h\""
  "#include \"pid0_internal.h\""
  "PID0_IMPLEMENTATION_ONCE"
)
  string(FIND "${build_header}" "${forbidden_text}" forbidden_text_offset)
  if(NOT forbidden_text_offset EQUAL -1)
    message(FATAL_ERROR "single-header artifact contains forbidden text: ${forbidden_text}")
  endif()
endforeach()

find_program(PID0_GZIP_BIN NAMES gzip)
if(NOT PID0_GZIP_BIN)
  message(FATAL_ERROR "gzip is required to verify ${PID0_SINGLE_HEADER_DIST_GZ}")
endif()

execute_process(
  COMMAND "${PID0_GZIP_BIN}" -cd "${PID0_SINGLE_HEADER_DIST_GZ}"
  OUTPUT_VARIABLE decompressed_header
  RESULT_VARIABLE gzip_result
)
if(NOT gzip_result EQUAL 0)
  message(FATAL_ERROR "failed to decompress ${PID0_SINGLE_HEADER_DIST_GZ}")
endif()
if(NOT decompressed_header STREQUAL build_header)
  message(FATAL_ERROR "gzipped single-header artifact does not match build header")
endif()
