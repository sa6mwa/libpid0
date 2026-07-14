include_guard(GLOBAL)

if(NOT DEFINED CPKT_DEPENDENCY_CACHE OR CPKT_DEPENDENCY_CACHE STREQUAL "")
  if(DEFINED ENV{CPKT_DEPENDENCY_CACHE} AND NOT "$ENV{CPKT_DEPENDENCY_CACHE}" STREQUAL "")
    set(CPKT_DEPENDENCY_CACHE "$ENV{CPKT_DEPENDENCY_CACHE}")
  elseif(DEFINED ENV{XDG_CACHE_HOME} AND NOT "$ENV{XDG_CACHE_HOME}" STREQUAL "")
    set(CPKT_DEPENDENCY_CACHE "$ENV{XDG_CACHE_HOME}/c.pkt.systems/deps")
  elseif(DEFINED ENV{HOME} AND NOT "$ENV{HOME}" STREQUAL "")
    set(CPKT_DEPENDENCY_CACHE "$ENV{HOME}/.cache/c.pkt.systems/deps")
  else()
    message(FATAL_ERROR "CPKT_DEPENDENCY_CACHE, XDG_CACHE_HOME, or HOME is required")
  endif()
endif()
set(CPKT_DEPENDENCY_CACHE "${CPKT_DEPENDENCY_CACHE}" CACHE PATH
  "Shared cache for verified external dependency archives")
set(PID0_DEPENDENCY_DOWNLOAD_ATTEMPTS 3 CACHE STRING
  "Number of attempts when downloading a checksum-pinned dependency archive")

if(NOT PID0_DEPENDENCY_DOWNLOAD_ATTEMPTS MATCHES "^[1-9][0-9]*$")
  message(FATAL_ERROR "PID0_DEPENDENCY_DOWNLOAD_ATTEMPTS must be a positive integer")
endif()

function(pid0_acquire_verified_archive name url sha256 out_archive)
  if(NOT url MATCHES "^https://")
    message(FATAL_ERROR "${name}: dependency URL must use HTTPS: ${url}")
  endif()
  string(LENGTH "${sha256}" sha256_length)
  if(NOT sha256_length EQUAL 64 OR NOT sha256 MATCHES "^[0-9a-fA-F]+$")
    message(FATAL_ERROR "${name}: expected a SHA-256 digest")
  endif()

  get_filename_component(archive_name "${url}" NAME)
  set(cache_dir "${CPKT_DEPENDENCY_CACHE}/archives/sha256/${sha256}")
  set(lock_dir "${CPKT_DEPENDENCY_CACHE}/locks")
  set(archive_path "${cache_dir}/${archive_name}")
  file(MAKE_DIRECTORY "${cache_dir}" "${lock_dir}")
  file(LOCK "${lock_dir}/${sha256}.lock" GUARD PROCESS TIMEOUT 120)

  if(EXISTS "${archive_path}")
    file(SHA256 "${archive_path}" actual_sha256)
    if(NOT actual_sha256 STREQUAL sha256)
      file(REMOVE "${archive_path}")
    endif()
  endif()

  if(NOT EXISTS "${archive_path}")
    string(RANDOM LENGTH 32 ALPHABET "0123456789abcdef" tmp_suffix)
    set(tmp_path "${archive_path}.tmp.${tmp_suffix}")
    set(download_code 1)
    set(download_log "")
    foreach(download_attempt RANGE 1 ${PID0_DEPENDENCY_DOWNLOAD_ATTEMPTS})
      file(REMOVE "${tmp_path}")
      set(download_command
        "${CMAKE_COMMAND}"
        "-DPID0_DOWNLOAD_URL=${url}"
        "-DPID0_DOWNLOAD_OUTPUT=${tmp_path}"
        "-DPID0_DOWNLOAD_SHA256=${sha256}"
      )
      if(DEFINED CMAKE_TLS_CAINFO AND NOT CMAKE_TLS_CAINFO STREQUAL "")
        list(APPEND download_command "-DCMAKE_TLS_CAINFO=${CMAKE_TLS_CAINFO}")
      endif()
      list(APPEND download_command
        "-P"
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/CPKTDownloadVerifiedArchive.cmake"
      )
      execute_process(
        COMMAND ${download_command}
        RESULT_VARIABLE download_code
        OUTPUT_VARIABLE download_stdout
        ERROR_VARIABLE download_stderr
      )
      set(download_log "${download_stdout}\n${download_stderr}")
      if(download_code EQUAL 0)
        break()
      endif()
      if(download_attempt LESS PID0_DEPENDENCY_DOWNLOAD_ATTEMPTS)
        message(STATUS
          "${name}: dependency download attempt ${download_attempt}/${PID0_DEPENDENCY_DOWNLOAD_ATTEMPTS} failed; retrying")
      endif()
    endforeach()
    if(NOT download_code EQUAL 0)
      file(REMOVE "${tmp_path}")
      message(FATAL_ERROR
        "${name}: verified download failed\nurl=${url}\nexpected_sha256=${sha256}\ncache=${archive_path}\n${download_log}"
      )
    endif()
    file(SHA256 "${tmp_path}" actual_sha256)
    if(NOT actual_sha256 STREQUAL sha256)
      file(REMOVE "${tmp_path}")
      message(FATAL_ERROR "${name}: downloaded archive checksum mismatch")
    endif()
    file(RENAME "${tmp_path}" "${archive_path}")
  endif()

  set(${out_archive} "${archive_path}" PARENT_SCOPE)
endfunction()

function(pid0_stage_verified_archive name version sha256 archive out_source)
  if(NOT DEFINED PID0_DEPENDENCY_BUILD_ROOT OR PID0_DEPENDENCY_BUILD_ROOT STREQUAL "")
    set(PID0_DEPENDENCY_BUILD_ROOT "${CMAKE_SOURCE_DIR}/.cache/deps/${PID0_TARGET_ID}"
      CACHE PATH "Disposable target-specific dependency build roots")
  endif()
  set(stage_root "${PID0_DEPENDENCY_BUILD_ROOT}/${name}-${version}-${sha256}")
  set(stage_lock_dir "${PID0_DEPENDENCY_BUILD_ROOT}/locks")
  set(stage_lock "${stage_lock_dir}/${name}-${version}-${sha256}.lock")
  set(stamp "${stage_root}/.pid0-archive-sha256")
  file(MAKE_DIRECTORY "${stage_lock_dir}")
  file(LOCK "${stage_lock}" GUARD FUNCTION TIMEOUT 120)
  if(EXISTS "${stamp}")
    file(READ "${stamp}" staged_sha256)
    string(STRIP "${staged_sha256}" staged_sha256)
  endif()
  if(NOT EXISTS "${stamp}" OR NOT staged_sha256 STREQUAL sha256)
    file(REMOVE_RECURSE "${stage_root}")
    file(MAKE_DIRECTORY "${stage_root}")
    file(ARCHIVE_EXTRACT INPUT "${archive}" DESTINATION "${stage_root}")
    file(WRITE "${stamp}" "${sha256}\n")
  endif()
  file(GLOB extracted_children LIST_DIRECTORIES TRUE "${stage_root}/*")
  list(FILTER extracted_children EXCLUDE REGEX "^${stamp}$")
  list(LENGTH extracted_children child_count)
  if(NOT child_count EQUAL 1)
    message(FATAL_ERROR "${name}: archive must extract to exactly one source root")
  endif()
  list(GET extracted_children 0 source_root)
  set(${out_source} "${source_root}" PARENT_SCOPE)
endfunction()
