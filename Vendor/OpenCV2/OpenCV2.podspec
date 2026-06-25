Pod::Spec.new do |s|
  s.name = 'OpenCV2'
  s.version = '4.10.0'
  s.summary = 'Local OpenCV build for Mac Catalyst.'
  s.homepage = 'https://opencv.org'
  s.license = { :type => 'BSD' }
  s.author = { 'OpenCV' => 'https://opencv.org' }
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  # xcframework 只含 maccatalyst slice。
  # vendored_frameworks 处理头文件解压和 xcframework embed script；
  # post_install 会从基础 OTHER_LDFLAGS 里移除无条件的 -l"opencv_world_maccatalyst"。
  # user_target_xcconfig 的条件 key 负责只在 maccatalyst 下链接库。
  s.vendored_frameworks = 'opencv2.xcframework'
  s.libraries = 'c++', 'z'
  s.frameworks = 'Accelerate', 'CoreGraphics', 'CoreImage', 'CoreMedia', 'CoreVideo', 'Foundation', 'ImageIO', 'QuartzCore', 'UIKit'
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
  s.user_target_xcconfig = {
    # maccatalyst：用真实的 xcframework 库（有 OpenCV 符号）
    'LIBRARY_SEARCH_PATHS[sdk=maccatalyst*]' => '$(PODS_XCFRAMEWORKS_BUILD_DIR)/OpenCV2',
    # iOS/模拟器：用空 stub 库，让 -lopencv_world_maccatalyst 能链接（stub 无符号，iOS 代码不调用 OpenCV）
    'LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]' => '"${PODS_ROOT}/../Vendor/OpenCV2/stub"',
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]' => '"${PODS_ROOT}/../Vendor/OpenCV2/stub"'
    # -lopencv_world_maccatalyst 由 vendored_frameworks 和 post_install 保留在 OTHER_LDFLAGS 里
  }
end
