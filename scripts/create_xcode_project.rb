#!/usr/bin/env ruby

require "xcodeproj"

project_path = "Aiyifan.xcodeproj"
project = Xcodeproj::Project.new(project_path)

deployment_target = "17.0"
bundle_id = "com.john.aiyifan"
team_id = "VGGZ34H2PS"

project.root_object.attributes["LastSwiftUpdateCheck"] = "2620"
project.root_object.attributes["LastUpgradeCheck"] = "2620"
project.root_object.attributes["TargetAttributes"] = {}

app_target = project.new_target(:application, "Aiyifan", :ios, deployment_target)
project.root_object.attributes["TargetAttributes"][app_target.uuid] = {
  "CreatedOnToolsVersion" => "26.2"
}

app_group = project.main_group.new_group("Aiyifan", "Aiyifan")
source_group = app_group.new_group("App", "App")
resource_group = app_group.new_group("Resources", "Resources")

Dir["Aiyifan/App/*.swift"].sort.each do |path|
  file_ref = source_group.new_file(File.basename(path))
  app_target.add_file_references([file_ref])
end

info_ref = resource_group.new_file("Info.plist")
entitlements_ref = app_group.new_file("Aiyifan.entitlements")

project.build_configurations.each do |config|
  config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = deployment_target
  config.build_settings["SWIFT_VERSION"] = "6.0"
end

app_target.build_configurations.each do |config|
  settings = config.build_settings
  settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = ""
  settings["CODE_SIGN_ENTITLEMENTS"] = "Aiyifan/Aiyifan.entitlements"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["CURRENT_PROJECT_VERSION"] = "1"
  settings["DEVELOPMENT_TEAM"] = team_id
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["INFOPLIST_FILE"] = "Aiyifan/Resources/Info.plist"
  settings["IPHONEOS_DEPLOYMENT_TARGET"] = deployment_target
  settings["MARKETING_VERSION"] = "1.0"
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_id
  settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  settings["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
  settings["SUPPORTS_MACCATALYST"] = "NO"
  settings["SWIFT_VERSION"] = "6.0"
  settings["TARGETED_DEVICE_FAMILY"] = "1,2"
end

project.save
