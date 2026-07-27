#!/usr/bin/env ruby
# frozen_string_literal: true

# Asserts the project invariants that break MoodCats silently.
#
# Section 16 of the spec is a list of things that fail without an error message. Most of
# them are structural and checkable here, so they are checked here rather than discovered
# on a locked phone at 2am:
#
#   - the base configuration actually resolves, so the settings it defines are not empty
#   - the App Group entitlement is on ALL THREE targets (Xcode will not warn you)
#   - the shared contract files are compiled into all three targets, not duplicated
#   - the widget and the NSE do not link Supabase, so they cannot make a network call
#   - the service role key appears nowhere in the iOS project
#   - reloadAllTimelines() is never called
#   - the extensions are embedded in the app
#
# Run:  ruby Tools/verify_project.rb

require 'xcodeproj'
require 'json'
require 'base64'

# Sources contain emoji (the mood table). Without this, File.read tags everything
# US-ASCII and every String#include? against them raises.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

ROOT = File.expand_path('..', __dir__)

def read_text(path)
  File.read(path, encoding: 'UTF-8')
end

# Strips comments, so that a rule like "never call reloadAllTimelines()" is not tripped by
# a comment that says exactly that.
def read_code(path)
  read_text(path)
    .gsub(%r{/\*.*?\*/}m, '')
    .lines.reject { |line| line.strip.start_with?('//') }
    .map { |line| line.sub(%r{\s//[^"]*$}, '') }
    .join
end
project = Xcodeproj::Project.open(File.join(ROOT, 'MoodCats.xcodeproj'))

APP = 'MoodCats'
WIDGET = 'MoodCatsWidget'
NSE = 'MoodCatsNotificationService'
SHARED_CONTRACT = %w[Config.swift Mood.swift RosterContract.swift RosterStore.swift].freeze

# App and widget only. Mirrors SHARED_UI in Tools/generate_xcodeproj.rb: the NSE runs under
# a 24 MB cap and renders nothing, so the SwiftUI layer is deliberately kept out of it.
SHARED_UI = %w[CatFaceView.swift].freeze

XCCONFIG = 'Config/Signing.xcconfig'

# Settings the xcconfig must define. If the base configuration fails to resolve these
# expand to empty rather than erroring, so the bundle id silently becomes ".moodcats" and
# the App Group entitlement becomes <string></string>.
XCCONFIG_SETTINGS = %w[BUNDLE_ID_PREFIX APP_GROUP_ID].freeze

@failures = []
@checks = 0

def check(description)
  @checks += 1
  ok = yield
  if ok
    puts "  ok    #{description}"
  else
    puts "  FAIL  #{description}"
    @failures << description
  end
rescue StandardError => e
  puts "  FAIL  #{description} (#{e.class}: #{e.message})"
  @failures << description
end

# How many build files in this target resolve to exactly this path.
#
# Compares absolute paths rather than testing a suffix. A suffix test cannot tell
# <ROOT>/Shared/Config.swift from a doubled <ROOT>/Shared/Shared/Config.swift -- the same
# class of bug that made the base configuration point at Config/Config/Signing.xcconfig and
# stopped the project building at all. Counting rather than using `any?` also catches a file
# added to one target twice, which fails the link with "duplicate output file".
def compile_count(target, absolute_path)
  target.source_build_phase.files.count do |build_file|
    reference = build_file.file_ref
    reference && File.expand_path(reference.real_path.to_s) == absolute_path
  end
end

targets = project.targets.to_h { |t| [t.name, t] }

puts "\nTargets"
check('three targets exist') { targets.keys.sort == [APP, NSE, WIDGET].sort }
check("#{APP} is an application") { targets[APP].product_type == 'com.apple.product-type.application' }
check("#{WIDGET} is an app extension") { targets[WIDGET].product_type == 'com.apple.product-type.app-extension' }
check("#{NSE} is an app extension") { targets[NSE].product_type == 'com.apple.product-type.app-extension' }

puts "\nBase configuration (if this does not resolve, every setting below it is silently empty)"
# This is the check that was missing when the base configuration pointed at
# Config/Config/Signing.xcconfig -- a path that does not exist. xcodebuild failed at
# project-load, so no Swift was ever compiled, and this script still printed
# "Project is structurally sound". Xcodeproj resolves a reference relative to its group, so
# a path that already includes the group's own directory silently doubles it.
check("the project base configuration resolves to #{XCCONFIG}") do
  expected = File.expand_path(File.join(ROOT, XCCONFIG))
  configurations = project.build_configurations
  !configurations.empty? && configurations.all? do |configuration|
    reference = configuration.base_configuration_reference
    !reference.nil? &&
      File.expand_path(reference.real_path.to_s) == expected &&
      File.exist?(reference.real_path)
  end
end
# The entitlements checks below only grep for the literal text "$(APP_GROUP_ID)"; they
# cannot tell whether that variable expands to anything. This is what gives them teeth.
check("#{XCCONFIG} defines #{XCCONFIG_SETTINGS.join(' and ')}") do
  contents = read_text(File.join(ROOT, XCCONFIG))
  # [ \t] rather than \s: Ruby's \s matches newlines, so \s*\S would happily skip a blank
  # value and match the next line, making "APP_GROUP_ID =" look defined.
  XCCONFIG_SETTINGS.all? { |setting| contents.match?(/^[ \t]*#{setting}[ \t]*=[ \t]*\S/) }
end

puts "\nApp Group entitlement (the classic 'why is my widget always empty' bug)"
[APP, WIDGET, NSE].each do |name|
  target = targets[name]
  target.build_configurations.each do |configuration|
    path = configuration.build_settings['CODE_SIGN_ENTITLEMENTS']
    check("#{name}/#{configuration.name} has CODE_SIGN_ENTITLEMENTS") { !path.nil? && !path.empty? }
    next if path.nil? || path.empty?

    contents = read_text(File.join(ROOT, path))
    check("#{name}/#{configuration.name} entitlements declare the App Group") do
      contents.include?('com.apple.security.application-groups') && contents.include?('$(APP_GROUP_ID)')
    end
  end
end

puts "\nPush entitlement is on the app only (no WidgetKit push in v1)"
check("#{APP} declares aps-environment") do
  read_text(File.join(ROOT, APP, "#{APP}.entitlements")).include?('aps-environment')
end
[WIDGET, NSE].each do |name|
  check("#{name} does NOT declare aps-environment") do
    !read_text(File.join(ROOT, name, "#{name}.entitlements")).include?('aps-environment')
  end
end
check("#{APP} Info.plist enables the remote-notification background mode") do
  read_text(File.join(ROOT, APP, 'Info.plist')).include?('remote-notification')
end

# A hardcoded `development` here is invisible in every simulator build and in every Debug
# device build. It only bites in TestFlight, where the device registers a SANDBOX token
# while NotificationManager.apnsEnvironment reports "production" -- the Edge Function then
# posts to the production APNs host, gets BadDeviceToken, and push is silently dead for
# every real user.
check("#{APP} drives aps-environment from a build setting, not a hardcoded string") do
  read_text(File.join(ROOT, APP, "#{APP}.entitlements")).include?('$(APS_ENVIRONMENT)')
end
check("#{APP} sets APS_ENVIRONMENT development in Debug and production in Release") do
  configurations = targets[APP].build_configurations
  configurations.length == 2 && configurations.all? do |configuration|
    expected = configuration.name == 'Debug' ? 'development' : 'production'
    configuration.build_settings['APS_ENVIRONMENT'] == expected
  end
end

puts "\nShared contract compiled into all three targets, exactly once each"
SHARED_CONTRACT.each do |file|
  path = File.expand_path(File.join(ROOT, 'Shared', file))
  [APP, WIDGET, NSE].each do |name|
    check("#{name} compiles Shared/#{file} exactly once") { compile_count(targets[name], path) == 1 }
  end
end

puts "\nShared SwiftUI stays out of the 24 MB Notification Service Extension"
SHARED_UI.each do |file|
  path = File.expand_path(File.join(ROOT, 'Shared', file))
  [APP, WIDGET].each do |name|
    check("#{name} compiles Shared/#{file} exactly once") { compile_count(targets[name], path) == 1 }
  end
  check("#{NSE} does NOT compile Shared/#{file}") { compile_count(targets[NSE], path).zero? }
end

puts "\nCat faces (kaomoji, not images)"
FACE_MOODS = %w[happy sad sleepy angry anxious chill excited hungry].freeze
mood_source = read_text(File.join(ROOT, 'Shared/Mood.swift'))
faces = mood_source[/public var face: String \{.*?\n    \}/m].to_s.scan(/case \.(\w+): "([^"]+)"/).to_h
placeholder = mood_source[/placeholderFace = "([^"]+)"/, 1]

check('all 8 moods define a face') { FACE_MOODS.all? { |m| faces[m] && !faces[m].empty? } }
check('a neutral placeholder face exists') { !placeholder.nil? && !placeholder.empty? }
check('every face is visually distinct') { (faces.values + [placeholder]).uniq.length == 9 }
check('every face keeps the (= =) frame and the omega muzzle') do
  (faces.values + [placeholder]).all? { |f| f.start_with?('(=') && f.end_with?('=)') && f.include?("\u03C9") }
end
check('faces differ ONLY in the eyes, never in the frame') do
  (faces.values + [placeholder]).map { |f| [f[0, 2], f[-2, 2], f.length] }.uniq.length == 1
end

# Anything outside these blocks risks tofu on a device whose font fallback differs, and
# Arabic-range characters would drag bidirectional layout into a Lock Screen widget.
SAFE_RANGES = [
  (0x20..0x7E),     # ASCII
  (0xA0..0xFF),     # Latin-1 Supplement
  (0x370..0x3FF),   # Greek (the omega muzzle)
  (0x2600..0x26FF), # Misc Symbols (star eyes)
  (0x25A0..0x25FF)  # Geometric Shapes (round eyes)
].freeze
check('faces use only fonts-guaranteed characters (no Arabic, Thai or rare CJK)') do
  offenders = (faces.values + [placeholder]).flat_map(&:chars).uniq.reject do |c|
    SAFE_RANGES.any? { |r| r.cover?(c.ord) }
  end
  puts "        offending characters: #{offenders.map { |c| format('%s U+%04X', c, c.ord) }}" unless offenders.empty?
  offenders.empty?
end

check('no image-based cat assets remain anywhere') do
  Dir.glob(File.join(ROOT, '**/cat_*.{pdf,png,svg}')).empty? &&
    !Dir.exist?(File.join(ROOT, 'Shared/CatAssets.xcassets'))
end
check('no source still references an image asset name') do
  swift_all = Dir.glob(File.join(ROOT, '{Shared,MoodCats,MoodCatsWidget,MoodCatsNotificationService}/**/*.swift'))
  swift_all.none? { |f| read_code(f).match?(/assetName|CatArtView|placeholderAssetName/) }
end
check('the app icon is 1024x1024 with no alpha channel') do
  path = File.join(ROOT, 'MoodCats/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
  next false unless File.exist?(path)
  header = File.binread(path, 26)
  width = header[16, 4].unpack1('N')
  height = header[20, 4].unpack1('N')
  colour_type = header[25].ord
  width == 1024 && height == 1024 && colour_type == 2 # 2 = truecolour, no alpha
end

puts "\nNetwork isolation"
check("#{APP} links the Supabase package") { targets[APP].package_product_dependencies.map(&:product_name) == ['Supabase'] }
[WIDGET, NSE].each do |name|
  check("#{name} links NO swift packages (it must never hit the network)") do
    targets[name].package_product_dependencies.empty?
  end
  check("#{name} does not compile SupabaseService.swift") do
    targets[name].source_build_phase.files.none? do |build_file|
      build_file.file_ref&.real_path.to_s.end_with?('SupabaseService.swift')
    end
  end
end

puts "\nExtensions embedded in the app"
embed = targets[APP].copy_files_build_phases.find { |phase| phase.symbol_dst_subfolder_spec == :plug_ins }
check('app has a PlugIns copy files phase') { !embed.nil? }
[WIDGET, NSE].each do |name|
  check("#{name} is embedded") do
    embed&.files&.any? { |f| f.display_name.include?(name) }
  end
  check("#{APP} depends on #{name}") do
    targets[APP].dependencies.any? { |d| d.target&.name == name }
  end
end

puts "\nSource-level rules from spec section 16"
swift = Dir.glob(File.join(ROOT, '{Shared,MoodCats,MoodCatsWidget,MoodCatsNotificationService}/**/*.swift'))
check('no call to reloadAllTimelines()') do
  offenders = swift.select { |f| read_code(f).include?('reloadAllTimelines') }
  puts "        offenders: #{offenders.map { |f| f.sub("#{ROOT}/", '') }}" unless offenders.empty?
  offenders.empty?
end
check('every reloadTimelines call is scoped to Config.widgetKind') do
  swift.all? do |f|
    read_code(f).scan(/reloadTimelines\(ofKind:\s*([^)]+)\)/).all? { |m| m.first.strip == 'Config.widgetKind' }
  end
end
check('at least one reloadTimelines call exists in each of app, widget-writer and NSE') do
  %w[MoodCats/AppModel.swift MoodCats/AppDelegate.swift
     MoodCatsNotificationService/NotificationService.swift].all? do |rel|
    read_code(File.join(ROOT, rel)).include?('reloadTimelines(ofKind: Config.widgetKind)')
  end
end
check('widget target makes no URLSession/network call') do
  Dir.glob(File.join(ROOT, 'MoodCatsWidget/**/*.swift')).none? do |f|
    read_code(f).match?(/URLSession|URLRequest|\.dataTask|await fetch/)
  end
end
check('NSE makes no network call and does no image work') do
  Dir.glob(File.join(ROOT, 'MoodCatsNotificationService/**/*.swift')).none? do |f|
    read_code(f).match?(/URLSession|URLRequest|UIImage|CGImage/)
  end
end

puts "\nSecrets"
tracked = Dir.glob(File.join(ROOT, '{Shared,MoodCats,MoodCatsWidget,MoodCatsNotificationService,Config}/**/*'))
           .select { |f| File.file?(f) }
check('no service_role key anywhere in the iOS project') do
  tracked.none? do |f|
    contents = File.read(f, encoding: 'BINARY')
    contents.include?('service_role') || contents.include?('SUPABASE_SERVICE_ROLE')
  end
end
check('no .p8 private key material in the repo') do
  Dir.glob(File.join(ROOT, '**/*.p8')).empty? &&
    tracked.none? { |f| File.read(f, encoding: 'BINARY').include?('BEGIN PRIVATE KEY') }
end
check('the anon key in Config.swift is a role=anon JWT') do
  source = read_text(File.join(ROOT, 'Shared/Config.swift'))
  jwt = source[/eyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+/]
  payload = JSON.parse(Base64.urlsafe_decode64(jwt.split('.')[1] + '=' * ((4 - jwt.split('.')[1].length % 4) % 4)))
  payload['role'] == 'anon'
end

puts "\nContract parity between Swift and TypeScript"
swift_moods = read_text(File.join(ROOT, 'Shared/Mood.swift')).scan(/case (\w+) = (\d)/).map { |k, v| [v.to_i, k] }.sort
ts_moods = read_text(File.join(ROOT, 'supabase/functions/set-mood/moods.ts'))
           .scan(/\{ key: "(\w+)"/).flatten.each_with_index.map { |k, i| [i, k] }
check('Mood.swift and moods.ts agree on ids and keys') { swift_moods == ts_moods }
check('both declare exactly 8 moods') { swift_moods.length == 8 }

puts "\n#{@checks - @failures.length}/#{@checks} checks passed"
if @failures.empty?
  puts 'Project is structurally sound.'
else
  puts "\nFailures:"
  @failures.each { |f| puts "  - #{f}" }
  exit 1
end
