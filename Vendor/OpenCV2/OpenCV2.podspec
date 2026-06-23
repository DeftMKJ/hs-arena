Pod::Spec.new do |s|
  s.name = 'OpenCV2'
  s.version = '4.10.0'
  s.summary = 'Local OpenCV build for Mac Catalyst.'
  s.homepage = 'https://opencv.org'
  s.license = { :type => 'BSD' }
  s.author = { 'OpenCV' => 'https://opencv.org' }
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  s.vendored_frameworks = 'opencv2.xcframework'
  s.libraries = 'c++', 'z'
  s.frameworks = 'Accelerate', 'CoreGraphics', 'CoreImage', 'CoreMedia', 'CoreVideo', 'Foundation', 'ImageIO', 'QuartzCore', 'UIKit'
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
end
