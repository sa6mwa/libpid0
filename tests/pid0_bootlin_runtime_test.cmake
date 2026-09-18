if(NOT EXISTS "${PID0_READELF}")
  message(FATAL_ERROR "Pinned Bootlin readelf is unavailable: ${PID0_READELF}")
endif()
if(NOT EXISTS "${PID0_EXPECTED_INTERPRETER}")
  message(FATAL_ERROR "Pinned Bootlin interpreter is unavailable: ${PID0_EXPECTED_INTERPRETER}")
endif()
if(PID0_EXPECTED_RPATH STREQUAL "")
  message(FATAL_ERROR "Pinned Bootlin runtime search path is empty")
endif()
if(PID0_VERIFY_RUNTIME_RESOLUTION AND NOT IS_DIRECTORY "${PID0_EXPECTED_RUNTIME_ROOT}")
  message(FATAL_ERROR "Pinned Bootlin runtime root is unavailable: ${PID0_EXPECTED_RUNTIME_ROOT}")
endif()

string(REPLACE "|" ";" pid0_executables "${PID0_EXECUTABLES}")
foreach(pid0_executable IN LISTS pid0_executables)
  if(NOT EXISTS "${pid0_executable}")
    message(FATAL_ERROR "Expected local executable is missing: ${pid0_executable}")
  endif()

  execute_process(
    COMMAND "${PID0_READELF}" -l "${pid0_executable}"
    RESULT_VARIABLE pid0_program_headers_result
    OUTPUT_VARIABLE pid0_program_headers
    ERROR_VARIABLE pid0_program_headers_error
  )
  if(NOT pid0_program_headers_result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ELF interpreter for ${pid0_executable}: ${pid0_program_headers_error}")
  endif()

  execute_process(
    COMMAND "${PID0_READELF}" -d "${pid0_executable}"
    RESULT_VARIABLE pid0_dynamic_result
    OUTPUT_VARIABLE pid0_dynamic_metadata
    ERROR_VARIABLE pid0_dynamic_error
  )
  if(NOT pid0_dynamic_result EQUAL 0)
    message(FATAL_ERROR
      "Unable to inspect ELF runtime path for ${pid0_executable}: ${pid0_dynamic_error}")
  endif()
  if(PID0_EXPECT_STATIC)
    string(FIND "${pid0_program_headers}" "Requesting program interpreter:" pid0_interpreter_index)
    string(FIND "${pid0_dynamic_metadata}" "RPATH" pid0_rpath_index)
    string(FIND "${pid0_dynamic_metadata}" "RUNPATH" pid0_runpath_index)
    if(NOT pid0_interpreter_index EQUAL -1 OR NOT pid0_rpath_index EQUAL -1 OR NOT pid0_runpath_index EQUAL -1)
      message(FATAL_ERROR
        "Fully static local executable contains dynamic runtime metadata: ${pid0_executable}")
    endif()
    continue()
  endif()

  string(FIND "${pid0_program_headers}" "Requesting program interpreter: ${PID0_EXPECTED_INTERPRETER}" pid0_interpreter_index)
  if(pid0_interpreter_index EQUAL -1)
    message(FATAL_ERROR
      "Local executable does not use the selected Bootlin interpreter: ${pid0_executable}")
  endif()
  string(FIND "${pid0_dynamic_metadata}" "RPATH" pid0_rpath_index)
  string(FIND "${pid0_dynamic_metadata}" "RUNPATH" pid0_runpath_index)
  string(FIND "${pid0_dynamic_metadata}" "${PID0_EXPECTED_RPATH}" pid0_expected_rpath_index)
  if(pid0_rpath_index EQUAL -1 OR NOT pid0_runpath_index EQUAL -1 OR pid0_expected_rpath_index EQUAL -1)
    message(FATAL_ERROR
      "Local executable does not have the selected Bootlin DT_RPATH: ${pid0_executable}")
  endif()

  if(PID0_VERIFY_RUNTIME_RESOLUTION)
    execute_process(
      COMMAND "${PID0_EXPECTED_INTERPRETER}" --list "${pid0_executable}"
      RESULT_VARIABLE pid0_runtime_resolution_result
      OUTPUT_VARIABLE pid0_runtime_resolution
      ERROR_VARIABLE pid0_runtime_resolution_error
    )
    if(NOT pid0_runtime_resolution_result EQUAL 0)
      message(FATAL_ERROR
        "Unable to resolve the selected Bootlin runtime for ${pid0_executable}: ${pid0_runtime_resolution_error}")
    endif()
    string(REPLACE "|" ";" pid0_required_runtime_libraries "${PID0_REQUIRED_RUNTIME_LIBRARIES}")
    string(REPLACE "\n" ";" pid0_runtime_resolution_lines "${pid0_runtime_resolution}")
    foreach(pid0_required_runtime_library IN LISTS pid0_required_runtime_libraries)
      set(pid0_runtime_library_path "")
      foreach(pid0_runtime_resolution_line IN LISTS pid0_runtime_resolution_lines)
        string(FIND "${pid0_runtime_resolution_line}" "${pid0_required_runtime_library}" pid0_runtime_library_index)
        if(NOT pid0_runtime_library_index EQUAL -1)
          string(REGEX REPLACE ".* => ([^ ]+).*" "\\1" pid0_runtime_library_path
            "${pid0_runtime_resolution_line}")
          break()
        endif()
      endforeach()
      if(pid0_runtime_library_path STREQUAL "")
        message(FATAL_ERROR
          "Local executable does not resolve required compiler runtime ${pid0_required_runtime_library}: ${pid0_executable}")
      endif()
      file(REAL_PATH "${pid0_runtime_library_path}" pid0_runtime_library_real)
      string(FIND "${pid0_runtime_library_real}" "${PID0_EXPECTED_RUNTIME_ROOT}/" pid0_runtime_root_index)
      if(pid0_runtime_root_index EQUAL -1)
        message(FATAL_ERROR
          "Local executable resolves ${pid0_required_runtime_library} outside the selected Bootlin collection: ${pid0_runtime_library_real}")
      endif()
    endforeach()
  endif()
endforeach()
