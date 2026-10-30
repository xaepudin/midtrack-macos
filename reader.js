// Persistent now-playing reader for Midtrack (macOS).
// Runs as: osascript -l JavaScript reader.js
// osascript is Apple-signed, which is what grants the private MediaRemote read
// on modern macOS; a normal helper binary gets nil for the same calls.
// Prints one JSON line per snapshot (10 Hz, plus a line per MediaRemote change):
// {"app":…,"t":title,"a":artist,"d":duration,"e":elapsed,"r":rate}

ObjC.import('Foundation')

var bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework')
bundle.load
var MR = $.NSClassFromString('MRNowPlayingRequest')

function snapshot() {
    if (!MR) return { app: null, t: null, a: null, d: -1, e: -1, r: 0 }
    var path = MR.localNowPlayingPlayerPath
    if (!path || !path.client) return { app: null, t: null, a: null, d: -1, e: -1, r: 0 }
    var s = { app: String(ObjC.unwrap(path.client.displayName) || ''), t: null, a: null, d: -1, e: -1, r: 0 }
    var item = MR.localNowPlayingItem
    if (!item) return s
    var info = item.nowPlayingInfo
    if (!info) return s
    function str(k) { var v = info.objectForKey(k); return v ? String(ObjC.unwrap(v)) : null }
    function num(k) { var v = info.objectForKey(k); return v ? v.doubleValue : -1 }
    s.t = str('kMRMediaRemoteNowPlayingInfoTitle')
    s.a = str('kMRMediaRemoteNowPlayingInfoArtist')
    s.d = num('kMRMediaRemoteNowPlayingInfoDuration')
    s.e = num('kMRMediaRemoteNowPlayingInfoElapsedTime')
    s.r = num('kMRMediaRemoteNowPlayingInfoPlaybackRate')
    var ts = info.objectForKey('kMRMediaRemoteNowPlayingInfoTimestamp')
    s.ts = ts ? ts.timeIntervalSince1970 : -1
    return s
}

function out(obj) {
    var line = JSON.stringify(obj) + '\n'
    var data = $.NSString.alloc.initWithUTF8String(line).dataUsingEncoding($.NSUTF8StringEncoding)
    $.NSFileHandle.fileHandleWithStandardOutput.writeData(data)
}

// Event-driven push (best effort): MediaRemote posts this notification on
// now-playing changes. If the run loop delivers it between polls, the seek
// fires ~instantly instead of waiting for the next poll.
// (JXA calls multi-part selectors as one concatenated name, positional args.)
var token = $.NSNotificationCenter.defaultCenter
    .addObserverForNameObjectQueueUsingBlock(
        'kMRMediaRemoteNowPlayingInfoDidChangeNotification',
        null,
        $.NSOperationQueue.mainQueue,
        function (n) { out(snapshot()) }
    )

while (true) {
    out(snapshot())
    delay(0.1)
}
