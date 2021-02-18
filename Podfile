def shared
  platform :ios, '8.0'
  pod 'Seafile', :path => "./"
  pod 'AFNetworking', '~> 3.2.0'
  pod 'OpenSSL-Universal', '1.0.2.17'
  pod 'APLRUCache', '~> 1.0.0'
end

target :"seafileApp" do
  pod 'SVPullToRefresh', :git => 'https://github.com/lilthree/SVPullToRefresh.git', :branch => 'master'
  pod 'SVProgressHUD', '~> 1.1.3'
  pod 'SWTableViewCell', :git => 'https://github.com/haiwen/SWTableViewCell.git', :branch => 'master'
  pod 'MWPhotoBrowser', :git => 'https://github.com/haiwen/MWPhotoBrowser.git', :branch => 'master'
  pod 'QBImagePickerController', :git => 'https://github.com/haiwen/QBImagePickerController.git', :branch => 'master'
  pod 'WechatOpenSDK', '1.8.5'
  pod 'Bugly'
  shared
end


target :"SeafFileProvider" do
  pod 'BuglyExtension'
  shared
end

target :"SeafFileProviderUI" do
  shared
end

target :"SeafAction" do
  pod 'SVPullToRefresh', :git => 'https://github.com/lilthree/SVPullToRefresh.git', :branch => 'master'
  shared
end

target :"SeafShare" do
    pod 'BuglyExtension'
    pod 'SVPullToRefresh', :git => 'https://github.com/lilthree/SVPullToRefresh.git', :branch => 'master'
    shared
end

# https://github.com/CocoaPods/CocoaPods/issues/8069
post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 8.0
                config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '8.0'
            end
        end
    end
end
