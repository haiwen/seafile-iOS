def shared
  platform :ios, '7.0'
  pod 'AFNetworking', '~> 2.6.1'
  pod 'OpenSSL-Universal', '~> 1.0.1.p'
  pod 'DACircularProgress', '~> 2.3.1'
end

target :"seafile-appstore" do
  pod 'EGOTableViewPullRefresh', '~> 0.1.0'
  pod 'SVProgressHUD', '~> 1.1.3'
  pod 'SWTableViewCell', :git => 'https://github.com/haiwen/SWTableViewCell.git', :branch => 'master'
  pod 'MWPhotoBrowser', :git => 'https://github.com/haiwen/MWPhotoBrowser.git', :branch => 'dev'
  shared
end


target :"SeafProvider" do
  pod 'SWTableViewCell', :git => 'https://github.com/haiwen/SWTableViewCell.git', :branch => 'master'
  shared
end

target :"SeafProviderFileProvider" do
  shared
end
