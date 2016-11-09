require 'json'
require 'ipa_analyzer'
require 'optparse'
require 'zip'
require 'zip/filesystem'
require 'pngdefry'

# -----------------------
# --- functions
# -----------------------

def fail_with_message(message)
  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def get_ios_ipa_info(ipa_path)

  parsed_ipa_infos = {
    mobileprovision: nil,
    info_plist: nil
  }

  ipa_analyzer = IpaAnalyzer::Analyzer.new(ipa_path)
   begin
    ipa_analyzer.open!

    parsed_ipa_infos[:mobileprovision] = ipa_analyzer.collect_provision_info
    parsed_ipa_infos[:info_plist] = ipa_analyzer.collect_info_plist_info
    fail 'Failed to collect Info.plist information' if parsed_ipa_infos[:info_plist].nil?
  rescue => ex
    puts
    puts "Failed: #{ex}"
    puts
    raise ex
  ensure
    puts '  => Closing the IPA'
    ipa_analyzer.close
  end

  ipa_file_size = File.size(ipa_path)

    icon_zip_path = ''
    ipa_zipfile = Zip::File.open(ipa_path)
    ipa_zipfile.dir.entries("Payload").each do |dir_entry|
      ipa_zipfile.dir.entries("Payload/#{dir_entry}").each do |file_entry|
        if file_entry =~ /^AppIcon.*png$/
          icon_zip_path = "Payload/#{dir_entry}/#{file_entry}"
        end
      end
    end

    if icon_zip_path
      icon_file_path = "#{File.dirname(ipa_path)}/icon.png"
      ipa_zipfile.extract(icon_zip_path, icon_file_path){ override = true }

      Pngdefry.defry(icon_file_path, icon_file_path)
    end

  info_plist_content = parsed_ipa_infos[:info_plist][:content]
  mobileprovision_content = parsed_ipa_infos[:mobileprovision][:content]
  ipa_info_hsh = {
    file_size_bytes: ipa_file_size,
    icon_path: icon_file_path,
    app_info: {
      app_title: info_plist_content['CFBundleName'],
      bundle_id: info_plist_content['CFBundleIdentifier'],
      version: info_plist_content['CFBundleShortVersionString'],
      build_number: info_plist_content['CFBundleVersion'],
      min_OS_version: info_plist_content['MinimumOSVersion'],
      device_family_list: info_plist_content['UIDeviceFamily']
    },
    provisioning_info: {
      creation_date: mobileprovision_content['CreationDate'],
      expire_date: mobileprovision_content['ExpirationDate'],
      team_name: mobileprovision_content['TeamName'],
      profile_name: mobileprovision_content['Name'],
      provisions_all_devices: mobileprovision_content['ProvisionsAllDevices'],
    }
  }
  puts "=> IPA Info: #{ipa_info_hsh}"

  return ipa_info_hsh
end

# ----------------------------
# --- Options

options = {
  ipa_path: nil,
}

parser = OptionParser.new do|opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-a', '--ipapath PATH', 'IPA Path') { |d| options[:ipa_path] = d unless d.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

fail_with_message('No ipa_path provided') unless options[:ipa_path]

options[:ipa_path] = File.absolute_path(options[:ipa_path])

if !Dir.exist?(options[:ipa_path]) && !File.exist?(options[:ipa_path])
  fail_with_message('IPA path does not exist: ' + options[:ipa_path])
end

puts "=> IPA path: #{options[:ipa_path]}"

# ----------------------------
# --- Main

begin
    ipa_info_hsh = ""
    if options[:ipa_path].match('.*.ipa')
      ipa_info_hsh = get_ios_ipa_info(options[:ipa_path])
    end

    # - Success
    fail 'Failed to export IOS_IPA_PACKAGE_NAME' unless system("envman add --key IOS_IPA_PACKAGE_NAME --value '#{ipa_info_hsh[:app_info][:bundle_id]}'")
    fail 'Failed to export IOS_IPA_FILE_SIZE' unless system("envman add --key IOS_IPA_FILE_SIZE --value '#{ipa_info_hsh[:file_size_bytes]}'")
    fail 'Failed to export IOS_APP_NAME' unless system("envman add --key IOS_APP_NAME --value '#{ipa_info_hsh[:app_info][:app_title]}'")
    fail 'Failed to export IOS_APP_VERSION_NAME' unless system("envman add --key IOS_APP_VERSION_NAME --value '#{ipa_info_hsh[:app_info][:version]}'")
    fail 'Failed to export IOS_APP_VERSION_CODE' unless system("envman add --key IOS_APP_VERSION_CODE --value '#{ipa_info_hsh[:app_info][:build_number]}'")
    fail 'Failed to export IOS_ICON_PATH' unless system("envman add --key IOS_ICON_PATH --value '#{ipa_info_hsh[:icon_path]}'")
    fail 'Failed to export IOS_APP_PROFILE_NAME' unless system("envman add --key IOS_APP_PROFILE_NAME --value '#{ipa_info_hsh[:provisioning_info][:profile_name]}'")
rescue => ex
  fail_with_message(ex)
end

exit 0