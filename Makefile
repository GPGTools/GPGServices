all: compile

update:
	@git submodule foreach git pull origin master
	@git pull

compile:
	@echo "(have a look at build.log for details)";
	@echo "" > build.log
	@echo "  * Building...(can take some minutes)";
	@xcodebuild -project GPGServices.xcodeproj -target GPGServices -configuration Release build >> build.log 2>&1

install: compile
	@echo "  * Installing...";
	@- killall GPGServices 2>/dev/null 1>/dev/null || echo
	@- killall -9 GPGServices 2>/dev/null 1>/dev/null || echo
	@mkdir -p ~/Library/Services >> build.log 2>&1
	@rm -rf ~/Library/Services/GPGServices.service >> build.log 2>&1
	@cp -r build/Release/GPGServices.service ~/Library/Services >> build.log 2>&1
	@./Dependencies/GPGTools_Core/bin/ServicesRestart
	@echo "Go to 'Preferences>Keyboard>Shortcuts>Services>Text>..."

dmg: clean-gpgservices update compile
	@./Dependencies/GPGTools_Core/scripts/create_dmg.sh

clean-gpgme:
	rm -rf Dependencies/MacGPGME/build

clean-gpgservices:
	xcodebuild -project GPGServices.xcodeproj -target GPGServices -configuration Release clean > /dev/null
	xcodebuild -project GPGServices.xcodeproj -target GPGServices -configuration Debug clean > /dev/null

clean: clean-gpgme clean-gpgservices

check-all-warnings: clean-gpgservices
	make | grep "warning: "

check-warnings: clean-gpgservices
	make | grep "warning: "|grep -v "#warning"

check: clean-gpgservices
	@if [ "`which scan-build`" == "" ]; then echo 'usage: PATH=$$PATH:path_to_scan_build make check'; echo "see: http://clang-analyzer.llvm.org/"; exit; fi
	@echo "";
	@echo "Have a closer look at these warnings:";
	@echo "=====================================";
	@echo "";
	@scan-build -analyzer-check-objc-missing-dealloc \
	            -analyzer-check-dead-stores \
	            -analyzer-check-idempotent-operations \
	            -analyzer-check-llvm-conventions \
	            -analyzer-check-objc-mem \
	            -analyzer-check-objc-methodsigs \
	            -analyzer-check-objc-missing-dealloc \
	            -analyzer-check-objc-unused-ivars \
	            -analyzer-check-security-syntactic \
	            --use-cc clang -o build/report xcodebuild \
	            -project GPGServices.xcodeproj -target GPGServices \
	            -configuration Release build 2>error.log|grep "is deprecated"
	@echo "";
	@echo "Now have a look at build/report/ or at error.log";

style:
	@if [ "`which uncrustify`" == "" ]; then echo 'usage: PATH=$$PATH:path_to_uncrustify make style'; echo "see: https://github.com/bengardner/uncrustify"; exit; fi
	uncrustify -c Utilities/uncrustify.cfg --no-backup Source/*.h
	uncrustify -c Utilities/uncrustify.cfg --no-backup Source/*.m

