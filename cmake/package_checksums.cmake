if(NOT DEFINED PID0_ROOT)
  message(FATAL_ERROR "PID0_ROOT is required")
endif()
if(NOT DEFINED PID0_VERSION)
  message(FATAL_ERROR "PID0_VERSION is required")
endif()

set(dist_dir "${PID0_ROOT}/dist")
set(checksums_name "libpid0-${PID0_VERSION}-CHECKSUMS")
set(checksums_path "${dist_dir}/${checksums_name}")

file(MAKE_DIRECTORY "${dist_dir}")
file(GLOB release_entries RELATIVE "${dist_dir}"
  "${dist_dir}/libpid0-${PID0_VERSION}.tar.gz"
  "${dist_dir}/libpid0-${PID0_VERSION}-*.tar.gz"
  "${dist_dir}/libpid0-${PID0_VERSION}.h.gz"
)

set(checksum_inputs "")
foreach(entry IN LISTS release_entries)
  if(NOT entry STREQUAL "${checksums_name}")
    list(APPEND checksum_inputs "${entry}")
  endif()
endforeach()

list(LENGTH checksum_inputs checksum_input_count)
if(checksum_input_count EQUAL 0)
  message(FATAL_ERROR "no release artifacts found in ${dist_dir} for version ${PID0_VERSION}")
endif()

list(SORT checksum_inputs)

execute_process(
  COMMAND sha256sum ${checksum_inputs}
  WORKING_DIRECTORY "${dist_dir}"
  OUTPUT_FILE "${checksums_path}"
  RESULT_VARIABLE checksum_result
)

if(NOT checksum_result EQUAL 0)
  message(FATAL_ERROR "failed to create ${checksums_name}")
endif()
