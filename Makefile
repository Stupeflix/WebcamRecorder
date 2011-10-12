FLEX=
FLEXBIN=${FLEX}/bin
MXMLC=${FLEXBIN}/mxmlc
OPTIMIZER=${FLEXBIN}/optimizer

debug:
	${MXMLC} -debug=true -incremental=true -benchmark=false -static-link-runtime-shared-libraries=true -o bin-debug/WebcamRecorderApp.swf src/WebcamRecorderApp.mxml

final:
	${MXMLC} -optimize=true -static-link-runtime-shared-libraries=true -o bin-final/WebcamRecorderApp.tmp.swf src/WebcamRecorderApp.mxml
	${OPTIMIZER} -keep-as3-metadata Bindable Managed ChangeEvent NonCommittingChangeEvent Transient -input  bin-final/WebcamRecorderApp.tmp.swf -output bin-final/WebcamRecorderApp.swf

