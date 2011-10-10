<?php

if (isset($GLOBALS["HTTP_RAW_POST_DATA"]))
{
	// get bytearray
	$jpg = $GLOBALS["HTTP_RAW_POST_DATA"];

	// add headers for download dialog-box
	header('Content-Type: image/jpeg');
	header("Content-Disposition: attachment; filename=".$_GET['name']);

        file_put_contents('/tmp/filename.jpg', $jpg);
        echo "OK !";
}

?>