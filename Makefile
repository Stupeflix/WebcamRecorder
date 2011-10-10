MXMLC=mxmlc

debug:
	${MXMLC} src/WebcamRecorderApp.mxml -debug=true -incremental=true -benchmark=false -static-link-runtime-shared-libraries=true -o bin-debug/WebcamRecorderApp.swf

final:
	${MXMLC} src/WebcamRecorderApp.mxml -static-link-runtime-shared-libraries=true -link-report externals.xml -o bin-final/WebcamRecorderApp.swf