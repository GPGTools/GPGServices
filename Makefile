PROJECT = GPGServices
TARGET = GPGServices
PRODUCT = GPGServices
MAKE_DEFAULT = Dependencies/GPGTools_Core/newBuildSystem/Makefile.default
VPATH = build/$(CONFIG)/GPGServices.service/Contents/MacOS
NEED_LIBMACGPG = 1


-include $(MAKE_DEFAULT)

.PRECIOUS: $(MAKE_DEFAULT)
$(MAKE_DEFAULT):
	@echo "Dependencies/GPGTools_Core is missing.\nPlease clone it manually from https://github.com/GPGTools/GPGTools_Core\n"
	@exit 1

init: $(MAKE_DEFAULT)


$(PRODUCT): Source/* Resources/* Resources/*/* GPGServices.xcodeproj
	@xcodebuild -project $(PROJECT).xcodeproj -target $(TARGET) -configuration $(CONFIG) build $(XCCONFIG)

install: $(PRODUCT)
	@echo "Installing GPGServices into $(INSTALL_ROOT)Library/Services"
	@mkdir -p "$(INSTALL_ROOT)Library/Services"
	@rsync -rltDE "build/$(CONFIG)/GPGServices.service" "$(INSTALL_ROOT)Library/Services"
	@echo Done
	@echo "In order to use GPGServices, please don't forget to install MacGPG2 and Libmacgpg."
