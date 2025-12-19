# Podfile for KomgaReaderAntigravity
platform :ios, '15.0'

target 'KomgaReaderAntigravity' do
  use_frameworks!

  # OpenCV for advanced image processing (using latest available version)
  pod 'OpenCV'
  
  # Firebase/Google ML Kit (if needed for future enhancements)
  # pod 'GoogleMLKit/TextRecognition'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      
      # Allow building for both device and simulator
      config.build_settings.delete('VALID_ARCHS')
      
      # For simulators only, exclude arm64 to work with OpenCV
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
    end
  end
end
