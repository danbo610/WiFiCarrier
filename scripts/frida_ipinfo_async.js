if (ObjC.available) {
    var comp = ObjC.classes.NSURLComponents.componentsWithString_('https://ipinfo.io');
    comp.setPath_('/23.132.124.147/json');
    var url = comp.URL();
    console.log('URL: ' + url.absoluteString());
    var task = ObjC.classes.NSURLSession.sharedSession()
        .dataTaskWithURL_completionHandler_(url, new ObjC.Block({
            retType: 'void',
            argTypes: ['object', 'object', 'object'],
            implementation: function (data, resp, err) {
                if (err) console.log('ERR: ' + err.toString());
                else if (data)
                    console.log('OK: ' + ObjC.classes.NSString.alloc()
                        .initWithData_encoding_(data, 4).toString());
                else console.log('empty response');
            }
        }));
    task.resume();
    setTimeout(function () { console.log('done waiting'); }, 8000);
}