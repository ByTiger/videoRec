package org.tiger.network 
{
	import flash.utils.ByteArray;	
	import flash.net.URLRequestHeader;	
	import flash.events.IOErrorEvent;	
	import flash.events.Event;	
	import flash.events.HTTPStatusEvent;	
	import flash.events.ProgressEvent;	
	import flash.events.SecurityErrorEvent;	
	import flash.net.URLRequestMethod;	
	import flash.net.URLRequest;	
	import flash.net.URLLoader;	
	import flash.events.IEventDispatcher;	
	import flash.events.EventDispatcher;
	
	/**
	 * @author Tiger
	 */
	public class PostFormData extends EventDispatcher 
	{
		private var _loader : URLLoader = null;
		private var _data : PostDataHelper = null;
		private var _httpStatusText : String = "";
		private var _httpStatus : int = 0;
		private var _userData : Object = null;
		
		public function PostFormData(target : IEventDispatcher = null)
		{
			super(target);
			_loader = new URLLoader();
			_data = new PostDataHelper();
			addLoaderListeners();
		}
		
		// clear post-data buffer
		public function Clear() : void
		{
			this.Release();
			
			_loader = new URLLoader();
			addLoaderListeners();
			_data = new PostDataHelper();
		}
		
		// release all object (for call before delete object)
		public function Release() : void
		{
			removeLoaderListeners();
			_loader = null;
			_data.Release();
			_data = null;
		}
		
		// set user object
		public function set userData(obj : Object) : void
		{
			_userData = obj;
		}
		
		// get user object
		public function get userData() : Object
		{
			return _userData;
		}
		
		// add param for post by multipart/form-data rules
		public function addParam(param : String, value : String) : void
		{
			_data.addParam(param, value);
		}
		
		// add file and close post data by multipart/form-data rules
		// don't call preparePostData() after
		public function addFile(fileName : String, byteArray : ByteArray, uploadDataFieldName : String = "Filedata") : void
		{
			_data.addFile(fileName, byteArray, uploadDataFieldName);
		}
		
		// add binary data to post request
		// @param params -- is array of strings
		public function addData(params : Array, byteArray : ByteArray) : void
		{
			_data.addData(params, byteArray);
		}
		
		// close post data and prepare for post
		public function preparePostData() : void
		{
			_data.CloseBoundary();
		}
		
		// get ByteArray of post buffer
		public function GetPostBuffer() : ByteArray
		{
			return _data.data;
		}
		
		// set content type of post
		// default: multipart/form-data
		public function SetContentType(type : String) : void
		{
			_data.ContentType = type;
		}
		
		// post data to server
		// @param url -- URL for post data
		// @param headers -- array of string to add to post's header
		public function Post(url : String, headers : Array) : void
		{
			var urlRequest : URLRequest = new URLRequest();
			urlRequest.url = url;
			urlRequest.method = URLRequestMethod.POST;
			urlRequest.contentType = _data.ContentType;
			_data.data.position = 0;
			urlRequest.data = _data.data;
			
			var qq : int;
			var hinfo : Array;
			if(headers.length > 0)
			{
				for(qq = 0; qq < headers.length; qq++)
				{
					hinfo = String(headers[qq]).split(":",2);
					urlRequest.requestHeaders.push(new URLRequestHeader(hinfo[0]?hinfo[0]:"", hinfo[1]?hinfo[1]:""));
				}
			}
			
			_loader.load(urlRequest);
			onSendStart();
		}
		
		private function addLoaderListeners() : void
		{
            _loader.addEventListener(Event.COMPLETE, onLoadComplete);
            _loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, onHttpStatusChange);
            _loader.addEventListener(IOErrorEvent.IO_ERROR, onIOError);
            _loader.addEventListener(ProgressEvent.PROGRESS, onUploadProgress);
            _loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
		}
		
		private function removeLoaderListeners() : void
		{
            _loader.removeEventListener(Event.COMPLETE, onLoadComplete);
            _loader.removeEventListener(HTTPStatusEvent.HTTP_STATUS, onHttpStatusChange);
            _loader.removeEventListener(IOErrorEvent.IO_ERROR, onIOError);
            _loader.removeEventListener(ProgressEvent.PROGRESS, onUploadProgress);
            _loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
		}
		
		private function onUploadProgress(e : ProgressEvent) : void
		{
			dispatchEvent(new PostFormDataEvent(PostFormDataEvent.PROGRESS,false,false,e.bytesLoaded, e.bytesTotal));
		}
		
		private function onSendStart(e : Event = null) : void
		{
			dispatchEvent(new PostFormDataEvent(PostFormDataEvent.POST_START,false,false,0,0));
		}
		
		private function onHttpStatusChange(event : HTTPStatusEvent) : void
		{
			_httpStatus = int(event.status);
			if(event.status != 0 && event.status < 400) return;
			
			var msg : String;
			switch(event.status)
			{
				case 400:
					msg = "Bad Request";
					break;
				case 401:
					msg = "Unauthorized";
					break;
				case 403:
					msg = "Forbidden";
					break;
				case 404:
					msg = "Not Found";
					break;
				case 405:
					msg = "Method Not Allowed";
					break;
				case 406:
					msg = "Not Acceptable";
					break;
				case 407:
					msg = "Proxy Authentication Required";
					break;
				case 408:
					msg = "Request Timeout";
					break;
				case 409:
					msg = "Conflict";
					break;
				case 410:
					msg = "Gone";
					break;
				case 411:
					msg = "Length Required";
					break;
				case 412:
					msg = "Precondition Failed";
					break;
				case 413:
					msg = "Request Entity Too Large";
					break;
				case 414:
					msg = "Request-URI Too Long";
					break;
				case 415:
					msg = "Unsupported Media Type";
					break;
				case 416:
					msg = "Requested Range Not Satisfiable";
					break;
				case 417:
					msg = "Expectation Failed";
					break;
				case 500:
					msg = "Internal Server Error";
					break;
				case 501:
					msg = "Not Implemented";
					break;
				case 502:
					msg = "Bad Gateway";
					break;
				case 503:
					msg = "Service Unavailable";
					break;
				case 504:
					msg = "Gateway Timeout";
					break;
				case 505:
					msg = "HTTP Version Not Supported";
					break;
				default:
					msg = "Unhandled HTTP status";
			}
			_httpStatusText = msg;
		}
		
		private function onLoadComplete(event : Event) : void
		{
			dispatchEvent(new PostFormDataEvent(PostFormDataEvent.COMPLETE,false,false,0,0,_httpStatus,String((event.target as URLLoader).data)));
		}
		
		private function onIOError(e : IOErrorEvent) : void
		{
			dispatchEvent(new PostFormDataEvent(PostFormDataEvent.ERROR,false,false,0,0,_httpStatus));
		}
		
		private function onSecurityError(e : IOErrorEvent) : void
		{
			dispatchEvent(new PostFormDataEvent(PostFormDataEvent.ERROR,false,false,0,0,_httpStatus));
		}
	}
}
