def shared
  platform :ios, '8.0'
  pod 'Seafile', :path => "./"
  pod 'AFNetworking', '~> 2.6.1'
  pod 'OpenSSL-Universal', '~> 1.0.1.p'
  pod 'APLRUCache', '~> 1.0.0'
end

target :"seafileApp" do
  pod 'SVPullToRefresh', :git => 'https://github.com/lilthree/SVPullToRefresh.git', :branch => 'master'
  pod 'SVProgressHUD', '~> 1.1.3'
  pod 'SWTableViewCell', :git => 'https://github.com/haiwen/SWTableViewCell.git', :branch => 'master'
  pod 'MWPhotoBrowser', :git => 'https://github.com/haiwen/MWPhotoBrowser.git', :branch => 'master'
  pod 'QBImagePickerController', :git => 'https://github.com/haiwen/QBImagePickerController.git', :branch => 'master'
  shared
end


target :"SeafFileProvider" do
  shared
end

target :"SeafFileProviderUI" do
  shared
end

target :"SeafAction" do
  pod 'SVPullToRefresh', :git => 'https://github.com/lilthree/SVPullToRefresh.git', :branch => 'master'
  shared
end
