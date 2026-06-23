require 'xcodeproj'

project_path = 'HearthStoneDraftAssistant.xcodeproj'
project = Xcodeproj::Project.new(project_path)

app_target = project.new_target(
  :application,
  'HearthStoneDraftAssistant',
  :ios,
  '15.0'
)

app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.hearthstone.draftassistant'
  config.build_settings['INFOPLIST_FILE'] = 'HearthStoneDraftAssistant/Resources/Info.plist'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['SUPPORTS_MACCATALYST'] = 'YES'
  config.build_settings['DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER'] = 'NO'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
end

sources_group = project.new_group('HearthStoneDraftAssistant', 'HearthStoneDraftAssistant')
app_group = sources_group.new_group('App', 'App')
resources_group = sources_group.new_group('Resources', 'Resources')
data_group = project.new_group('HearthDraftData', 'Sources/HearthDraftData')

app_sources = Dir['HearthStoneDraftAssistant/App/*.swift']
data_sources = Dir['Sources/HearthDraftData/*.swift']

(app_sources + data_sources).each do |path|
  group = path.start_with?('HearthStoneDraftAssistant/App') ? app_group : data_group
  file_ref = group.new_file(File.basename(path))
  app_target.add_file_references([file_ref])
end

resources_group.new_file('Info.plist')

project.save
