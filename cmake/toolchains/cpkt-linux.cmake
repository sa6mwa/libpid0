# Select one complete, pinned Bootlin compiler collection before project().
# Linux builds deliberately have no host-compiler fallback.

if(NOT DEFINED PID0_TARGET_ID OR PID0_TARGET_ID STREQUAL "")
  message(FATAL_ERROR "PID0_TARGET_ID is required for the lifecycle Linux toolchain")
endif()
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES PID0_TARGET_ID)

set(PID0_TOOLCHAIN_RESOLVER "${CMAKE_CURRENT_LIST_DIR}/../../scripts/cpkt-toolchains.sh")
if(NOT EXISTS "${PID0_TOOLCHAIN_RESOLVER}")
  message(FATAL_ERROR "missing lifecycle toolchain resolver: ${PID0_TOOLCHAIN_RESOLVER}")
endif()

execute_process(
  COMMAND bash "${PID0_TOOLCHAIN_RESOLVER}" ensure "${PID0_TARGET_ID}"
  RESULT_VARIABLE pid0_ensure_result
  OUTPUT_VARIABLE pid0_ensure_output
  ERROR_VARIABLE pid0_ensure_error
)
if(NOT pid0_ensure_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to provision the pinned Bootlin toolchain for ${PID0_TARGET_ID}:\n${pid0_ensure_error}"
  )
endif()

execute_process(
  COMMAND bash "${PID0_TOOLCHAIN_RESOLVER}" discover "${PID0_TARGET_ID}"
  RESULT_VARIABLE pid0_discover_result
  OUTPUT_VARIABLE pid0_description
  ERROR_VARIABLE pid0_discover_error
)
if(NOT pid0_discover_result EQUAL 0)
  message(FATAL_ERROR
    "Unable to inspect the pinned Bootlin toolchain for ${PID0_TARGET_ID}:\n${pid0_discover_error}"
  )
endif()

foreach(pid0_key IN ITEMS root cc cxx ld ar ranlib strip nm objcopy objdump addr2line readelf sysroot)
  string(REGEX MATCH "${pid0_key}=([^\r\n]+)" pid0_match "${pid0_description}")
  if(NOT pid0_match)
    message(FATAL_ERROR
      "Bootlin resolver did not report ${pid0_key} for ${PID0_TARGET_ID}:\n${pid0_description}"
    )
  endif()
  set(pid0_${pid0_key} "${CMAKE_MATCH_1}")
endforeach()

set(CMAKE_C_COMPILER "${pid0_cc}" CACHE FILEPATH "Pinned Bootlin C compiler" FORCE)
set(CMAKE_CXX_COMPILER "${pid0_cxx}" CACHE FILEPATH "Pinned Bootlin C++ compiler" FORCE)
set(CMAKE_LINKER "${pid0_ld}" CACHE FILEPATH "Pinned Bootlin linker" FORCE)
set(CMAKE_AR "${pid0_ar}" CACHE FILEPATH "Pinned Bootlin archiver" FORCE)
set(CMAKE_RANLIB "${pid0_ranlib}" CACHE FILEPATH "Pinned Bootlin ranlib" FORCE)
set(CMAKE_STRIP "${pid0_strip}" CACHE FILEPATH "Pinned Bootlin strip" FORCE)
set(CMAKE_NM "${pid0_nm}" CACHE FILEPATH "Pinned Bootlin nm" FORCE)
set(CMAKE_OBJCOPY "${pid0_objcopy}" CACHE FILEPATH "Pinned Bootlin objcopy" FORCE)
set(CMAKE_OBJDUMP "${pid0_objdump}" CACHE FILEPATH "Pinned Bootlin objdump" FORCE)
set(CMAKE_ADDR2LINE "${pid0_addr2line}" CACHE FILEPATH "Pinned Bootlin addr2line" FORCE)
set(CMAKE_READELF "${pid0_readelf}" CACHE FILEPATH "Pinned Bootlin readelf" FORCE)
set(CMAKE_SYSROOT "${pid0_sysroot}" CACHE PATH "Pinned Bootlin sysroot" FORCE)
set(CMAKE_FIND_ROOT_PATH "${pid0_sysroot}" "${pid0_root}" CACHE STRING "Pinned Bootlin roots" FORCE)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER CACHE STRING "" FORCE)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY CACHE STRING "" FORCE)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY CACHE STRING "" FORCE)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY CACHE STRING "" FORCE)

if(NOT DEFINED CMAKE_SYSTEM_NAME)
  set(CMAKE_SYSTEM_NAME Linux)
endif()
if(NOT DEFINED CMAKE_SYSTEM_PROCESSOR)
  if(PID0_TARGET_ID MATCHES "^x86_64-")
    set(CMAKE_SYSTEM_PROCESSOR x86_64)
  elseif(PID0_TARGET_ID MATCHES "^aarch64-")
    set(CMAKE_SYSTEM_PROCESSOR aarch64)
  elseif(PID0_TARGET_ID MATCHES "^armhf-")
    set(CMAKE_SYSTEM_PROCESSOR armhf)
  endif()
endif()
if(NOT PID0_TARGET_ID MATCHES "^x86_64-")
  set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
endif()

execute_process(
  COMMAND "${pid0_cc}" -print-prog-name=ld
  OUTPUT_VARIABLE pid0_reported_ld
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
string(FIND "${pid0_reported_ld}" "${pid0_root}/" pid0_ld_inside_root)
if(pid0_ld_inside_root EQUAL -1)
  message(FATAL_ERROR
    "Pinned compiler selected a linker outside its collection: ${pid0_reported_ld}"
  )
endif()
