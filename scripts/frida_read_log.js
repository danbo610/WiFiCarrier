// Attach to SpringBoard and read WiFiCarrier debug log + relevant prefs.
// Usage: frida -U -n SpringBoard -l scripts/frida_read_log.js

if (!ObjC.available) {
    console.log('ObjC not available');
} else {
    var fm = ObjC.classes.NSFileManager.defaultManager();
    var logPath = '/tmp/WiFiCarrier.log';
    var prefsPath = '/var/mobile/Library/Preferences/com.highrez.wificarrier.plist';

    function readFile(path) {
        var pool = ObjC.classes.NSAutoreleasePool.alloc().init();
        try {
            if (!fm.fileExistsAtPath_(path)) {
                console.log('[missing] ' + path);
                return null;
            }
            var s = ObjC.classes.NSString.stringWithContentsOfFile_encoding_error_(path, 4, NULL);
            if (s) return s.toString();
            return '(read failed)';
        } finally {
            pool.release();
        }
    }

    console.log('=== WiFiCarrier.log (tail) ===');
    var log = readFile(logPath);
    if (log) {
        var lines = log.split('\n');
        var tail = lines.slice(Math.max(0, lines.length - 60));
        console.log(tail.join('\n'));
    }

    console.log('\n=== prefs (ipGeo / ExtIP / debug) ===');
    var dict = ObjC.classes.NSDictionary.dictionaryWithContentsOfFile_(prefsPath);
    if (!dict) {
        console.log('[missing] ' + prefsPath);
    } else {
        var keys = [
            'enableDebug', 'enableExtIP_1', 'enableExtIP_2',
            'enableIPADDR_1', 'enableIPADDR_2', 'enableSSID_1', 'enableSSID_2',
            'ipGeoMode_1', 'ipGeoMode_2', 'publicIPURL_1', 'publicIPURL_2', 'ipinfoToken'
        ];
        keys.forEach(function (k) {
            var v = dict.objectForKey_(k);
            if (v !== null) console.log(k + ' = ' + v.toString());
        });
    }
}