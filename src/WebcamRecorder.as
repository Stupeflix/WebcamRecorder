package
{
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.NetStatusEvent;
	import flash.events.TimerEvent;
	import flash.external.ExternalInterface;
	import flash.media.Camera;
	import flash.media.Microphone;
	import flash.media.Video;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.system.Security;
	import flash.utils.Timer;
	
	import mx.core.FlexGlobals;

	/**
	 * WebcamRecorder uses the user's webcam and/or microphone to record
	 * video and/or audio and stream it to a Wowza server which then stores
	 * it. It can play the recorded video or sound, and send notifications
	 * about its state to a provided Javascript listener.
	 * 
	 * @see flash.media.Camera
	 * @see flash.media.Microphone
	 * @see flash.media.Video
	 * @see flash.net.NetConnection
	 * @see flash.net.NetStream
	 */
	public class WebcamRecorder extends EventDispatcher
	{
		//------------------------------------//
		//									  //
		//				CONSTS				  //
		//									  //
		//------------------------------------//
		
		/** Recording mode using the webcam to record video and the microphone to record audio */
		public static const VIDEO : String = "video";
		
		/** Recording mode using the microphone to record audio */
		public static const AUDIO : String = "audio";
		
		/** Type of the notification dispatched when a recording starts */
		public static const STARTED_RECORDING : String = "StartedRecording";
		
		/** Type of the notification dispatched when a recording pauses */
		public static const PAUSED_RECORDING : String = "PausedRecording";
		
		/** Type of the notification dispatched when a recording stops */
		public static const STOPPED_RECORDING : String = "StoppedRecording";
		
		/** Type of the notification dispatched periodically while recording */
		public static const RECORDING_TIME : String = "RecordingTime";
		
		/** Type of the notification dispatched when a playback starts */
		public static const STARTED_PLAYING : String = "StartedPlaying";
		
		/** Type of the notification dispatched when a playback pauses */
		public static const PAUSED_PLAYING : String = "PausedPlaying";
		
		/** Type of the notification dispatched when a playback ends */
		public static const END_PLAYING : String = "EndPlaying";
		
		/** Type of the notification dispatched periodically while playing */
		public static const PLAYED_TIME : String = "PlayedTime";
		
		/** Video width (in pixels) */
		private static const VIDEO_WIDTH : uint = 160;
		
		/** Video height (in pixels) */
		private static const VIDEO_HEIGHT : uint = 120;
		
		
		//------------------------------------//
		//									  //
		//				VARS				  //
		//									  //
		//------------------------------------//
		
		private var _recordingMode : String;
		private var _serverConnection : NetConnection;
		private var _jsListener : String;		
		private var _videoPreview : Video;
		private var _webcam : Camera;
		private var _microphone : Microphone;
		private var _publishStream : NetStream;
		private var _playStream : NetStream;
		private var _currentRecordId : String;
		private var _previousRecordId : String;
		private var _notificationTimer : Timer;
		private var _recordingTimer : Timer;
		private var _playingTimer : Timer;
		private var _flushBufferTimer : Timer;
		
		
		
		//------------------------------------//
		//									  //
		//				PUBLIC API			  //
		//									  //
		//------------------------------------//
		
		/** Constructor: Set up the JS API */
		public function WebcamRecorder()
		{
			setUpJSApi();
		}
		
		/**
		 * Initialize the recorder.
		 * 
		 * @param serverUrl String: The Wowza server URL (eg: rtmp://localhost/WebcamRecorder).
		 * 
		 * @param recordingMode String: Can be either WebcamRecorder.VIDEO or WebcamRecorder.AUDIO.
		 * Note that WebcamRecorder.VIDEO includes audio recording if a microphone is available.
		 * 
		 * @param jsListener String: The name of a Javascript listener function able to handle our
		 * notifications. It has to conform to the following API: TO DO.
		 * 
		 * @param notificationFrequency Number: The frequency at which the recorder will send notifications
		 * to the JS listener (in Hz).
		 */
		public function init( serverUrl:String, recordingMode:String, jsListener:String, notificationFrequency:Number ):void
		{
			// We need a server URL
			if( !serverUrl )
			{
				log( 'error', 'init - You need to pass a server URL!' );
				return;
			}
			
			// The recorder can be initialized only once
			if( _recordingMode )
			{
				log( 'error', 'init - Recorder already initialized!' );
				return;
			}
			
			// Check the recording mode
			if( !( recordingMode == VIDEO || recordingMode == AUDIO ) )
			{
				log( 'error', 'init - recordingMode should be either ' + VIDEO + ' or ' + AUDIO + '(given: ' + recordingMode + ')' );
				return;
			}
			
			// Connect to the server
			_serverConnection = new NetConnection();
			_serverConnection.addEventListener( NetStatusEvent.NET_STATUS, onConnectionStatus );
			_serverConnection.connect( serverUrl );
			
			// Set up the recording mode and video preview
			_recordingMode = recordingMode;
			_videoPreview = new Video( VIDEO_WIDTH, VIDEO_HEIGHT );
			FlexGlobals.topLevelApplication.stage.addChild( _videoPreview );
			
			// Set up the timers
			_recordingTimer = new Timer( 1000 );
			_playingTimer = new Timer( 1000 );
			
			// Set up the JS notifications
			setUpJSNotifications( jsListener, notificationFrequency );
		}
		
		public function record( recordId:String ):void
		{
			// Error if we are already recording
			if( _publishStream || _currentRecordId )
			{
				log( 'error', 'record - Already recording! You have to call stopRecording() before recording again.' );
				return;
			}
			
			if( !recordId || recordId.length == 0 )
			{
				log( 'error', 'record - recordId must be a non-empty string' );
				return;
			}
			
			// If there is a playback in progress, we stop it
			if( _playStream )
			{
				log( 'info', 'record - Stopped playback to record' );
				stopPlayStream();
			}
			
			// Start recording and dispatch a notification
			_currentRecordId = recordId;
			startPublishStream( recordId, false );
			notify( STARTED_RECORDING );
		}
		
		/** Stop the current recording without the possibility to resume it. */
		public function stopRecording():void
		{
			if( !_publishStream && !_currentRecordId )
			{
				log( 'error', 'stopRecording - No recording started!' );
				return;
			}
			
			// Stop the publish stream if necessary
			if( _publishStream )
				stopPublishStream();
			
			// Memorize the recordId
			_previousRecordId = _currentRecordId;
			_currentRecordId = null;
			
			// Dispatch a notification
			notify( STOPPED_RECORDING, { time: _recordingTimer.currentCount } );
			
			// Reset the recording time
			_recordingTimer.reset();
		}
		
		/**
		 * Stop the current recording with the possibility to resume it.
		 * 
		 * @see #resumeRecording()
		 */
		public function pauseRecording():void
		{
			if( !_publishStream )
			{
				log( 'error', 'pauseRecording - Not recording, or recording already paused.' );
				return;
			}
			
			// Stop the publish stream
			stopPublishStream();
			
			// Dispatch a notification
			notify( PAUSED_RECORDING, { time: _recordingTimer.currentCount } );
		}
		
		/**
		 * Resume the previously paused recording.
		 * 
		 * @see #pauseRecording()
		 */
		public function resumeRecording():void
		{
			if( !_currentRecordId )
			{
				log( 'error', 'resumeRecording - No recording started!' );
				return;
			}
			
			startPublishStream( _currentRecordId, true );
		}
		
		/**
		 * Play the previous recording. You have to call <code>stopRecording()</code>
		 * before being able to call <code>play()</code>.
		 * 
		 * @see #stopRecording()
		 */
		public function play():void
		{
			// If we already started playing, we just resume, dispatch a notification and restore scheduled notifications
			if( _playStream )
			{
				_playStream.resume();
				notify( STARTED_PLAYING );
				_notificationTimer.addEventListener( TimerEvent.TIMER, notifyPlayedTime );
				_playingTimer.start();
				return;
			}
			
			if( _currentRecordId )
			{
				log( 'error', 'play - Currently recording. You have to call stopRecording() before play().' );
				return;
			}
			
			if( !_previousRecordId )
			{
				log( 'error', 'play - Nothing recorded yet. You have to call stopRecording() before play().' );
				return;
			}
			
			// Start the play stream
			startPlayStream( _previousRecordId );
			
			// Dispatch an notification
			notify( STARTED_PLAYING );
		}
		
		/**
		 * Go to the keyframe closest to the specified time.
		 * 
		 * @param time Number: Time to seek (in seconds).
		 */
		public function seek( time:Number ):void
		{
			if( !_playStream )
			{
				log( 'error', 'seek - Not playing anything!' );
				return;
			}
			
			_playStream.seek( time );
		}
		
		/** Pause the current playback */
		public function pausePlaying():void
		{
			if( !_playStream )
			{
				log( 'error', 'pausePlaying - Not playing anything!' );
				return;
			}
			
			_playStream.pause();
			
			// Dispatch a notification
			notify( PAUSED_PLAYING );
			
			// Stop incrementing the played time and dispatching notifications
			_notificationTimer.removeEventListener( TimerEvent.TIMER, notifyPlayedTime );
			_playingTimer.stop();
		}
		
		
		//------------------------------------//
		//									  //
		//			PRIVATE METHODS			  //
		//									  //
		//------------------------------------//
		
		/**
		 * Listen to the server connection status. Set up the JS API
		 * if the connection was successful.
		 */
		private function onConnectionStatus( event:NetStatusEvent ):void
		{
			if( event.info.code == "NetConnection.Connect.Success" )
				setUpRecording();
			else if( event.info.code == "NetConnection.Connect.Failed" || event.info.code == "NetConnection.Connect.Rejected" )
				log( 'error', 'Couldn\'t connect to the server. Error: ' + event.info.description );
		}
		
		/** Set up the JS API */
		private function setUpJSApi():void
		{
			if( !ExternalInterface.available )
			{
				log( 'warn', 'setUpJSApi - ExternalInterface not available: the Flex component won\'t be reachable from Javascript!');
				return;
			}
			
			Security.allowDomain('*');
			ExternalInterface.addCallback( 'init', init );
			ExternalInterface.addCallback( 'record', record );
			ExternalInterface.addCallback( 'pauseRecording', pauseRecording );
			ExternalInterface.addCallback( 'stopRecording', stopRecording );
			ExternalInterface.addCallback( 'resumeRecording', resumeRecording );
			ExternalInterface.addCallback( 'play', play );
			ExternalInterface.addCallback( 'seek', seek );
			ExternalInterface.addCallback( 'pausePlaying', pausePlaying );
			log( 'info', 'JS API initialized' );
		}
		
		/** Set up the JS notifications */
		private function setUpJSNotifications( jsListener:String, notificationFrequency:Number ):void
		{
			// Check the notification frequency
			if( !( notificationFrequency >= 0 ) )
				log( 'warn', 'init - notificationFrequency has to be greater or equal to zero! We won\' notify for this session.' );
			
			// Set up the notifications
			_jsListener = jsListener;
			if( notificationFrequency > 0 )
			{
				_notificationTimer = new Timer( (1/notificationFrequency)*1000 );
				_notificationTimer.start();
			}
		}
		
		/** Set up the recording device(s) (webcam and/or microphone) */
		private function setUpRecording():void
		{
			// Video (if necessary)
			if( _recordingMode == VIDEO )
			{
				if( !_webcam )
				{
					_webcam = Camera.getCamera();
					_webcam.setMode( VIDEO_WIDTH, VIDEO_HEIGHT, 30, false );
					_webcam.setQuality( 0, 88 );
					_webcam.setKeyFrameInterval( 30 );
				}
				
				_videoPreview.attachNetStream( null );
				_videoPreview.attachCamera( _webcam );
			}
			
			// Audio
			if( !_microphone )
			{
				_microphone = Microphone.getMicrophone();
				_microphone.rate = 11;
				
				// Just to trigger the security window when initializing the component in audio mode
				var testStream : NetStream = new NetStream( _serverConnection );
				testStream.attachAudio( _microphone );
				testStream.attachAudio( null );
			}
		}
		
		/** Set up the player */
		private function setUpPlaying():void
		{
			_videoPreview.attachCamera( null );
			_videoPreview.attachNetStream( _playStream );
		}
		
		/** Trace a log message and forward it to the Javascript console */
		private function log( level:String, msg:String ):void
		{
			trace( level.toLocaleUpperCase() + ' :: ' + msg );
			if( ExternalInterface.available )
				ExternalInterface.call( 'console.'+level, msg );
		}
		
		/** Trigger the sending of a notification to the JS listener */
		private function notify( type:String = null, arguments:Object = null ):void
		{
			if( !_jsListener || !ExternalInterface.available )
				return;
			
			ExternalInterface.call( _jsListener, type, arguments );
		}
		
		/** Notify of the recording time */
		private function notifyRecordingTime( event:Event ):void
		{
			notify( RECORDING_TIME, { time: _recordingTimer.currentCount } );
		}
		
		/** Notify of the played time */
		private function notifyPlayedTime( event:Event ):void
		{
			notify( PLAYED_TIME, { time: _playingTimer.currentCount } );
		}
		
		/**
		 * Start the publish stream.
		 * 
		 * @param recordId String: The name of the recorded file.
		 * @param append Boolean: true if we resume an existing recording, false otherwise.
		 */
		private function startPublishStream( recordId:String, append:Boolean ):void
		{
			// Set up the publish stream
			_publishStream = new NetStream( _serverConnection );
			_publishStream.client = {};
			
			// Start the recording
			_publishStream.publish( recordId, append?"append":"record" );
			
			// Attach the devices
			_publishStream.attachCamera( _webcam );
			_publishStream.attachAudio( _microphone );
			
			// Set the buffer
			_publishStream.bufferTime = 20;
			
			// Start incrementing the recording time and dispatching notifications
			_recordingTimer.start();
			_notificationTimer.addEventListener( TimerEvent.TIMER, notifyRecordingTime );
		}
		
		/** Stop the publish stream or monitor the buffer size */
		private function stopPublishStream():void
		{
			// Detach the devices
			_publishStream.attachCamera( null );
			_publishStream.attachAudio( null );
			
			// Stop the recording or delay if the buffer is not empty
			if( _publishStream.bufferLength == 0 )
				doStopPublishStream();
			else
			{
				_flushBufferTimer = new Timer( 250 );
				_flushBufferTimer.addEventListener( TimerEvent.TIMER, checkBufferLength );
				_flushBufferTimer.start();
			}
			
			// Stop incrementing the recording time and dispatching notifications
			_notificationTimer.removeEventListener( TimerEvent.TIMER, notifyRecordingTime );
			_recordingTimer.stop();
		}
		
		/** Check the buffer length and stop the publish stream if empty */
		private function checkBufferLength( event:Event ):void
		{
			log('debug', 'check buffer length');
			// Do nothing if the buffer is still not empty
			if( _publishStream.bufferLength > 0 )
				return;
			
			// If the buffer is empty, destroy the timer
			_flushBufferTimer.removeEventListener( TimerEvent.TIMER, checkBufferLength );
			_flushBufferTimer.stop();
			_flushBufferTimer = null;
			
			// Then actually stop the publish stream
			doStopPublishStream();
		}
		
		/** Actually stop the publish stream */
		private function doStopPublishStream():void
		{
			_publishStream.publish( null );
			_publishStream = null;
		}
		
		/** Stop the playback and go back to the webcam preview when the playback ends */
		private function onPlaybackEnd():void
		{
			// Dispatch a notification
			notify( END_PLAYING, { time: _playingTimer.currentCount } );
			
			// Reset the playing timer and stop scheduled notifications
			_notificationTimer.removeEventListener( TimerEvent.TIMER, notifyPlayedTime );
			_playingTimer.stop();
			_playingTimer.reset();
			
			// Stop playing stream
			stopPlayStream();
		}
		
		/**
		 * Start the play stream.
		 * 
		 * @param playId String: The name of the file to play.
		 */
		private function startPlayStream( playId:String ):void
		{
			// Set up the play stream
			_playStream = new NetStream( _serverConnection );
			_playStream.client = {};
			_playStream.bufferTime = 2;
			
			// Replace the webcam preview by the stream playback
			setUpPlaying();
			
			// Add an event listener to dispatch a notification and go back to the webcam preview when the playing is finished
			_playStream.client.onPlayStatus = function( info:Object ):void
			{
				if( info.code == "NetStream.Play.Complete" )
					onPlaybackEnd();
			}
			
			// Start the playback
			_playStream.play( _previousRecordId );
			
			// Start incrementing the played time and dispatching notifications
			_playingTimer.start();
			_notificationTimer.addEventListener( TimerEvent.TIMER, notifyPlayedTime );
		}
		
		/** Stop the play stream */
		private function stopPlayStream():void
		{
			_playStream.pause();
			_playStream = null;
			setUpRecording();
		}
	}
}