Pod::Spec.new do |s|
  s.name             = 'TorClient'
  s.version          = '409.5.1'
  s.summary          = 'Local Tor client wrapper'
  s.description      = 'A local pod to avoid name collisions with the official Tor.framework.'
  s.homepage         = 'https://github.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Guido' => 'guido@example.com' }
  s.source           = { :path => '.' }

  s.ios.deployment_target = '15.0'

  # Include both Core and CTor sources
  s.source_files = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.vendored_frameworks = 'tor.xcframework'
  
  s.libraries = 'z'
  s.frameworks = 'Foundation'
  
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -all_load',
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/tor.xcframework/ios-arm64/tor.framework/Headers"'
  }
end
