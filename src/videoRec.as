package  
{
	import flash.media.SoundChannel;	
	import flash.media.Sound;	
	
	import org.tiger.network.PostFormDataEvent;	
	import org.tiger.network.PostFormData;	
	import org.tiger.media.SimpleFlvWriter;
	
	import flash.display.Bitmap;	
	import flash.external.ExternalInterface;	
	import flash.display.StageScaleMode;	
	import flash.display.StageAlign;	
	import flash.system.Security;	
	import flash.display.DisplayObject;	
	import flash.events.Event;	
	import flash.events.ActivityEvent;	
	import flash.events.SampleDataEvent;	
	import flash.events.StatusEvent;	
	import flash.utils.ByteArray;	
	import flash.media.Microphone;	
	import flash.net.FileReference;	
	import flash.display.BitmapData;	
	import flash.media.Video;	
	import flash.media.Camera;	
	import flash.display.Sprite;
	import flash.events.MouseEvent;
	import flash.utils.getTimer;
	import flash.utils.setTimeout;
	import flash.utils.clearTimeout;	
	
	[SWF(backgroundColor="#888888", frameRate="20", width="320", height="240")]
	
	public class videoRec extends Sprite
	{
		[Embed(source="record.png")] private var RecordIconClass : Class;
		[Embed(source="play.png")] private var PlayIconClass : Class;
		[Embed(source="processing.png")] private var ProcessIconClass : Class;
		
		[Embed(source="bttn_record.png")] private var BttnRecordClass : Class;
		[Embed(source="bttn_stop.png")] private var BttnRecStopClass : Class;
		[Embed(source="bttn_delete.png")] private var BttnDeleteClass : Class;
		[Embed(source="bttn_play.png")] private var BttnPlayClass : Class;
		[Embed(source="bttn_save.png")] private var BttnSaveClass : Class;
		[Embed(source="bttn_stop.png")] private var BttnStopClass : Class;
		private var _bttnDelete : Sprite = new Sprite();
		private var _bttnPlay : Sprite = new Sprite();
		private var _bttnRecord : Sprite = new Sprite();
		private var _bttnRecStop : Sprite = new Sprite();
		private var _bttnSave : Sprite = new Sprite();
		private var _bttnStop : Sprite = new Sprite();
		
		// camera width
		private const vidWidth : int = 320;
		// camera height
		private const vidHeight : int = 240;
		// capture FPS
		private const vidFps : int = 15;
		// камера
		private var _cam : Camera;
		// видео
		private var _vid : Video;
		// video player object
		private var _vidPlayer : Bitmap;
		// microphones
		private var _mic : Microphone;
		// audio buffer 
		private var _micBuff : ByteArray;
		// array of screen bitmap
		private var _bmpBuff : Array = new Array();
		// object for encode video
		private var flv_writer : SimpleFlvWriter;
		// video record state
		private var _isRecording : Boolean = false;
		// sound record state
		private var _isRecordSound : Boolean = false;
		// encode state 
		private var _isEncoding : Boolean = false;
		// timer ID
		private var _recordingInterval : uint;
		// start record time
		private var _startRecTime : int = 0;
		// record icon displayed right-top
		private var _iconRecord : DisplayObject = null;
		// play icon displayed right-top
		private var _iconPlay : DisplayObject = null;
		// encode processing icon displayed right-top
		private var _iconProcess : DisplayObject = null;
		
		static private var _id : String = "";
		private var _postUrl : String = "";
		private var _postToken : String = "";
		private var _postKey : String = "";
		private var _postXml : String = "";
		private var _postClientId : String = "unknown";
		private var _failParam : String = "";
		
		
		
		public function videoRec()
		{
			Security.allowDomain("*");
			Security.allowInsecureDomain("*");
			
			stage.align = StageAlign.TOP_LEFT;
			stage.scaleMode = StageScaleMode.NO_SCALE;
			stage.showDefaultContextMenu = true;
			stage.focus = this;
			
			// save new record Id
			if(this.loaderInfo.parameters["id"])
				_id = this.loaderInfo.parameters["id"];
			
			// register JS functions
			if(ExternalInterface.available)
			{
				ExternalInterface.addCallback("StartRecord", StartRecord);
				ExternalInterface.addCallback("StopRecord", StopRecord);
				ExternalInterface.addCallback("DeleteRecorded", ClearBuffer);
				ExternalInterface.addCallback("Encode", EncodeVideo);
				ExternalInterface.addCallback("PlayRecord", PlayVideo);
				ExternalInterface.addCallback("StopPlaingRecord", StopVideo);
				ExternalInterface.addCallback("SetPostData", SetPostData);
				ExternalInterface.addCallback("SetMediaData", SetMediaData);
				ExternalInterface.addCallback("SetEnable", SetEnable);
				ExternalInterface.addCallback("SetNewId", SetNewId);
			}
			
			// check for camera avaible
			if(Camera.names.length <= 0)
			{
				CallJSFunction("vr_noCamera");
				return;
			}
			
			// create and init objects
			_iconRecord = (new RecordIconClass()) as DisplayObject;
			_iconPlay = (new PlayIconClass()) as DisplayObject;
			_iconProcess = (new ProcessIconClass()) as DisplayObject;
			
			_cam = Camera.getCamera();
			_cam.setMode(vidWidth, vidHeight, vidFps, true);
			_cam.addEventListener(StatusEvent.STATUS, onCamStatus);
			_cam.addEventListener(ActivityEvent.ACTIVITY, onCamActivity);
			
			_micBuff = new ByteArray();
			_mic = Microphone.getMicrophone();
			_mic.setSilenceLevel(0, 2000);
			
			_mic.gain = 50;
			_mic.rate = 44;
			_mic.encodeQuality = 10;
			_mic.addEventListener(StatusEvent.STATUS, onStatus);
			_mic.addEventListener(SampleDataEvent.SAMPLE_DATA, onSampleData);			
			
			_vid = new Video(_cam.width, _cam.height);
			_vid.attachCamera(_cam);
			_vid.x = _vid.y = 0;
			this.addChild(_vid);
			
			// add control button
			_bttnDelete.addChild((new BttnDeleteClass()) as DisplayObject);
			_bttnPlay.addChild((new BttnPlayClass()) as DisplayObject);
			_bttnRecord.addChild((new BttnRecordClass()) as DisplayObject);
			_bttnRecStop.addChild((new BttnRecStopClass()) as DisplayObject);
			_bttnSave.addChild((new BttnSaveClass()) as DisplayObject);
			_bttnStop.addChild((new BttnStopClass()) as DisplayObject);
			_bttnDelete.y = _bttnPlay.y = _bttnRecord.y = _bttnRecStop.y = _bttnSave.y = _bttnStop.y = 240-25;
			_bttnDelete.buttonMode = _bttnPlay.buttonMode = _bttnRecord.buttonMode = _bttnRecStop.buttonMode = _bttnSave.buttonMode = _bttnStop.buttonMode = true;
			_bttnRecStop.x = _bttnRecord.x = 320/2-12;
			_bttnPlay.x = _bttnStop.x = 320/2 - 30 - 12;
			_bttnSave.x = 320/2 - 12;
			_bttnDelete.x = 320/2 + 30 - 12;
			
			// attach event for control buttons
			_bttnRecord.addEventListener(MouseEvent.MOUSE_UP, OnBttnRecord);
			_bttnPlay.addEventListener(MouseEvent.MOUSE_UP, OnBttnPlay);
			_bttnStop.addEventListener(MouseEvent.MOUSE_UP, OnBttnStop);
			_bttnSave.addEventListener(MouseEvent.MOUSE_UP, OnBttnSave);
			_bttnDelete.addEventListener(MouseEvent.MOUSE_UP, OnBttnDelete);
			_bttnRecStop.addEventListener(MouseEvent.MOUSE_UP, OnBttnRecStop);
			stage.addEventListener(MouseEvent.MOUSE_UP, OnBttnRecord);
			this.addChild(_bttnRecord);
			
			CallJSFunction("vr_onRecordInit");
			
//			SetPostData(
//					"http://uploads.gdata.youtube.com/feeds/api/users/default/uploads",
//					"1/J0_0qXX3cOS_ytMtdZBAMxyleadyWyJHOYM6chYMLzc",
//					"AI39si5yWp5hM7n3r-pWAGLMLm-spwP_EMzB3DzBjoD21-yz8TX69xWpqU-EMSFaNbqkHqHXn1O4VXmgt4FswRYrRPocX0OX0g",
//					"bytiger.com");
//			SetMediaData(this.GenerateFileName(),"","People","");
		}
		
		private function OnBttnRecord(e : MouseEvent) : void
		{
			e.stopPropagation();
			e.preventDefault();
			stage.removeEventListener(MouseEvent.MOUSE_UP, OnBttnRecord);
			StartRecord();
			this.removeChild(_bttnRecord);
			this.addChild(_bttnRecStop);
			stage.addEventListener(MouseEvent.MOUSE_UP, OnBttnRecStop);
		}
		
		private function OnBttnRecStop(e : MouseEvent) : void
		{
			e.stopPropagation();
			e.preventDefault();
			this.removeChild(_bttnRecStop);
			StopRecord();
			stage.removeEventListener(MouseEvent.MOUSE_UP, OnBttnRecStop);
			stage.addEventListener("encodeFinish", OnEncodeComplete);
			EncodeVideo();
			//OnEncodeComplete(null);
		}
		
		private function OnEncodeComplete(e : Event) : void
		{
			stage.removeEventListener("encodeFinish", OnEncodeComplete);
			this.addChild(_bttnPlay);
			this.addChild(_bttnStop);
			this.addChild(_bttnDelete);
			this.addChild(_bttnSave);
			_bttnPlay.visible = true;
			_bttnStop.visible = false;
			
//			stage.addEventListener(MouseEvent.CLICK, function(e : Event) : void{
//				(new FileReference).save(flv_writer.videoData, "video.flv");
//			});
		}

		private function OnBttnPlay(e : MouseEvent) : void
		{
			_bttnPlay.visible = false;
			_bttnStop.visible = true;
			PlayVideo();
		}

		private function OnBttnStop(e : MouseEvent) : void
		{
			StopVideo();
			_bttnPlay.visible = true;
			_bttnStop.visible = false;
		}
		
		private function OnBttnSave(e : MouseEvent) : void
		{
			this.DoPost();
		}
		
		private function OnBttnDelete(e : MouseEvent) : void
		{
			this.ClearBuffer();
			
			if(this.contains(_bttnPlay)) this.removeChild(_bttnPlay);
			if(this.contains(_bttnStop)) this.removeChild(_bttnStop);
			if(this.contains(_bttnDelete)) this.removeChild(_bttnDelete);
			if(this.contains(_bttnSave)) this.removeChild(_bttnSave);
			
			if(!this.contains(_bttnRecord)) this.addChild(_bttnRecord);
			stage.addEventListener(MouseEvent.MOUSE_UP, OnBttnPlay);
		}
		
		private function onBttnSaveClick(e : MouseEvent) : void
		{
			if(!flv_writer) return;
			var fr : FileReference = new FileReference();
			fr.save(flv_writer.videoData, "video.flv");
		}
		
		private function DoPost() : void
		{
			if(_postUrl == "")
			{
				CallJSFunction("vr_onPostWarning", "url");
				return;
			}
			if(_postToken == "")
			{
				CallJSFunction("vr_onPostWarning", "token");
				return;
			}
			if(_postKey == "")
			{
				CallJSFunction("vr_onPostWarning", "key");
				return;
			}
			if(_postClientId == "")
			{
				CallJSFunction("vr_onPostWarning", "clientId");
				return;
			}
			if(_postXml == "")
			{
				CallJSFunction("vr_onPostWarning", _failParam);
				return;
			}
			
			var fileName : String = this.GenerateFileName();
			var fileField : String = "file";
			var headers : Array = [
				"Authorization: AuthSub token=\"" + _postToken + "\"",
				"X-GData-Key: key=" + _postKey,
				"X-GData-Client: " + _postClientId,
				"Slug: " + this.GenerateFileName()
					];
			
			CallJSFunction("vr_onPostStart");
			
			var ba : ByteArray = new ByteArray();
			ba.writeUTFBytes(_postXml);
			
			var _postForm : PostFormData = new PostFormData();
			_postForm.SetContentType("multipart/related");
			_postForm.addData(["Content-Type: application/atom+xml; charset=UTF-8"], ba);
			_postForm.addData(["Content-Type: video/x-flv","Content-Transfer-Encoding: binary"], flv_writer.videoData);
			_postForm.preparePostData();
			
			// clear buffer for next records
			this.OnBttnDelete(null);
			_postForm.userData = { id:videoRec._id };
			_postForm.Post(_postUrl, headers);
			_postForm.addEventListener(PostFormDataEvent.COMPLETE, DoPostComplete);
			_postForm.addEventListener(PostFormDataEvent.ERROR, DoPostError);
		}
		
		private function DoPostComplete(e : PostFormDataEvent) : void
		{
			var id : String = (e.currentTarget as PostFormData).userData["id"];
			(e.currentTarget as PostFormData).removeEventListener(PostFormDataEvent.COMPLETE, DoPostComplete);
			(e.currentTarget as PostFormData).addEventListener(PostFormDataEvent.ERROR, DoPostError);
			(e.currentTarget as PostFormData).Release();
			CallJSFunctionId("vr_onPostComplete", id);
		}
		
		private function DoPostError(e : PostFormDataEvent) : void
		{
			var id : String = (e.currentTarget as PostFormData).userData["id"];
			(e.currentTarget as PostFormData).removeEventListener(PostFormDataEvent.COMPLETE, DoPostComplete);
			(e.currentTarget as PostFormData).addEventListener(PostFormDataEvent.ERROR, DoPostError);
			(e.currentTarget as PostFormData).Release();
			CallJSFunctionId("vr_onPostError", id, e.result.toString());
		}
		
		private function GenerateFileName():String
		{
			var fn : String = "";
			
			for (var i:int = 0; i < 0x12; i++ )
			{
				fn += String.fromCharCode( int( 97 + Math.random() * 25 ) );
			}
			fn += ".flv";
			return fn;
		}
		
		
		
		
		/****************************************************************************
		 * control functions
		 ****************************************************************************/
		
		private function SetNewId(id : String) : void
		{
			_id = id;
		}
		
		private function SetEnable(en : String) : void
		{
			if(en == "true")
			{
				if(_vid) _vid.attachCamera(_cam);
			}
			else
			{
				if(_vid) _vid.attachCamera(null);
			}
		}
		
		private function SetPostData(url : String, token : String, key : String, clientId : String) : void
		{
			_postUrl = url;
			_postToken = token;
			_postKey = key;
			_postClientId = clientId;
		}
		
		private function SetMediaData(name : String, desc : String, cat : String, keyword : String) : void
		{
			_postXml = "";
			if(name.length <= 0)
			{
				_failParam = "name";
				return;
			}
//			if(desc.length <= 0)
//			{
//				_failParam = "desc";
//				return;
//			}
			if(cat.length <= 0)
			{
				_failParam = "cat";
				return;
			}
//			if(keyword.length <= 0)
//			{
//				_failParam = "keyword";
//				return;
//			}
			_postXml = '<?xml version="1.0"?>';
			_postXml += '<entry xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/" xmlns:yt="http://gdata.youtube.com/schemas/2007">';
			_postXml += '<media:group>';
			_postXml += '<media:title type="plain">' + name + '</media:title>';
			if(desc.length > 0) _postXml += '<media:description type="plain">' + desc + '</media:description>';
			_postXml += '<media:category scheme="http://gdata.youtube.com/schemas/2007/categories.cat">' + cat + '</media:category>';
			if(keyword.length > 0) _postXml += '<media:keywords>' + keyword + '</media:keywords>';
			_postXml += '</media:group>';
			_postXml += '</entry>';
		}
		
		private function StartRecord() : void
		{
			if(_isRecording || _isEncoding) return;
			
			_startRecTime = getTimer();
			_mic.setLoopBack(true);
			
			this.addChild(_iconRecord);
			_iconRecord.x = 300;
			_iconRecord.y = 4;
			
			CallJSFunction("vr_onRecordStart");	
			_isRecording = true;
			_isRecordSound = true;
			
			this.add_picture();
		}
		
		private function StopRecord() : void
		{
			if(!_isRecording) return;
			setTimeout(function() : void { _isRecordSound = false; }, 200);
			
			if(this.contains(_iconRecord)) this.removeChild(_iconRecord);
			_mic.setLoopBack(false);
			clearTimeout(_recordingInterval);
			CallJSFunction("vr_onRecordStop");
			_isRecording = false;
		}
		
		private function EncodeVideo() : void
		{
			if(_isRecording || _isEncoding) return;
			
			CallJSFunction("vr_onEncodeStart");
			
			this.addChild(_iconProcess);
			_iconProcess.x = 300;
			_iconProcess.y = 4;
			_isEncoding = true;
			
			if(!flv_writer) flv_writer = SimpleFlvWriter.getInstance();
			flv_writer.Clear();
			flv_writer.setVideoParam(_cam.width, _cam.height, vidFps);
			flv_writer.setAudioParam(SimpleFlvWriter.SAMPLERATE_44KHZ, true, false, true);
			flv_writer.createFile();
			_curFrame = 0;
			
			encodeNextFrame();
		}
		
		private function ClearBuffer() : void
		{
			if(_isRecording || _isEncoding) return;
			
			var qq : int;
			for(qq = 0; qq < _bmpBuff.length; qq++)
			{
				(_bmpBuff[qq] as BitmapData).dispose();
				_bmpBuff[qq] = null;
			}
			_bmpBuff = [];
			_micBuff.length = 0;
			flv_writer = null;
			
			CallJSFunction("vr_onRecordDeleted");
		}
		
		private function PlayVideo(e : Event = null) : void
		{
			if(_isRecording || _isEncoding) return;
			this.player_start();
		}
		
		private function StopVideo() : void
		{
			if(_isRecording || _isEncoding) return;
			_PlayFrame = _bmpBuff.length;
		}
		
		
		
		
		
		
		/****************************************************************************
		 * capture functions
		 ****************************************************************************/
		
		public function add_picture() : void
		{
			var img : BitmapData = new BitmapData(_cam.width, _cam.height);
			img.draw(_vid);
			_bmpBuff.push(img);
			var elapsedMs : int = getTimer() - _startRecTime;
			var nextMs : int = (_bmpBuff.length / vidFps) * 1000;
			var deltaMs : int = nextMs - elapsedMs;
			if (deltaMs < 10) deltaMs = 10;
			_recordingInterval = setTimeout(add_picture, deltaMs);
			
			CallJSFunction("vr_onRecordTime", elapsedMs.toString());
//			trace("add_picture", elapsedMs.toString(), nextMs.toString(), _micBuff.length.toString(), (_micBuff.length / elapsedMs).toString());
			
			var pp : int = _bmpBuff.length % 15;
			_iconRecord.alpha = pp < 7 ? 1 : 0;
		}
		
		private function onSampleData(e : SampleDataEvent) : void
		{
			if(!_isRecordSound) return;
			var to : int = getTimer() - _startRecTime;
			
			while(e.data.bytesAvailable > 0)
			{
				_micBuff.writeFloat(e.data.readFloat());
			}
		}
		
		
		
		
		
		
		/****************************************************************************
		 * player functions
		 ****************************************************************************/
		
		private var _startPlayTime : int = 0;
		private var _PlayFrame : int = 0;
		private var _playInterval : int = 0;
		private var _sound : Sound = null;
		private var _soundChanel : SoundChannel = null;

		private function player_start() : void
		{
			_vid.visible = false;
			if(!_vidPlayer) _vidPlayer = new Bitmap();
			this.addChildAt(_vidPlayer, 2);
			_vidPlayer.x = _vidPlayer.y = 0;
			this.addChild(_iconPlay);
			_iconPlay.x = 300;
			_iconPlay.y = 4;
			_startPlayTime = getTimer();
			_PlayFrame = 0;
			_soundChanel = null;
			
			_micBuff.position = 0;
			_sound = new Sound();
			_sound.addEventListener(SampleDataEvent.SAMPLE_DATA, player_sound);
			_soundChanel = _sound.play();
			
			CallJSFunction("vr_onPlayStart");
			
			this.player_step();
		}
		
		private function player_sound(e : SampleDataEvent) : void
		{
//			trace("player_sound", _micBuff.position.toString(), _micBuff.length.toString(), (_micBuff.position / _micBuff.length).toString(), (_PlayFrame / _bmpBuff.length).toString());
			var blockSize : int = 8192;
			var qq : int;
			var nn : Number;
			for(qq = 0; qq < blockSize; qq++)
			{
				if(_micBuff.bytesAvailable > 0)
					nn = _micBuff.readFloat();
				else nn = 0;
				e.data.writeFloat(nn);
				e.data.writeFloat(nn);
			}
		}
		
		private function player_step() : void
		{
			if(_PlayFrame >= _bmpBuff.length)
			{
				this.player_stop();
				return;
			}
			
			_vidPlayer.bitmapData = _bmpBuff[_PlayFrame];
			_PlayFrame++;
			
			var nextMs : int = (_PlayFrame / vidFps) * 1000 + _startPlayTime;
			var deltaMs : int = nextMs - getTimer();
			if (deltaMs < 10) deltaMs = 10;
			_playInterval = setTimeout(player_step, deltaMs);
			
			CallJSFunction("vr_onPlayProgress", _PlayFrame.toString(), _bmpBuff.length.toString());
		}
		
		private function player_stop() : void
		{
			if(this.contains(_iconPlay)) this.removeChild(_iconPlay);
			if(this.contains(_vidPlayer)) this.removeChild(_vidPlayer);
			_vid.visible = true;
			
			_soundChanel.stop();
			_soundChanel = null;
			_sound = null;
			
			OnBttnStop(null);
			CallJSFunction("vr_onPlayStop");
		}
		
		
		
		
		
		/****************************************************************************
		 * encode functions
		 ****************************************************************************/
		
		private var _curFrame : int = 0;
		
		private function encodeNextFrame(n : int = 5) : void
		{
			_vid.alpha = 0.5;
			
			if(_bmpBuff.length > 0)
			{
				var qq : int;
				for(qq = 0; qq < n; qq++)
				{
					this.encodeFrameData(_curFrame);
					_curFrame++;
					if(_curFrame >= _bmpBuff.length) break;
				}
			}
			
			CallJSFunction("vr_onEncodeProgress", _curFrame.toString(), _bmpBuff.length.toString());
			
			if(_curFrame < _bmpBuff.length) setTimeout(encodeNextFrame, 10);
			else encodeVideoFinish();
		}
		
		private function encodeFrameData(num : int) : void
		{
			var audio : ByteArray = new ByteArray();
			var bmp : BitmapData;
			var pos : int;
			
			pos = num * flv_writer.audioFrameSize;
			if (pos < 0 || pos + flv_writer.audioFrameSize > _micBuff.length)
			{
				audio.length = flv_writer.audioFrameSize; // zero's
			}
			else
			{
				audio.writeBytes(_micBuff, pos, flv_writer.audioFrameSize);
			}
			bmp = _bmpBuff[num];
			flv_writer.addFrame(bmp, audio);
			audio.length = 0;
			audio = null;
			bmp = null;
		}
		
		private function encodeVideoFinish() : void
		{
			flv_writer.closeFile();
			this.removeChild(_iconProcess);
			_vid.alpha = 1;
			_isEncoding = false;
			
			CallJSFunction("vr_onEncodeStop");
			
			stage.dispatchEvent(new Event("encodeFinish"));
		}
		
		
		
		
		
		/****************************************************************************
		 * event's functions
		 ****************************************************************************/
		
		private function onStatus(e : StatusEvent) : void
		{
		}
		
		private function onCamStatus(e : StatusEvent) : void
		{
		}
		
		private function onCamActivity(e : ActivityEvent) : void
		{
		}
		
		
		
		
		
		/********************************************************************************
		 * call JS function for callback
		 ********************************************************************************/
		
		static public function CallJSFunction(func : String, prm1 : String = null, prm2 : String = null, prm3 : String = null) : String
		{
			return CallJSFunctionId(func, _id, prm1, prm2, prm3);
		}
		static public function CallJSFunctionId(func : String, id : String, prm1 : String = null, prm2 : String = null, prm3 : String = null) : String
		{
//			trace(_id, func,prm1,prm2);
			
			if(!ExternalInterface.available)
			{
				return "";
			}
			
			var res : String ="";
			if(prm3 != null)
			{
				res = String(ExternalInterface.call(func, id, prm1, prm2, prm3));
			}
			else if(prm2 != null)
			{
				res = String(ExternalInterface.call(func, id, prm1, prm2));
			}
			else if(prm1 != null)
			{
				res = String(ExternalInterface.call(func, id, prm1));
			}
			else
			{
				res = String(ExternalInterface.call(func, id));
			}
			return res;
		}
	}
}
