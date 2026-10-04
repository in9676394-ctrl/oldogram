# Podfile (alternative to manual framework drop — for those who prefer pods)
#
# Usage:
#   sudo gem install cocoapods
#   cd TelegramLite/
#   pod install
#   open TelegramLite.xcworkspace
#
# ⚠️  If you use CocoaPods:
#     1. Comment out the `dependencies:` block in project.yml (if uncommented).
#     2. After `pod install`, use TelegramLite.xcworkspace (NOT .xcodeproj).
#     3. In GitHub Actions, change `xcodegen generate` to also call `pod install`.

platform :ios, '11.0'
use_frameworks!

target 'TelegramLite' do
  # TDLib community pod — wraps the official TDLib binary + a generated Swift surface.
  # If this pod fails to resolve, switch to the manual framework approach
  # described in README.md → "Where to get TDLib".
  pod 'TDLibKit', :git => 'https://github.com/iverlyy/tdlib-swift.git', :branch => 'master'

  # Optional: animated GIF playback (replaces the static-frame fallback in MessageCell.swift)
  # pod 'FLAnimatedImage', '~> 1.0'

  # Optional: progress-bar-style image loading (currently using built-in ImageLoader)
  # pod 'SDWebImage', '~> 5.12'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '11.0'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      config.build_settings['SWIFT_VERSION'] = '5.0'
    end
  end
end
