PROJECT = GPGServices
TARGET = GPGServices
PRODUCT = GPGServices.service
MAKE_DEFAULT = Dependencies/GPGTools_Core/newBuildSystem/Makefile.default

ifneq "$(wildcard $(MAKE_DEFAULT))" ""
	include $(MAKE_DEFAULT)
endif

$(MAKE_DEFAULT):
	@bash -c "$$(curl -fsSL https://raw.github.com/GPGTools/GPGTools_Core/master/newBuildSystem/prepare-core.sh)"

init: $(MAKE_DEFAULT)

update: update-libmacgpg

pkg: pkg-libmacgpg

clean-all: clean-libmacgpg

$(PRODUCT): Source/* Resources/* Resources/*/* GPGServices.xcodeproj
	@xcodebuild -project $(PROJECT).xcodeproj -target $(TARGET) -configuration $(CONFIG) build $(XCCONFIG)

