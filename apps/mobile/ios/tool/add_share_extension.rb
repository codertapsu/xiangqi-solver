#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Wires the iOS share-in feature into Runner.xcodeproj (idempotent).
#
# `flutter create` does not know about app extensions, so this script adds what
# the GUI "File > New > Target > Share Extension" would, using the xcodeproj gem
# that ships with CocoaPods. Re-running is safe.
#
#   ruby ios/tool/add_share_extension.rb
#
# It:
#   1. registers `vi` as a known region + adds the InfoPlist.strings variant
#      group (en, vi) to Runner's resources (per-device-locale app name);
#   2. sets the App Group entitlement on the Runner target;
#   3. creates the `ShareExtension` app-extension target (ShareViewController.swift
#      + Info.plist + entitlements + build settings);
#   4. embeds the extension into Runner and adds it as a dependency.

require 'xcodeproj'

PROJECT = File.expand_path('../Runner.xcodeproj', __dir__)
APP_GROUP = 'group.com.codertapsu.xiangqiSolver'
EXT_NAME = 'ShareExtension'
EXT_BUNDLE_ID = 'com.codertapsu.xiangqiSolver.ShareExtension'

project = Xcodeproj::Project.open(PROJECT)
runner = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' unless runner

# --- 1. known regions + localized InfoPlist.strings variant group -----------
root = project.root_object
%w[en vi Base].each { |r| root.known_regions << r unless root.known_regions.include?(r) }

runner_group = project.main_group['Runner']
unless runner_group.children.any? { |c| c.display_name == 'InfoPlist.strings' }
  variant = runner_group.new_variant_group('InfoPlist.strings')
  %w[en vi].each do |lang|
    ref = variant.new_reference("#{lang}.lproj/InfoPlist.strings")
    ref.name = lang
  end
  runner.resources_build_phase.add_file_reference(variant)
  puts '  + added InfoPlist.strings variant group (en, vi)'
end

# --- 2. Runner App Group entitlement ----------------------------------------
runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end
puts '  + set Runner CODE_SIGN_ENTITLEMENTS'

# --- 3. ShareExtension target ------------------------------------------------
if project.targets.any? { |t| t.name == EXT_NAME }
  puts "  = #{EXT_NAME} target already exists — skipping creation"
else
  ext = project.new_target(:app_extension, EXT_NAME, :ios, '13.0')

  ext_group = project.main_group.new_group(EXT_NAME, EXT_NAME)
  swift_ref = ext_group.new_reference('ShareViewController.swift')
  ext.source_build_phase.add_file_reference(swift_ref)
  ext_group.new_reference('Info.plist')
  ext_group.new_reference("#{EXT_NAME}.entitlements")

  ext.build_configurations.each do |c|
    bs = c.build_settings
    bs['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_BUNDLE_ID
    bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
    bs['INFOPLIST_FILE'] = "#{EXT_NAME}/Info.plist"
    bs['CODE_SIGN_ENTITLEMENTS'] = "#{EXT_NAME}/#{EXT_NAME}.entitlements"
    bs['SWIFT_VERSION'] = '5.0'
    bs['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    bs['TARGETED_DEVICE_FAMILY'] = '1,2'
    bs['CURRENT_PROJECT_VERSION'] = '3'    # keep in sync with the app on release
    bs['MARKETING_VERSION'] = '1.0.0'      # keep in sync with the app on release
    bs['SKIP_INSTALL'] = 'YES'
    bs['GENERATE_INFOPLIST_FILE'] = 'NO'
    bs['CLANG_ENABLE_MODULES'] = 'YES'
    bs['CODE_SIGN_STYLE'] = 'Automatic'
    bs['LD_RUNPATH_SEARCH_PATHS'] =
      ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  end

  # --- 4. embed into Runner + dependency ------------------------------------
  runner.add_dependency(ext)
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
  bf = embed.add_file_reference(ext.product_reference)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts "  + created #{EXT_NAME} app-extension target + embedded it in Runner"
end

# --- 5. order: embed the extension BEFORE Flutter's "Thin Binary" -----------
# Otherwise the appex copy (writing Runner.app/PlugIns) and Thin Binary (scanning
# Runner.app) form a build dependency cycle.
phases = runner.build_phases
embed = phases.find { |ph| ph.display_name == 'Embed Foundation Extensions' }
thin = phases.find { |ph| ph.display_name == 'Thin Binary' }
if embed && thin && phases.index(embed) > phases.index(thin)
  phases.delete(embed)
  phases.insert(phases.index(thin), embed)
  puts '  + moved "Embed Foundation Extensions" before "Thin Binary"'
end

project.save
puts "Done: #{PROJECT}"
