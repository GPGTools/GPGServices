PROJECT = GPGServices
TARGET = GPGServices
PRODUCT = GPGServices.service

include Dependencies/GPGTools_Core/newBuildSystem/Makefile.default


update: update-libmacgpg

pkg: pkg-libmacgpg

clean-all: clean-libmacgpg

$(PRODUCT): Source/* Resources/* Resources/*/* GPGServices.xcodeproj
	@xcodebuild -project $(PROJECT).xcodeproj -target $(TARGET) -configuration $(CONFIG) build $(XCCONFIG)

