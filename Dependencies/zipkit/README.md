ZipKit
======

ZipKit is an Objective-C framework for reading and writing Zip archives in Mac OS X and iOS apps. It supports:
* the standard [PKZip format](http://www.pkware.com/documents/casestudies/APPNOTE.TXT);
* files larger than 4GB in size using PKZip's zip64 extensions (ZKFileArchive only);
* optionally, resource forks in a manner compatible with Mac OS X's Archive Utility (in the Mac OS X targets only);
* clean interruption, so archiving can be cancelled by the invoking object (e.g., a NSOperation or NSThread).
It was developed by Karl Moskowski (aka [@kolpanic](https://twitter.com/kolpanic)) and released under the BSD license.

If you find ZipKit to be useful, please [let me know](http://about.me/kolpanic).

###Requirements

ZipKit requires Xcode 4.6. It works on OS X 10.8 Mountain Lion, and iOS 6.0 or greater. (If you're using older versions, make sure you "git checkout 1.0.0". The project at that tag supports garbage collection and manual memory management.) The Xcode project contains three targets:
* an OS X framework;
* an OS X static library;
* an iOS static library.

###Using ZipKit

1. If you're using git for your project, first add ZipKit as a submodule to your project. If you're not using git, clone ZipKit into your project's directory. (If you're using another VCS, you might want to ignore the ZipKit sub-project, or its .git/ directory.)
2. Open your .xcodeproj and drag ZipKit.xcodeproj from the Finder to Xcode's Project Navigator for your project. The Frameworks group is a good place for it.
3. In the Project Navigator for your project, disclose ZipKit's Products and note the one you want to use in your project.
4. In the Project Navigator, select your project at the top, then:
	* add the relevant ZipKit product to your target's Linked Frameworks and Libraries section, and add it to the your target's Target Dependencies under Build Phases;
	* add libz.dylib to your target's Linked Frameworks;
	* add ./ZipKit/ to your target's User Header Search Paths setting.
5. If you're using one of ZipKit's static library targets in your project, add -ObjC to your target's Other Linker Flags. You may have to add -all_load as well. (Objective-C categories aren't properly linked by default when using static libraries.)
 
See the accompanying demo projects for guidance.

###License

ZipKit is released under the BSD license. It's in COPYING.TXT in the project. Acknowledge ZipKit (and other FOSS projects you use) in your app's About or Settings view or window. (If your iOS app doesn't have either, you can add a Settings Bundle; see the ZipKit Touch demo.)

###Demo Projects
* [ZipKit Utility](https://github.com/kolpanic/ZipKit-Utility) - an OS X Cocoa application
* [zku](https://github.com/kolpanic/zku) - an OS X command line tool
* [ZipKit Touch](https://github.com/kolpanic/ZipKit-Touch) - an iOS application

####Note
This project was originally a Mercurial repository hosted at Bitbucket. It was converted to git using [fast-export](https://github.com/frej/fast-export), and all open issues were manually copied here.
