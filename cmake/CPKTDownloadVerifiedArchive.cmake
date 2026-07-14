foreach(required_variable
    PID0_DOWNLOAD_URL
    PID0_DOWNLOAD_OUTPUT
    PID0_DOWNLOAD_SHA256)
  if(NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR "${required_variable} is required")
  endif()
endforeach()

file(DOWNLOAD "${PID0_DOWNLOAD_URL}" "${PID0_DOWNLOAD_OUTPUT}"
  TLS_VERIFY ON
  EXPECTED_HASH "SHA256=${PID0_DOWNLOAD_SHA256}"
  STATUS download_status
  LOG download_log
  TIMEOUT 60
  INACTIVITY_TIMEOUT 15
)
list(GET download_status 0 download_code)
if(NOT download_code EQUAL 0)
  message(FATAL_ERROR "download failed: ${download_log}")
endif()
