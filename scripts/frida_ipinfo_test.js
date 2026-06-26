// Test ipinfo.io lookup from SpringBoard network context (same as tweak).
if (!ObjC.available) {
    console.log('ObjC not available');
} else {
    var ip = '23.132.124.147';
    var comp = ObjC.classes.NSURLComponents.componentsWithString_('https://ipinfo.io');
    comp.setPath_('/' + ip + '/json');
    var url = comp.URL();
    console.log('Fetching: ' + url.absoluteString().toString());

    var sem = ObjC.classes.NSObject.alloc().init(); // placeholder
    var done = false;
    var result = null;
    var err = null;

    var task = ObjC.classes.NSURLSession.sharedSession()
        .dataTaskWithURL_completionHandler_(url, new ObjC.Block({
            retType: 'void',
            argTypes: ['object', 'object', 'object'],
            implementation: function (data, response, error) {
                if (error) err = error.toString();
                else if (data) result = ObjC.classes.NSString.alloc()
                    .initWithData_encoding_(data, 4).toString();
                done = true;
            }
        }));
    task.resume();

    var start = Date.now();
    while (!done && Date.now() - start < 15000) {
        Thread.sleep(0.1);
    }
    if (!done) console.log('TIMEOUT');
    else if (err) console.log('ERROR: ' + err);
    else console.log('RESPONSE: ' + result);
}