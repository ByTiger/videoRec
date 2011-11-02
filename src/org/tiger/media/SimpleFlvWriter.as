/*
	SimpleFlvWriter.as
	Lee Felarca
	http://www.zeropointnine.com/blog
	5-2007
	v0.8
	
	Singleton class to create uncompressed FLV files.
	Does not handle audio. Feel free to extend.
	
	Source code licensed under a Creative Commons Attribution 3.0 License.
	http://creativecommons.org/licenses/by/3.0/
	Some Rights Reserved.

	EXAMPLE USAGE:
	
		var myWriter:SimpleFlvWriter = SimpleFlvWriter.getInstance();
		myWriter.createFile(myFile, 320,240, 30, 120);
		myWriter.saveFrame( myBitmapData1 );
		myWriter.saveFrame( myBitmapData2 );
		myWriter.saveFrame( myBitmapData3 ); // etc.
		myWriter.closeFile();			
*/

package org.tiger.media
{
	import flash.utils.Endian;	
	import flash.display.BitmapData;
    import flash.utils.ByteArray;

	public class SimpleFlvWriter
	{
		public static const SAMPLERATE_11KHZ : uint = 11025;
		public static const SAMPLERATE_22KHZ : uint = 22050;
		public static const SAMPLERATE_44KHZ : uint = 44100;
		
		static private var _instance:SimpleFlvWriter;
		
		private var _isStarted : Boolean = false;
		private var _isSaveVideo : Boolean = false;
		private var _isSaveAudio : Boolean = false;
		
		private var _frameWidth : int;
		private var _frameHeight : int;
		private var _frameRate : Number;
		private var _duration : Number;
		private var _durationPos : int = 0;
		
		private var _sampleRate : uint = 0;
		private var _is16Bit : Boolean = true;
		private var _isStereo : Boolean = false;
		private var _isAudioInputFloats : Boolean = true;
		private var _audioFrameSize : uint = 0;
		private var _soundPropertiesByte : uint;
		
		private const blockWidth : int = 32;
		private const blockHeight : int = 32;
		
		private var _previousTagSize : uint = 0;
		private var _iteration : int = 0;
		private var _bmp : BitmapData;
		private var _videoData : ByteArray = null;
		
		public static function getInstance():SimpleFlvWriter 
		{
			if(SimpleFlvWriter._instance == null) 
				SimpleFlvWriter._instance = new SimpleFlvWriter();
			return SimpleFlvWriter._instance;
		}

		public function SimpleFlvWriter()
		{
			_videoData = new ByteArray();
		}
		
		public function get videoData() : ByteArray
		{
			return _videoData;
		}
		
		public function Clear() : void
		{
			_isStarted = false;
			_isSaveVideo = false;
			_isSaveAudio = false;
			
			_previousTagSize = 0;
			_iteration = 0;
			_bmp = null;
			_videoData.length = 0;
		}
		
		/**
		 * Defines the video properties to be used in the FLV.
		 * setVideoParam() must be called before calling "createFile()"
		 *  @param pWidth				Video height
		 *  @param pWidth				Video width
		 *  @param pFramesPerSecond		Determines framerate of created video
		 *  @param pDurationInSeconds	Duration of video file to be created. Used for metadata only. Optional.
		 */
		public function setVideoParam(pWidth:int=0, pHeight:int=0, pFramesPerSecond:Number=0, pDurationInSeconds:Number=0) : void
		{
			if(pWidth <= 0 || pHeight <= 0 || pFramesPerSecond <= 0)
			{
				_isSaveVideo = false;
				return;
			}
			
			_isSaveVideo = true;
			_frameWidth = pWidth;
			_frameHeight = pHeight;
			_frameRate = pFramesPerSecond;
			_duration = pDurationInSeconds;
		}
		
		/**
		 * Defines the audio properties to be used in the FLV.
		 * setAudioParam() must be called before calling "createFile()"
		 * 
		 * @param sampleRate			Should be either SAMPLERATE_11KHZ, SAMPLERATE_22KHZ, or SAMPLERATE_44KHZ
		 * @param is16Bit				16-bit audio will be expected if true, 8-bit if false
		 * 								Default is true, matching data format coming from Microphone
		 * @param isStereo				Two channel of audio will be expected if true, one (mono) if false
		 * 								Default is false, matching data format coming from Microphone
		 * @param dataWillBeInFloats	If set to true, audio data supplied to "addFrame()" will be assumed to be
		 * 								in floating point format and will be automatically converted to 
		 * 								unsigned shortints for the FLV. (PCM audio coming from either WAV files or 
		 * 								from webcam microphone input is in floating point format.) 
		 */		
		public function setAudioParam(sampleRate : uint=0, is16Bit : Boolean=true, isStereo : Boolean=false, dataWillBeInFloats : Boolean = true) : void
		{
			if(sampleRate == 0)
			{
				_isSaveAudio = false;
				return;
			}
			
			_isSaveAudio = true;
			_sampleRate = sampleRate;
			_is16Bit = is16Bit;
			_isStereo = isStereo;
			_isAudioInputFloats = dataWillBeInFloats;
			
			var n : Number = _sampleRate * (_isStereo ? 2 : 1) * (_is16Bit ? 2 : 1);
			n = n / _frameRate;
			if (_isAudioInputFloats) n *= 2;
			_audioFrameSize = int(n);
			
			_soundPropertiesByte = this.makeSoundPropertiesByte();
		}
		
		public function get audioFrameSize():uint
		{
			return _audioFrameSize;
		}
		
		public function get timeStamp() : uint
		{
			return uint(1000 / _frameRate * _iteration);
		}
		
		public function get isRecording() : Boolean
		{
			return _isStarted;
		}
		
		public function createFile():void
		{
			if(_isStarted) return;

			_isStarted = true;
			_previousTagSize = 0;
			// create header
			_videoData.length = 0;
			this.flvWriteHeader();
			
			// create metadata tag
			_videoData.writeUnsignedInt(_previousTagSize);
			this.flvWriteTagOnMetaData();
			
			// get and save position of metadata's duration float
			var tmp : ByteArray = new ByteArray();
			tmp.writeUTFBytes("duration");
			_durationPos = SimpleFlvWriter.byteArrayIndexOf(_videoData, tmp) + tmp.length + 1;
			tmp.length = 0;
			tmp = null;
		}
		
		public function addFrame(pBitmapData : BitmapData, pUncompressedAudio : ByteArray) : void
		{
			if(!_isStarted) return;
			if(_isSaveVideo && !pBitmapData) return;
			if(_isSaveAudio && !pUncompressedAudio) return;

			// bitmap dimensions should of course match parameters passed to createFile()
			if(_isSaveVideo)
			{
				_bmp = pBitmapData;
				_videoData.writeUnsignedInt(_previousTagSize);
				this.flvWriteTagVideo();
			}
			if(_isSaveAudio)
			{
				_videoData.writeUnsignedInt(_previousTagSize);
				
				// Note how, if _isAudioInputFloats is true (which is the default), 
				// the incoming audio data is assumed to be in normalized floats 
				// (4 bytes per float value) and converted to signed shortint's, 
				// which are 2 bytes per value. Don't let this be a source of confusion...
				if(_isAudioInputFloats)
				{
					var ba : ByteArray = this.floatsToSignedShorts(pUncompressedAudio);
					this.flvWriteTagAudio(ba);
					ba.length = 0;
					ba = null;
				}
				else this.flvWriteTagAudio(pUncompressedAudio);
			}
			_iteration++;
		}
		
		public function closeFile():void
		{
			_videoData.position = _durationPos;
			_videoData.writeDouble(_iteration / _frameRate);
			_videoData.position = _videoData.length;
			
			if(!_isStarted) return;
			_isStarted = false;
		}
		
		private function makeSoundPropertiesByte() : uint
		{
			var u : uint;
			var val : int;
			
			// soundformat [4 bits] - only supporting linear PCM little endian == 3
			u  = (3 << 4); 

			// soundrate [2 bits]
			switch(_sampleRate)
			{
				case SAMPLERATE_11KHZ: val = 1; break;
				case SAMPLERATE_22KHZ: val = 2; break;
				case SAMPLERATE_44KHZ: val = 3; break;
			}
			u += (val << 2);
			
			// soundsize [1 bit] - 0 = 8bit; 1 = 16bit
			val = _is16Bit ? 1 : 0;
			u += (val << 1);
			
			// soundtype [1 bit] - 0 = mono; 1 = stereo
			val = _isStereo ? 1 : 0;
			u += (val << 0);			
			
			// trace('FlvEncoder.makeSoundPropertiesByte():', u.toString(2));
			
			return u;
		}
		
		private function flvWriteHeader() : void
		{
			_videoData.writeByte(0x46); // 'F'
			_videoData.writeByte(0x4C); // 'L'
			_videoData.writeByte(0x56); // 'V'
			_videoData.writeByte(0x01); // Version 1
			var u : uint = 0;
			if (_isSaveVideo) u += 1;
			if (_isSaveAudio) u += 4;
			_videoData.writeByte(u); // streams: video and/or audio
			_videoData.writeUnsignedInt(0x09); // header length
		}
		
		private function flvWriteTagOnMetaData() : void
		{
			var pos : uint = _videoData.position;
			var dat : ByteArray = this.metaData();
			
			// tag 'header'
			_videoData.writeByte(18); 						// tagType = script data
			writeUI24(_videoData, dat.length); 			// data size
			writeUI24(_videoData, 0);						// timestamp should be 0 for onMetaData tag
			_videoData.writeByte(0);						// timestamp extended
			writeUI24(_videoData, 0);						// streamID always 0
			
			// data tag
			_videoData.writeBytes(dat);
			
			// free buffer
			dat.length = 0;
			dat = null;
			
			_previousTagSize = _videoData.position - pos;
		}
		
		private function metaData():ByteArray
		{
			// onMetaData info goes in a ScriptDataObject of data type 'ECMA Array'

			var b:ByteArray = new ByteArray();
			
			// ObjectNameType (always 2)
			b.writeByte(2);	
			
			// ObjectName (type SCRIPTDATASTRING):
			writeUI16(b, "onMetaData".length); // StringLength
			b.writeUTFBytes("onMetaData"); // StringData
			
			// ObjectData (type SCRIPTDATAVALUE):
			b.writeByte(8); // Type (ECMA array = 8)
			b.writeUnsignedInt(7); // // Elements in array
			
			// SCRIPTDATAVARIABLES...
			
			writeUI16(b, "duration".length);
			b.writeUTFBytes("duration");
			b.writeByte(0); 
			b.writeDouble(0.0); // * this value will get updated dynamically with addFrame() 
			
			writeUI16(b, "width".length);
			b.writeUTFBytes("width");
			b.writeByte(0); 
			b.writeDouble(_frameWidth);

			writeUI16(b, "height".length);
			b.writeUTFBytes("height");
			b.writeByte(0); 
			b.writeDouble(_frameHeight);

			writeUI16(b, "framerate".length);
			b.writeUTFBytes("framerate");
			b.writeByte(0); 
			b.writeDouble(_frameRate);

			writeUI16(b, "videocodecid".length);
			b.writeUTFBytes("videocodecid");
			b.writeByte(0); 
			b.writeDouble(SimpleFlvWriterCodecTypes.ScreenVideo); // 'Screen Video' = 3

			writeUI16(b, "canSeekToEnd".length);
			b.writeUTFBytes("canSeekToEnd");
			b.writeByte(1); 
			b.writeByte(int(true));
			
			var mdc:String = "ByTiger FlvEncoder";
			writeUI16(b, "metadatacreator".length);
			b.writeUTFBytes("metadatacreator");
			b.writeByte(2); 
			writeUI16(b, mdc.length);
			b.writeUTFBytes(mdc);
			
			// VariableEndMarker1 (type UI24 - always 9)
			writeUI24(b, 9);
		
			return b;
		}
		
		private function flvWriteTagVideo() : void
		{
			var pos : uint = _videoData.position;
			var dat : ByteArray = this.frameData();
			var timeStamp : uint = uint(1000 / _frameRate * _iteration);
			
			// write tag 'header'
			_videoData.writeByte( 0x09); 					// tagType = video
			writeUI24(_videoData, dat.length); 			// data size
			writeUI24(_videoData, timeStamp);				// timestamp in ms
			_videoData.writeByte(0);						// timestamp extended, not using *** 
			writeUI24(_videoData, 0);						// streamID always 0
			
			// write videodata			
			_videoData.writeBytes(dat);
			
			// save length
			_previousTagSize = _videoData.position - pos;
			
			// clear buffer
			dat.length = 0;
			dat = null;
		}
		
		private function flvWriteTagAudio(pcmData : ByteArray) : void
		{
			var pos : uint = _videoData.position;
			var timeStamp : uint = uint(1000 / _frameRate * _iteration);
			
			_videoData.writeByte( 0x08 ); 						// TagType - 8 = audio
			writeUI24(_videoData, pcmData.length + 1); 			// DataSize ("+1" for header)
			writeUI24(_videoData, timeStamp);					// Timestamp (ms)
			_videoData.writeByte(0);							// TimestampExtended - not using 
			writeUI24(_videoData, 0);							// StreamID - always 0
			
			// AUDIODATA			
			_videoData.writeByte(_soundPropertiesByte);		// header
			_videoData.writeBytes(pcmData);					// real sound data
			
			_previousTagSize = _videoData.position - pos;
		}
		
		private function floatsToSignedShorts(ba : ByteArray) : ByteArray
		{
			var out : ByteArray = new ByteArray();
			out.endian = Endian.LITTLE_ENDIAN;
			
			ba.position = 0;
			var num : int = ba.length / 4;
			
			for (var i : int = 0; i < num; i++)
			{
				var n : Number = ba.readFloat();
				var val : int = n * 32768;
				out.writeShort(val);
			}
			return out;
		}
		
		private function frameData() : ByteArray
		{
			var v : ByteArray = new ByteArray;
			
			// VIDEODATA 'header'
			v.writeByte(0x10 + SimpleFlvWriterCodecTypes.ScreenVideo); // frametype (1) + codecid (3)
			
			// SCREENVIDEOPACKET 'header'			
			// blockwidth/16-1 (4bits) + imagewidth (12bits)
			writeUI4_12(v, int(blockWidth/16) - 1,  _frameWidth);
			// blockheight/16-1 (4bits) + imageheight (12bits)
			writeUI4_12(v, int(blockHeight/16) - 1, _frameHeight);			

			// VIDEODATA > SCREENVIDEOPACKET > IMAGEBLOCKS:

			var yMax : int = int(_frameHeight/blockHeight);
			var yRemainder : int = _frameHeight % blockHeight; 
			if (yRemainder > 0) yMax += 1;

			var xMax : int = int(_frameWidth/blockWidth);
			var xRemainder : int = _frameWidth % blockWidth;				
			if (xRemainder > 0) xMax += 1;
				
			for (var y1 : int = 0; y1 < yMax; y1++)
			{
				for (var x1 : int = 0; x1 < xMax; x1++) 
				{
					// create block
					var block : ByteArray = new ByteArray();
					block.endian = Endian.LITTLE_ENDIAN;
					
					var yLimit : int = blockHeight;	
					if (yRemainder > 0 && y1 + 1 == yMax) yLimit = yRemainder;

					for (var y2 : int = 0; y2 < yLimit; y2++) 
					{
						var xLimit:int = blockWidth;
						if (xRemainder > 0 && x1 + 1 == xMax) xLimit = xRemainder;
						
						for (var x2 : int = 0; x2 < xLimit; x2++) 
						{
							var px:int = (x1 * blockWidth) + x2;
							var py:int = _frameHeight - ((y1 * blockHeight) + y2); // (flv's save from bottom to top)
							var p:uint = _bmp.getPixel(px, py);

							block.writeByte( p & 0xff ); 		// blue	
							block.writeByte( p >> 8 & 0xff ); 	// green
							block.writeByte( p >> 16 ); 		// red
						}
					}
					block.compress();

					writeUI16(v, block.length); // write block length (UI16)
					v.writeBytes( block ); // write block
					
					block.length = 0;
				}
			}
			
			return v;
		}

		private function writeUI24(stream:ByteArray, p:uint):void
		{
			var byte1:int = p >> 16;
			var byte2:int = p >> 8 & 0xff;
			var byte3:int = p & 0xff;
			stream.writeByte(byte1);
			stream.writeByte(byte2);
			stream.writeByte(byte3);
		}
		
		private function writeUI16(stream:ByteArray, p:uint):void
		{
			stream.writeByte( p >> 8 );
			stream.writeByte( p & 0xff );			
		}

		private function writeUI4_12(stream:ByteArray, p1:uint, p2:uint):void
		{
			// writes a 4-bit value followed by a 12-bit value in two sequential bytes

			var byte1a:int = p1 << 4;
			var byte1b:int = p2 >> 8;
			var byte1:int = byte1a + byte1b;
			var byte2:int = p2 & 0xff;

			stream.writeByte(byte1);
			stream.writeByte(byte2);
		}
		
		
		
		
		
		
		
		
		public static function byteArrayIndexOf($ba:ByteArray, $searchTerm:ByteArray):int
		{
			var origPosBa:int = $ba.position;
			var origPosSearchTerm:int = $searchTerm.position;
			
			var end:int = $ba.length - $searchTerm.length;
			for (var i:int = 0; i <= end; i++)
			{
				if(SimpleFlvWriter.byteArrayEqualsAt($ba, $searchTerm, i)) 
				{
					$ba.position = origPosBa;
					$searchTerm.position = origPosSearchTerm;
					return i;
				}
			}
			
			$ba.position = origPosBa;
			$searchTerm.position = origPosSearchTerm;
			return -1;
		}
		
		public static function byteArrayEqualsAt($ba:ByteArray, $searchTerm:ByteArray, $position:int):Boolean
		{
			// NB, function will modify byteArrays' cursors 
			if ($position + $searchTerm.length > $ba.length) return false;
			
			$ba.position = $position;
			$searchTerm.position = 0;
			
			for (var i:int = 0; i < $searchTerm.length; i++)
			{
				var valBa:int = $ba.readByte();
				var valSearch:int = $searchTerm.readByte();
				
				if (valBa != valSearch) return false;
			}
			return true;
		}
	}
}

/*
	FLV structure summary:

		header
		previoustagsize
		flvtag
			[info]
			videodata
				[info]
				screenvideopacket
					[info]
					imageblocks
					imageblocks
					...
		previoustagsize
		flvtag
		...
		

	FLV file format:
	
		header
		
		last tag size
	
		FLVTAG:
			tagtype
			datasize
			timestamp
			timestampextended
			streamid						
			data [VIDEODATA]:
				frametype
				codecid
				videodata [SCREENVIDEOPACKET]:
					blockwidth						ub[4]
					imagewidth						ub[12]
					blockheight						ub[4]
					imageheight						ub[12]
					imageblocks [IMAGEBLOCKS[]]:	
						datasize					ub[16] <same as 'ub16', i think>
						data..
		
		last tag size
		
		FLVTAG
		
		etc.		
*/
