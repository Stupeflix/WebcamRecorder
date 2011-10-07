#AMXMLC=/Users/lagunas/devel/stupeflix/website/website/imageupload/flex/bin/amxmlc
AMXMLC=/Users/lagunas/devel/flex/flex_sdk_4.1.0.16076_mpl/bin/amxmlc

all:
	${AMXMLC} src/WebcamRecorder.as -debug=true -incremental=true -benchmark=false -o bin-debug/WebcamRecorderApp.swf