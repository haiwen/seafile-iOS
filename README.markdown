
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

Please submit translations via Transifex: [https://www.transifex.com/projects/p/seafile-ios/](https://www.transifex.com/projects/p/seafile-ios/)

Steps:

1. Create a free account on Transifex ([https://www.transifex.com/](https://www.transifex.com/)).

2. Send a request to join the language translation.

3. After accepted by the project maintainer, then you can upload your file or translate online.
