platform :ios, '15.0'
use_frameworks!

target 'HearthStoneDraftAssistant' do
  pod 'SnapKit', '~> 5.7'
  pod 'SDWebImage', '~> 5.20'

  # OpenCV CocoaPods currently found in trunk are iOS-only and do not ship a
  # Mac Catalyst slice. Keep this disabled until we provide a local
  # opencv2.xcframework that contains ios-arm64_x86_64-maccatalyst.
  # pod 'OpenCV-Dynamic-Framework', '~> 4.10.0.1'
  pod 'OpenCV2', :path => './Vendor/OpenCV2'
end
