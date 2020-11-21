Pod::Spec.new do |s|
  s.name             = "Seafile"
  s.version          = "2.9.12"
  s.summary          = "iOS client for seafile."
  s.homepage         = "https://github.com/haiwen/seafile-iOS"
  s.license          = 'MIT'
  s.author           = { "wei.wang" => "poetwang@gmail.com" }
  s.source           = { :git => "https://github.com/haiwen/seafile-iOS.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/Seafile'
  s.source_files     = 'Pod/Classes/*.{h,m}'
  s.resource_bundles = { 'Seafile' => 'Pod/Resources/*' }
  s.platform         = :ios, '8.0'
  s.requires_arc     = true
  s.frameworks       = 'AssetsLibrary'
  s.dependency 'AFNetworking', '~> 3.2.0'
  s.dependency 'OpenSSL-Universal', '~> 1.0.1.p'
  s.pod_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/OpenSSL-Universal/lib-ios/',
    'OTHER_LDFLAGS' => '$(inherited) -lssl -lcrypto'
  }
end
