// ISLe8 MediaRemote bridge.
//
// Since macOS 15.4 MediaRemote only answers processes with an Apple identity, so this
// library is loaded into /usr/bin/perl (see isle8-media.pl) and talks to the app over
// stdin/stdout:
//   stdout: one JSON object per line  {"type":"data","payload":{...}|null}
//                                      {"type":"ack","command":2,"ok":true}
//   stdin:  "get" | "cmd <MRCommand>" | "seek <seconds>"
// Closing stdin (the app quit) ends the process.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*MRClientStringFn)(id);
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFn)(int, CFDictionaryRef);
typedef void (*MRSetElapsedFn)(double);

static void *mr;
static MRGetInfoFn MRGetInfo;
static MRGetIsPlayingFn MRGetIsPlaying;
static MRGetClientFn MRGetClient;
static MRClientStringFn MRClientBundleID;
static MRClientStringFn MRClientParentBundleID;
static MRSendCommandFn MRSendCommand;
static MRSetElapsedFn MRSetElapsed;

static NSData *lastArtwork;
static BOOL fetchScheduled;
static dispatch_source_t stdinSource;

static NSString *MRKey(const char *name) {
    CFStringRef *value = dlsym(mr, name);
    return value ? (__bridge NSString *)*value : @(name);
}

static void emit(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void put(NSMutableDictionary *payload, NSString *key, id value) {
    if (value && value != (id)kCFNull) payload[key] = value;
}

static void emitInfo(NSDictionary *info, BOOL playing, NSString *bundleID, NSString *parentBundleID) {
    if (info.count == 0) {
        lastArtwork = nil;
        emit(@{@"type": @"data", @"payload": [NSNull null]});
        return;
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    put(payload, @"title", info[MRKey("kMRMediaRemoteNowPlayingInfoTitle")]);
    put(payload, @"artist", info[MRKey("kMRMediaRemoteNowPlayingInfoArtist")]);
    put(payload, @"album", info[MRKey("kMRMediaRemoteNowPlayingInfoAlbum")]);
    put(payload, @"duration", info[MRKey("kMRMediaRemoteNowPlayingInfoDuration")]);
    put(payload, @"elapsed", info[MRKey("kMRMediaRemoteNowPlayingInfoElapsedTime")]);
    put(payload, @"rate", info[MRKey("kMRMediaRemoteNowPlayingInfoPlaybackRate")]);
    put(payload, @"shuffle", info[MRKey("kMRMediaRemoteNowPlayingInfoShuffleMode")]);
    put(payload, @"repeat", info[MRKey("kMRMediaRemoteNowPlayingInfoRepeatMode")]);
    put(payload, @"bundleID", bundleID);
    put(payload, @"parentBundleID", parentBundleID);
    payload[@"playing"] = @(playing);

    id timestamp = info[MRKey("kMRMediaRemoteNowPlayingInfoTimestamp")];
    if ([timestamp isKindOfClass:[NSDate class]]) {
        payload[@"timestamp"] = @([(NSDate *)timestamp timeIntervalSince1970]);
    }

    // Artwork is large, so it is only sent when it actually changes.
    id artwork = info[MRKey("kMRMediaRemoteNowPlayingInfoArtworkData")];
    if ([artwork isKindOfClass:[NSData class]] && [(NSData *)artwork length] > 0) {
        if (![artwork isEqualToData:lastArtwork]) {
            lastArtwork = artwork;
            payload[@"artwork"] = [(NSData *)artwork base64EncodedStringWithOptions:0];
        } else {
            payload[@"artworkUnchanged"] = @YES;
        }
    } else {
        lastArtwork = nil;
    }

    emit(@{@"type": @"data", @"payload": payload});
}

static void fetch(void) {
    if (!MRGetInfo) return;
    dispatch_queue_t main = dispatch_get_main_queue();
    MRGetInfo(main, ^(CFDictionaryRef cfInfo) {
        NSDictionary *info = [(__bridge NSDictionary *)cfInfo copy];
        void (^finish)(BOOL) = ^(BOOL playing) {
            if (!MRGetClient || !MRClientBundleID) {
                emitInfo(info, playing, nil, nil);
                return;
            }
            MRGetClient(main, ^(id client) {
                NSString *bundleID = client ? (__bridge NSString *)MRClientBundleID(client) : nil;
                NSString *parent = (client && MRClientParentBundleID)
                    ? (__bridge NSString *)MRClientParentBundleID(client) : nil;
                emitInfo(info, playing, bundleID, parent);
            });
        };
        if (MRGetIsPlaying) {
            MRGetIsPlaying(main, ^(Boolean playing) { finish(playing); });
        } else {
            NSNumber *rate = info[MRKey("kMRMediaRemoteNowPlayingInfoPlaybackRate")];
            finish(rate.doubleValue > 0);
        }
    });
}

// Notifications arrive in bursts (one track change fires several), so coalesce them.
static void scheduleFetch(void) {
    if (fetchScheduled) return;
    fetchScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        fetchScheduled = NO;
        fetch();
    });
}

static void handleLine(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *verb = parts.firstObject;
    if ([verb isEqualToString:@"get"]) {
        fetch();
    } else if ([verb isEqualToString:@"cmd"] && parts.count > 1) {
        int command = parts[1].intValue;
        BOOL ok = MRSendCommand ? MRSendCommand(command, NULL) : NO;
        emit(@{@"type": @"ack", @"command": @(command), @"ok": @(ok)});
    } else if ([verb isEqualToString:@"seek"] && parts.count > 1) {
        if (MRSetElapsed) MRSetElapsed(parts[1].doubleValue);
        scheduleFetch();
    }
}

static void listenToStdin(void) {
    static NSMutableData *buffer;
    buffer = [NSMutableData data];
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0,
                                                      dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{
        char chunk[1024];
        ssize_t count = read(STDIN_FILENO, chunk, sizeof chunk);
        if (count <= 0) {
            // The app closed the pipe. Give in-flight replies a moment, then leave.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                exit(0);
            });
            dispatch_source_cancel(source);
            return;
        }
        [buffer appendBytes:chunk length:(NSUInteger)count];
        const char *bytes = buffer.bytes;
        NSUInteger start = 0;
        for (NSUInteger i = 0; i < buffer.length; i++) {
            if (bytes[i] != '\n') continue;
            NSString *line = [[NSString alloc] initWithBytes:bytes + start length:i - start
                                                    encoding:NSUTF8StringEncoding];
            line = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (line.length) handleLine(line);
            start = i + 1;
        }
        [buffer replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
    });
    dispatch_resume(source);
    stdinSource = source;
}

// Called from Perl as an XSUB. It never returns.
__attribute__((visibility("default")))
void isle8_mr_run(void *interpreter, void *cv) {
    (void)interpreter;
    (void)cv;
    signal(SIGPIPE, SIG_DFL);

    mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (!mr) {
        emit(@{@"type": @"error", @"message": @"MediaRemote could not be loaded"});
        exit(1);
    }
    MRGetInfo = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    MRGetIsPlaying = (MRGetIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    MRGetClient = (MRGetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    MRClientBundleID = (MRClientStringFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    MRClientParentBundleID = (MRClientStringFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    MRSendCommand = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
    MRSetElapsed = (MRSetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
    MRRegisterFn registerForNotifications =
        (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");

    if (!MRGetInfo || !registerForNotifications) {
        emit(@{@"type": @"error", @"message": @"MediaRemote symbols are missing"});
        exit(1);
    }

    registerForNotifications(dispatch_get_main_queue());
    NSArray<NSString *> *names = @[
        MRKey("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
        MRKey("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
        MRKey("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
    ];
    for (NSString *name in names) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            (void)note;
            scheduleFetch();
        }];
    }

    emit(@{@"type": @"ready"});
    listenToStdin();
    fetch();
    CFRunLoopRun();
    exit(0);
}
