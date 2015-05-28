PRODUCT = GPGServices
VPATH = build/Release/GPGServices.service/Contents/MacOS

all: $(PRODUCT)

$(PRODUCT): Source/* Resources/* Resources/*/* GPGServices.xcodeproj
	xcodebuild -project GPGServices.xcodeproj -target GPGServices build $(XCCONFIG)

clean:
	rm -rf ./build
