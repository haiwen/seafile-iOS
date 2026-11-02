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
  # iOS 26 SDK: <netinet6/in6.h> is a private header and #errors when
  # included directly ("include netinet/in.h instead"). AFNetworking 4.0.1 is
  # archived and still imports it, so strip the redundant import after install.
  Dir.glob(File.join(installer.sandbox.root, 'AFNetworking/AFNetworking/*.m')).each do |file|
    src = File.read(file)
    patched = src.gsub(/^#import <netinet6\/in6\.h>\n/, '')
    next if patched == src
    File.chmod(0644, file) # CocoaPods installs pod sources read-only
    File.write(file, patched)
  end

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      # OpenSSL-Universal and WechatOpenSDK ship fat .a archives without an
      # arm64-simulator slice, so simulator builds must stay x86_64.
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = "arm64"
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
end
