
Introduction
============

Seafile-iOS is a the iOS client for [Seafile](http://www.seafile.com).

Build and Run
=============

Follow these steps :

	git clone https://github.com/haiwen/seafile-iOS.git
	cd seafile-iOS
    pod install
    open seafilePro.xcworkspace

Then you can run seafile in xcode simulator.


SDK and Integration
=================
The seafile SDK is is under development and the api will be clarified soon.
Now, you can use CocoaPods to integrate Seafile in your app.

    pod 'Seafile', :git => 'https://github.com/haiwen/seafile-iOS.git'

If it failed with the following error:

    target has transitive dependencies that include static binaries

Add the following line to your Podfile.

    pre_install do |installer|
        # workaround for https://github.com/CocoaPods/CocoaPods/issues/3289
        def installer.verify_no_static_framework_transitive_dependencies; end
    end


Internationalization (I18n)
==========

Please submit translations via Transifex:

Steps:

1. Visit the webpage of Transifex ([https://explore.transifex.com/haiwen/seafile-ios/](https://explore.transifex.com/haiwen/seafile-ios/)).

2. Click the "Join this project" button in the bottom right corner.

3. Use an email or GitHub account(recommended) to create an account.

4. Select a language and click 'Join project' to join the language translation.

5. After accepted by the project maintainer, then you can upload your file or translate online.
