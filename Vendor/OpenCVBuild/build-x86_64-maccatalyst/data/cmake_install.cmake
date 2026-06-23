# Install script for directory: /Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/install-x86_64-maccatalyst")
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

if(CMAKE_INSTALL_COMPONENT STREQUAL "libs" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/share/opencv4/haarcascades" TYPE FILE FILES
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_eye.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_eye_tree_eyeglasses.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_frontalcatface.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_frontalcatface_extended.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_frontalface_alt.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_frontalface_alt2.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_frontalface_alt_tree.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_frontalface_default.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_fullbody.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_lefteye_2splits.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_license_plate_rus_16stages.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_lowerbody.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_profileface.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_righteye_2splits.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_russian_plate_number.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_smile.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/haarcascades/haarcascade_upperbody.xml"
    )
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "libs" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/share/opencv4/lbpcascades" TYPE FILE FILES
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/lbpcascades/lbpcascade_frontalcatface.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/lbpcascades/lbpcascade_frontalface.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/lbpcascades/lbpcascade_frontalface_improved.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/lbpcascades/lbpcascade_profileface.xml"
    "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/opencv-4.10.0/data/lbpcascades/lbpcascade_silverware.xml"
    )
endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
if(CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "/Users/bytedance/Workspace/hearth-stone/Vendor/OpenCVBuild/build-x86_64-maccatalyst/data/install_local_manifest.txt"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
