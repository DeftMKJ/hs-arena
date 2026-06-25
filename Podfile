platform :ios, '15.0'
use_frameworks!

target 'HearthStoneDraftAssistant' do
  pod 'SnapKit', '~> 5.7'
  pod 'SDWebImage', '~> 5.20'
  # OpenCV2 xcframework 只含 maccatalyst slice。
  # post_install 会把链接参数限制为 [sdk=maccatalyst*] 条件，iOS/模拟器构建时不链接。
  pod 'OpenCV2', :path => './Vendor/OpenCV2'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end

  # OpenCV2 xcframework 只含 maccatalyst slice。
  # 策略：保留 -l"opencv_world_maccatalyst" 在所有平台的 OTHER_LDFLAGS 里；
  # iOS/模拟器通过 Vendor/OpenCV2/stub/ 里的空 stub 库满足链接（无符号，代码层已 #if 隔离）；
  # Mac Catalyst 通过真实的 xcframework 库满足链接。
  # LIBRARY_SEARCH_PATHS 的条件 key 已在 podspec user_target_xcconfig 里设置。
  # 无需额外 xcconfig 补丁。
end
