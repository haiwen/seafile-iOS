def shared
  platform :ios, '7.0'
  pod 'AFNetworking', '~> 2.6.1'
  pod 'OpenSSL-Universal', '~> 1.0.1.p'
  pod 'DACircularProgress', '~> 2.3.1'
  pod 'SVProgressHUD', '~> 1.1.3'
end

target :"seafile-appstore" do
  pod 'EGOTableViewPullRefresh', '~> 0.1.0'
  pod 'MWPhotoBrowser', '~> 2.1.1'
  shared
end


target :"SeafProvider" do
  shared
end

target :"SeafProviderFileProvider" do
  shared
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['APPLICATION_EXTENSION_API_ONLY'] == 'YES'
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)', 'SV_APP_EXTENSIONS=1']
      end
    end
  end
end
