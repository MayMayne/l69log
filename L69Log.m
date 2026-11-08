#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static dispatch_queue_t Q;
static BOOL Enabled;

static void L(NSString *fmt, ...) {
    if (!Q) return;
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    dispatch_async(Q, ^{
        @autoreleasepool {
            NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            if (!dir) return;
            NSString *p = [dir stringByAppendingPathComponent:@"l69.log"];
            if (![NSFileManager.defaultManager fileExistsAtPath:p])
                [NSFileManager.defaultManager createFileAtPath:p contents:nil attributes:nil];
            @try {
                NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
                if (!h) return;
                if ([h seekToEndOfFile] > 512000) { [h truncateFileAtOffset:0]; [h seekToFileOffset:0]; }
                NSString *line = [NSString stringWithFormat:@"%.0f %@\n", NSDate.date.timeIntervalSince1970, s];
                [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [h closeFile];
            } @catch (__unused NSException *e) { }
        }
    });
}

static BOOL Owns(Class c, SEL sel, Method *out) {
    unsigned n = 0; Method *m = class_copyMethodList(c, &n); BOOL f = NO;
    for (unsigned i = 0; i < n; i++) if (sel_isEqual(method_getName(m[i]), sel)) { if (out) *out = m[i]; f = YES; break; }
    free(m); return f;
}

static void HookRequest(void) {
    Class f = NSClassFromString(@"GTMSessionFetcher");
    SEL sel = NSSelectorFromString(@"setRequest:");
    Method m = f ? class_getInstanceMethod(f, sel) : NULL;
    if (!m) return;
    IMP o = method_getImplementation(m);
    IMP r = imp_implementationWithBlock(^(id self, NSURLRequest *req) {
        @try {
            NSString *u = [[req URL].absoluteString lowercaseString] ?: @"";
            if ([u containsString:@"firebasestorage"] || [u containsString:@"storage.googleapis"]) {
                NSString *cmd = [req valueForHTTPHeaderField:@"X-Goog-Upload-Command"];
                NSString *off = [req valueForHTTPHeaderField:@"X-Goog-Upload-Offset"];
                NSString *tot = [req valueForHTTPHeaderField:@"X-Goog-Upload-Content-Length"];
                NSString *cl = [req valueForHTTPHeaderField:@"Content-Length"];
                NSString *ac = [req valueForHTTPHeaderField:@"X-Firebase-AppCheck"];
                NSString *au = [req valueForHTTPHeaderField:@"Authorization"];
                NSString *ct = [req valueForHTTPHeaderField:@"Content-Type"];
                L(@"REQ %@ cmd=%@ off=%@ total=%@ len=%@ appcheck=%lu auth=%lu ct=%@",
                  req.HTTPMethod, cmd ?: @"-", off ?: @"-", tot ?: @"-", cl ?: @"-",
                  (unsigned long)ac.length, (unsigned long)au.length, ct ?: @"-");
            }
        } @catch (__unused NSException *e) { }
        ((void (*)(id, SEL, id))o)(self, sel, req);
    });
    class_replaceMethod(f, sel, r, method_getTypeEncoding(m));
    L(@"hooked setRequest");
}

static void HookResponse(void) {
    Class f = NSClassFromString(@"GTMSessionFetcher");
    SEL sel = NSSelectorFromString(@"setResponse:");
    Method m = f ? class_getInstanceMethod(f, sel) : NULL;
    if (!m) return;
    IMP o = method_getImplementation(m);
    IMP r = imp_implementationWithBlock(^(id self, NSURLResponse *resp) {
        @try {
            if ([resp isKindOfClass:NSHTTPURLResponse.class]) {
                NSHTTPURLResponse *h = (NSHTTPURLResponse *)resp;
                NSString *u = [[h URL].absoluteString lowercaseString] ?: @"";
                if ([u containsString:@"firebasestorage"] || [u containsString:@"storage.googleapis"]) {
                    NSString *us = h.allHeaderFields[@"X-Goog-Upload-Status"];
                    NSString *rec = h.allHeaderFields[@"X-Goog-Upload-Size-Received"];
                    L(@"RESP %ld us=%@ recv=%@", (long)h.statusCode, us ?: @"-", rec ?: @"-");
                }
            }
        } @catch (__unused NSException *e) { }
        ((void (*)(id, SEL, id))o)(self, sel, resp);
    });
    class_replaceMethod(f, sel, r, method_getTypeEncoding(m));
    L(@"hooked setResponse");
}

static void HookExport(void) {
    Class c = NSClassFromString(@"AVAssetExportSession");
    SEL sel = NSSelectorFromString(@"exportAsynchronouslyWithCompletionHandler:");
    Method m = c ? class_getInstanceMethod(c, sel) : NULL;
    if (!m) return;
    IMP o = method_getImplementation(m);
    IMP r = imp_implementationWithBlock(^(id self, void (^cb)(void)) {
        @try {
            NSURL *out = [self valueForKey:@"outputURL"];
            NSString *type = [self valueForKey:@"outputFileType"];
            long long lim = [[self valueForKey:@"fileLengthLimit"] longLongValue];
            L(@"EXPORT out=%@ type=%@ limit=%lld", out.lastPathComponent ?: @"-", type ?: @"-", lim);
            void (^wrap)(void) = ^{
                @try {
                    NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:out.path error:NULL];
                    L(@"EXPORT done status=%ld bytes=%lld", (long)[[self valueForKey:@"status"] integerValue],
                      (long long)[a[NSFileSize] longLongValue]);
                } @catch (__unused NSException *e) { }
                if (cb) cb();
            };
            ((void (*)(id, SEL, id))o)(self, sel, wrap);
            return;
        } @catch (__unused NSException *e) { }
        ((void (*)(id, SEL, id))o)(self, sel, cb);
    });
    class_replaceMethod(c, sel, r, method_getTypeEncoding(m));
    L(@"hooked export");
}

__attribute__((constructor)) static void L69Load(void) {
    @autoreleasepool {
        NSString *exe = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
        if (![exe isEqualToString:@"Locket"]) return;
        Enabled = YES;
        Q = dispatch_queue_create("l69.log", DISPATCH_QUEUE_SERIAL);
        L(@"=== L69 start ===");
        HookRequest();
        HookResponse();
        HookExport();
        dispatch_async(dispatch_get_main_queue(), ^{ HookRequest(); HookResponse(); HookExport(); });
    }
}
