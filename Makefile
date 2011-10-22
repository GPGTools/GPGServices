PROJECT = GPGServices
TARGET = GPGServices
CONFIG = Release

include Dependencies/GPGTools_Core/make/default

all: compile

update-core:
	@cd Dependencies/GPGTools_Core; git pull origin master; cd -
update-libmac:
	@cd Dependencies/Libmacgpg; git pull origin lion; cd -
update-me:
	@git pull

update: update-core update-libmac update-me

install: compile
	@echo "  * Installing...";
	@- killall GPGServices 2>/dev/null 1>/dev/null || echo
	@- killall -9 GPGServices 2>/dev/null 1>/dev/null || echo
	@mkdir -p ~/Library/Services >> build.log 2>&1
	@rm -rf ~/Library/Services/GPGServices.service >> build.log 2>&1
	@cp -r build/Release/GPGServices.service ~/Library/Services >> build.log 2>&1
	@./Dependencies/GPGTools_Core/bin/ServicesRestart
	@echo "Go to 'Preferences>Keyboard>Shortcuts>Services>Text>..."

test: deploy
