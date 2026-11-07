def shared
  platform :ios, '16.0'
  pod 'Seafile', :path => "./"
  pod 'AFNetworking', '~> 4.0.0'
  pod 'OpenSSL-Universal', '1.0.2.17'
  pod 'APLRUCache', '~> 1.0.0'
  pod 'UniversalDetector'
end

target :"seafileApp" do
  pod 'SVPullToRefresh', :git => 'https://github.com/lilthree/SVPullToRefresh.git', :branch => 'master'
  pod 'SVProgressHUD', :git => 'https://github.com/SVProgressHUD/SVProgressHUD', :tag =>'1.1.3'
  pod 'SWTableViewCell', :git => 'https://github.com/haiwen/SWTableViewCell.git', :branch => 'master'
  pod 'MWPhotoBrowser', :git => 'https://github.com/haiwen/MWPhotoBrowser.git', :branch => 'master'
  pod 'WechatOpenSDK', '~> 1.8.7.1'
  shared
end


target :"SeafFileProvider" do
  shared
end

target :"SeafAction" do
  pod 'SVPullToRefresh', :git => 'https://github.com/lilthree/SVPullToRefresh.git', :branch => 'master'
  shared
end

target :"SeafShare" do
    pod 'SVPullToRefresh', :git => 'https://github.com/lilthree/SVPullToRefresh.git', :branch => 'master'
    shared
end

# https://github.com/CocoaPods/CocoaPods/issues/8069
# https://github.com/CocoaPods/CocoaPods/issues/11402
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 16.0
          config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      end
    end
    if target.respond_to?(:product_type) and target.product_type == "com.apple.product-type.bundle"
      target.build_configurations.each do |config|
          config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      end
    end
  end

  # OpenSSL-Universal and WechatOpenSDK ship fat .a archives without an
  # arm64-simulator slice. Simulator builds link OpenSSL from
  # Vendor/OpenSSL-simulator/lib (run Vendor/OpenSSL-simulator/build.sh once)
  # and skip WeChat entirely; device builds are untouched.
  # A conditional `KEY[sdk=...] = $(inherited) ...` in the same xcconfig would
  # inherit the unconditional value of that file, so route the difference
  # through helper variables that are only non-empty for one SDK.
  installer.aggregate_targets.each do |aggregate|
    aggregate.user_build_configurations.each_key do |config_name|
      path = aggregate.xcconfig_path(config_name)
      xcconfig = File.read(path)
      extra = []
      if xcconfig =~ /^LIBRARY_SEARCH_PATHS = .*OpenSSL-Universal/
        xcconfig.sub!(/^LIBRARY_SEARCH_PATHS = /, 'LIBRARY_SEARCH_PATHS = $(SEAF_OPENSSL_SIM_LIB) ')
        extra << 'SEAF_OPENSSL_SIM_LIB[sdk=iphonesimulator*] = "${PODS_ROOT}/../Vendor/OpenSSL-simulator/lib"'
      end
      if xcconfig =~ /^OTHER_LDFLAGS = .* -l"WeChatSDK"/
        xcconfig.sub!(/^(OTHER_LDFLAGS = .*) -l"WeChatSDK"/, '\1 $(SEAF_WECHAT_LDFLAGS)')
        extra << 'SEAF_WECHAT_LDFLAGS = -l"WeChatSDK"'
        extra << 'SEAF_WECHAT_LDFLAGS[sdk=iphonesimulator*] ='
      end
      File.write(path, xcconfig.rstrip + "\n" + extra.join("\n") + "\n") unless extra.empty?
    end
  end
end
