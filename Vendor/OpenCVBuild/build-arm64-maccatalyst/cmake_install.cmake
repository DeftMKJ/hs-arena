# Install script for directory: /Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/install-arm64-maccatalyst")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "Release")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "TRUE")
endif()

# Set path to fallback-tool for dependency-resolution.
if(NOT DEFINED CMAKE_OBJDUMP)
  set(CMAKE_OBJDUMP "/usr/bin/objdump")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "licenses" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/share/licenses/opencv4" TYPE FILE RENAME "flatbuffers-LICENSE.txt" FILES "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/3rdparty/flatbuffers/LICENSE.txt")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "dev" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/opencv4/3rdparty" TYPE STATIC_LIBRARY OPTIONAL FILES "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/3rdparty/lib/libade.a")
  if(EXISTS "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/opencv4/3rdparty/libade.a" AND
     NOT IS_SYMLINK "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/opencv4/3rdparty/libade.a")
    execute_process(COMMAND "/usr/bin/ranlib" "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/opencv4/3rdparty/libade.a")
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "licenses" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/share/licenses/opencv4" TYPE FILE RENAME "ade-LICENSE" FILES "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/3rdparty/ade/ade-0.1.2d/LICENSE")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "dev" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/opencv4/opencv2" TYPE FILE FILES "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/cvconfig.h")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "dev" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/opencv4/opencv2" TYPE FILE FILES "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/opencv2/opencv_modules.hpp")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "dev" OR NOT CMAKE_INSTALL_COMPONENT)
  if(EXISTS "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/opencv4/OpenCVModules.cmake")
    file(DIFFERENT _cmake_export_file_changed FILES
         "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/opencv4/OpenCVModules.cmake"
         "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/CMakeFiles/Export/51ea738ee2ea68756d9122094dacc2a4/OpenCVModules.cmake")
    if(_cmake_export_file_changed)
      file(GLOB _cmake_old_config_files "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/opencv4/OpenCVModules-*.cmake")
      if(_cmake_old_config_files)
        string(REPLACE ";" ", " _cmake_old_config_files_text "${_cmake_old_config_files}")
        message(STATUS "Old export file \"$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/opencv4/OpenCVModules.cmake\" will be replaced.  Removing files [${_cmake_old_config_files_text}].")
        unset(_cmake_old_config_files_text)
        file(REMOVE ${_cmake_old_config_files})
      endif()
      unset(_cmake_old_config_files)
    endif()
    unset(_cmake_export_file_changed)
  endif()
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/opencv4" TYPE FILE FILES "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/CMakeFiles/Export/51ea738ee2ea68756d9122094dacc2a4/OpenCVModules.cmake")
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/opencv4" TYPE FILE FILES "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/CMakeFiles/Export/51ea738ee2ea68756d9122094dacc2a4/OpenCVModules-release.cmake")
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "dev" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/opencv4" TYPE FILE FILES
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/unix-install/OpenCVConfig-version.cmake"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/unix-install/OpenCVConfig.cmake"
    )
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "scripts" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/bin" TYPE FILE PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE FILES "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/CMakeFiles/install/setup_vars_opencv4.sh")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "dev" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/share/opencv4" TYPE FILE FILES
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/platforms/scripts/valgrind.supp"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/platforms/scripts/valgrind_3rdparty.supp"
    )
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for each subdirectory.
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/3rdparty/zlib/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/3rdparty/libjpeg-turbo/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/3rdparty/libtiff/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/3rdparty/libwebp/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/3rdparty/openjpeg/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/3rdparty/libpng/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/3rdparty/protobuf/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/include/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/calib3d/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/core/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/dnn/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/features2d/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/flann/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/gapi/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/highgui/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/imgcodecs/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/imgproc/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/java/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/js/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/ml/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/objc/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/objdetect/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/photo/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/python/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/stitching/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/ts/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/video/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/videoio/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/.firstpass/world/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/modules/world/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/doc/cmake_install.cmake")
  include("/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/data/cmake_install.cmake")

endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
if(CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/install_local_manifest.txt"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
if(CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_COMPONENT MATCHES "^[a-zA-Z0-9_.+-]+$")
    set(CMAKE_INSTALL_MANIFEST "install_manifest_${CMAKE_INSTALL_COMPONENT}.txt")
  else()
    string(MD5 CMAKE_INST_COMP_HASH "${CMAKE_INSTALL_COMPONENT}")
    set(CMAKE_INSTALL_MANIFEST "install_manifest_${CMAKE_INST_COMP_HASH}.txt")
    unset(CMAKE_INST_COMP_HASH)
  endif()
else()
  set(CMAKE_INSTALL_MANIFEST "install_manifest.txt")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-arm64-maccatalyst/${CMAKE_INSTALL_MANIFEST}"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
