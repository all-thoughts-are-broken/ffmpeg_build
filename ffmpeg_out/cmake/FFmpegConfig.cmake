if(TARGET FFmpeg::ffmpeg)
  set(FFmpeg_FOUND TRUE)
  set(FFMPEG_FOUND TRUE)
  return()
endif()

get_filename_component(_ffmpeg_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(_ffmpeg_include_dir "${_ffmpeg_root}/include")
set(_ffmpeg_lib_dir "${_ffmpeg_root}/lib")
set(_ffmpeg_pkgconfig_dir "${_ffmpeg_lib_dir}/pkgconfig")

if(NOT EXISTS "${_ffmpeg_include_dir}" OR NOT EXISTS "${_ffmpeg_lib_dir}")
  message(FATAL_ERROR "FFmpegConfig.cmake expects include/ and lib/ under ${_ffmpeg_root}")
endif()

include(CMakeFindDependencyMacro)

function(_ffmpeg_read_pc_field _pc_path _field_regex _out_var)
  if(NOT EXISTS "${_pc_path}")
    set(${_out_var} "" PARENT_SCOPE)
    return()
  endif()

  file(STRINGS "${_pc_path}" _ffmpeg_pc_lines REGEX "^${_field_regex}:")
  if(_ffmpeg_pc_lines)
    list(GET _ffmpeg_pc_lines 0 _ffmpeg_pc_line)
    string(REGEX REPLACE "^[^:]+:[ ]*" "" _ffmpeg_pc_value "${_ffmpeg_pc_line}")
  else()
    set(_ffmpeg_pc_value "")
  endif()

  set(${_out_var} "${_ffmpeg_pc_value}" PARENT_SCOPE)
endfunction()

function(_ffmpeg_collect_pc_link_items _pc_path _out_libs _out_options _out_needs_threads)
  _ffmpeg_read_pc_field("${_pc_path}" "Libs" _ffmpeg_libs)
  _ffmpeg_read_pc_field("${_pc_path}" "Libs\\.private" _ffmpeg_libs_private)

  set(_ffmpeg_combined "${_ffmpeg_libs} ${_ffmpeg_libs_private}")
  string(STRIP "${_ffmpeg_combined}" _ffmpeg_combined)
  if(_ffmpeg_combined STREQUAL "")
    set(${_out_libs} "" PARENT_SCOPE)
    set(${_out_options} "" PARENT_SCOPE)
    set(${_out_needs_threads} FALSE PARENT_SCOPE)
    return()
  endif()

  separate_arguments(_ffmpeg_tokens UNIX_COMMAND "${_ffmpeg_combined}")
  set(_ffmpeg_lib_items)
  set(_ffmpeg_option_items)
  set(_ffmpeg_needs_threads FALSE)
  set(_ffmpeg_expect_framework FALSE)

  foreach(_ffmpeg_token IN LISTS _ffmpeg_tokens)
    if(_ffmpeg_expect_framework)
      find_library(_ffmpeg_framework NAMES "${_ffmpeg_token}")
      if(_ffmpeg_framework)
        list(APPEND _ffmpeg_lib_items "${_ffmpeg_framework}")
      else()
        list(APPEND _ffmpeg_option_items "-framework" "${_ffmpeg_token}")
      endif()
      set(_ffmpeg_expect_framework FALSE)
      continue()
    endif()

    if(_ffmpeg_token STREQUAL "-framework")
      set(_ffmpeg_expect_framework TRUE)
    elseif(_ffmpeg_token MATCHES "^-L")
    elseif(_ffmpeg_token STREQUAL "-pthread")
      set(_ffmpeg_needs_threads TRUE)
    elseif(_ffmpeg_token MATCHES "^-l(.+)")
      set(_ffmpeg_link_name "${CMAKE_MATCH_1}")
      if(_ffmpeg_link_name MATCHES "^(avutil|swresample|swscale|avcodec|avformat)$")
        continue()
      endif()
      if(_ffmpeg_link_name STREQUAL "pthread")
        set(_ffmpeg_needs_threads TRUE)
      else()
        list(APPEND _ffmpeg_lib_items "${_ffmpeg_link_name}")
      endif()
    elseif(_ffmpeg_token MATCHES "\\.(lib|a)$" AND NOT _ffmpeg_token MATCHES "[/\\\\]")
      if(_ffmpeg_token MATCHES "^(lib)?(avutil|swresample|swscale|avcodec|avformat)\\.(lib|a)$")
        continue()
      endif()
      list(APPEND _ffmpeg_lib_items "${_ffmpeg_token}")
    elseif(_ffmpeg_token MATCHES "^-Wl,")
      list(APPEND _ffmpeg_option_items "${_ffmpeg_token}")
    elseif(_ffmpeg_token MATCHES "^[-/]")
      list(APPEND _ffmpeg_option_items "${_ffmpeg_token}")
    else()
      list(APPEND _ffmpeg_lib_items "${_ffmpeg_token}")
    endif()
  endforeach()

  list(REMOVE_DUPLICATES _ffmpeg_lib_items)
  list(REMOVE_DUPLICATES _ffmpeg_option_items)

  set(${_out_libs} "${_ffmpeg_lib_items}" PARENT_SCOPE)
  set(${_out_options} "${_ffmpeg_option_items}" PARENT_SCOPE)
  set(${_out_needs_threads} "${_ffmpeg_needs_threads}" PARENT_SCOPE)
endfunction()

function(_ffmpeg_find_library_file _name _out_var)
  set(_ffmpeg_candidates
    "${_ffmpeg_lib_dir}/${_name}.lib"
    "${_ffmpeg_lib_dir}/lib${_name}.a"
    "${_ffmpeg_lib_dir}/${_name}.a"
    "${_ffmpeg_lib_dir}/lib${_name}.lib"
  )

  foreach(_ffmpeg_candidate IN LISTS _ffmpeg_candidates)
    if(EXISTS "${_ffmpeg_candidate}")
      set(${_out_var} "${_ffmpeg_candidate}" PARENT_SCOPE)
      return()
    endif()
  endforeach()

  message(FATAL_ERROR "Could not find FFmpeg library '${_name}' under ${_ffmpeg_lib_dir}")
endfunction()

set(_ffmpeg_components avutil swresample swscale avcodec avformat)
foreach(_ffmpeg_component IN LISTS _ffmpeg_components)
  _ffmpeg_find_library_file("${_ffmpeg_component}" _ffmpeg_component_location)

  add_library(FFmpeg::${_ffmpeg_component} STATIC IMPORTED GLOBAL)
  set_target_properties(FFmpeg::${_ffmpeg_component} PROPERTIES
    IMPORTED_LOCATION "${_ffmpeg_component_location}"
    INTERFACE_INCLUDE_DIRECTORIES "${_ffmpeg_include_dir}"
  )
endforeach()

function(_ffmpeg_apply_pc_usage _component)
  set(_ffmpeg_pc_path "${_ffmpeg_pkgconfig_dir}/lib${_component}.pc")
  set(_ffmpeg_link_libs)
  set(_ffmpeg_link_options)
  set(_ffmpeg_component_needs_threads FALSE)

  if(EXISTS "${_ffmpeg_pc_path}")
    _ffmpeg_collect_pc_link_items(
      "${_ffmpeg_pc_path}"
      _ffmpeg_link_libs
      _ffmpeg_link_options
      _ffmpeg_component_needs_threads
    )
  endif()

  set(_ffmpeg_usage_libs)
  if(_component STREQUAL "swresample" OR _component STREQUAL "swscale" OR _component STREQUAL "avcodec")
    list(APPEND _ffmpeg_usage_libs FFmpeg::avutil)
  elseif(_component STREQUAL "avformat")
    list(APPEND _ffmpeg_usage_libs FFmpeg::avcodec FFmpeg::avutil)
  endif()

  if(_ffmpeg_component_needs_threads)
    if(NOT TARGET Threads::Threads)
      find_dependency(Threads)
    endif()
    list(APPEND _ffmpeg_usage_libs Threads::Threads)
  endif()

  list(APPEND _ffmpeg_usage_libs ${_ffmpeg_link_libs})
  list(REMOVE_DUPLICATES _ffmpeg_usage_libs)

  if(_ffmpeg_usage_libs)
    set_property(TARGET FFmpeg::${_component} APPEND PROPERTY INTERFACE_LINK_LIBRARIES "${_ffmpeg_usage_libs}")
  endif()

  if(_ffmpeg_link_options)
    set_property(TARGET FFmpeg::${_component} APPEND PROPERTY INTERFACE_LINK_OPTIONS "${_ffmpeg_link_options}")
  endif()
endfunction()

foreach(_ffmpeg_component IN LISTS _ffmpeg_components)
  _ffmpeg_apply_pc_usage("${_ffmpeg_component}")
endforeach()

add_library(FFmpeg::ffmpeg INTERFACE IMPORTED GLOBAL)
set_property(TARGET FFmpeg::ffmpeg PROPERTY INTERFACE_INCLUDE_DIRECTORIES "${_ffmpeg_include_dir}")
set_property(TARGET FFmpeg::ffmpeg PROPERTY INTERFACE_LINK_LIBRARIES
  "FFmpeg::avformat;FFmpeg::avcodec;FFmpeg::swresample;FFmpeg::swscale;FFmpeg::avutil"
)

set(FFmpeg_FOUND TRUE)
set(FFMPEG_FOUND TRUE)
set(FFmpeg_INCLUDE_DIRS "${_ffmpeg_include_dir}")
set(FFMPEG_INCLUDE_DIRS "${_ffmpeg_include_dir}")
set(FFmpeg_LIBRARY_DIRS "${_ffmpeg_lib_dir}")
set(FFMPEG_LIBRARY_DIRS "${_ffmpeg_lib_dir}")
set(FFmpeg_LIBRARIES "FFmpeg::avformat;FFmpeg::avcodec;FFmpeg::swresample;FFmpeg::swscale;FFmpeg::avutil")
set(FFMPEG_LIBRARIES "${FFmpeg_LIBRARIES}")
