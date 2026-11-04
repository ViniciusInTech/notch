#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include "NotchMediaBridge.h"

typedef void (*RegisterFn)(dispatch_queue_t);
typedef void (*InfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*PlayingFn)(dispatch_queue_t, void (^)(BOOL));
typedef void (*ClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*ClientStringFn)(id);
typedef Boolean (*CommandFn)(int, NSDictionary *);
typedef void (*ElapsedFn)(double);

static dispatch_queue_t queue;
static RegisterFn registerFn;
static InfoFn infoFn;
static PlayingFn playingFn;
static ClientFn clientFn;
static ClientStringFn bundleFn, parentFn;
static CommandFn commandFn;
static ElapsedFn elapsedFn;
static NSUInteger generation;
static NSData *lastArtwork;
static NSUInteger artworkSerial;
static NSString *lastTrack;
static NSDictionary *lastEmitted;

static void emit(NSDictionary *payload) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id number(id value) { return [value isKindOfClass:NSNumber.class] ? value : nil; }
static id text(id value) { return [value isKindOfClass:NSString.class] ? value : nil; }

static void publish(void) {
    NSUInteger current = ++generation;
    infoFn(queue, ^(NSDictionary *info) {
        playingFn(queue, ^(BOOL playing) {
            clientFn(queue, ^(id client) {
                if (current != generation) return;
                if (info.count == 0) {
                    lastArtwork = nil; lastTrack = nil;
                    if (![lastEmitted isEqual:@{@"empty": @YES}]) { lastEmitted = @{@"empty": @YES}; emit(lastEmitted); }
                    return;
                }
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"playing"] = @(playing);
                out[@"title"] = text(info[@"kMRMediaRemoteNowPlayingInfoTitle"]) ?: @"";
                out[@"artist"] = text(info[@"kMRMediaRemoteNowPlayingInfoArtist"]) ?: @"";
                out[@"album"] = text(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]) ?: @"";
                out[@"duration"] = number(info[@"kMRMediaRemoteNowPlayingInfoDuration"]) ?: @0;
                out[@"elapsed"] = number(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]) ?: @0;
                out[@"rate"] = number(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]) ?: @(playing ? 1 : 0);
                id stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                out[@"timestamp"] = @([stamp isKindOfClass:NSDate.class] ? [stamp timeIntervalSince1970] : NSDate.date.timeIntervalSince1970);
                if (client) {
                    NSString *parent = parentFn ? text(parentFn(client)) : nil;
                    NSString *bundle = bundleFn ? text(bundleFn(client)) : nil;
                    if (parent.length || bundle.length) out[@"bundle"] = parent.length ? parent : bundle;
                }
                NSString *track = [NSString stringWithFormat:@"%@\x1f%@\x1f%@\x1f%@", out[@"bundle"] ?: @"", out[@"title"], out[@"artist"], out[@"album"]];
                if (![track isEqualToString:lastTrack]) { lastTrack = track; lastArtwork = nil; }
                id artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                NSString *encoded = nil;
                // Some updates omit the image; the track keeps the last one it had.
                if ([artwork isKindOfClass:NSData.class] && [artwork length] > 0 && [artwork length] <= 2000000
                    && ![artwork isEqualToData:lastArtwork]) {
                    lastArtwork = artwork;
                    artworkSerial++;
                    encoded = [artwork base64EncodedStringWithOptions:0];
                }
                if (lastArtwork) out[@"artworkId"] = @(artworkSerial);
                // Image bytes cross the pipe only when they change.
                if (!encoded && [out isEqual:lastEmitted]) return;
                lastEmitted = [out copy];
                if (encoded) out[@"artwork"] = encoded;
                emit(out);
            });
        });
    });
}

/// Coalesces bursts of notifications into one read.
static void schedule(void) {
    static BOOL pending;
    if (pending) return;
    pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), queue, ^{ pending = NO; publish(); });
}

static void handle(NSString *line) {
    // MRMediaRemoteCommand: 2 toggle, 4 next, 5 previous.
    if ([line isEqualToString:@"toggle"]) commandFn(2, nil);
    else if ([line isEqualToString:@"next"]) commandFn(4, nil);
    else if ([line isEqualToString:@"previous"]) commandFn(5, nil);
    else if ([line hasPrefix:@"seek "] && elapsedFn) {
        double seconds = [[line substringFromIndex:5] doubleValue];
        if (isfinite(seconds) && seconds >= 0) elapsedFn(seconds);
    }
    schedule();
}

void notch_media_stream(void *interpreter, void *cv) {
    (void)interpreter; (void)cv;
    void *library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!library) exit(3);
    registerFn = (RegisterFn)dlsym(library, "MRMediaRemoteRegisterForNowPlayingNotifications");
    infoFn = (InfoFn)dlsym(library, "MRMediaRemoteGetNowPlayingInfo");
    playingFn = (PlayingFn)dlsym(library, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    clientFn = (ClientFn)dlsym(library, "MRMediaRemoteGetNowPlayingClient");
    bundleFn = (ClientStringFn)dlsym(library, "MRNowPlayingClientGetBundleIdentifier");
    parentFn = (ClientStringFn)dlsym(library, "MRNowPlayingClientGetParentAppBundleIdentifier");
    commandFn = (CommandFn)dlsym(library, "MRMediaRemoteSendCommand");
    elapsedFn = (ElapsedFn)dlsym(library, "MRMediaRemoteSetElapsedTime");
    if (!registerFn || !infoFn || !playingFn || !clientFn || !commandFn) exit(3);

    queue = dispatch_queue_create("dev.vinicius.Notch.media", DISPATCH_QUEUE_SERIAL);
    registerFn(queue);
    NSArray *names = @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                       @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                       @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                       @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange"];
    for (NSString *name in names) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { (void)note; dispatch_async(queue, ^{ schedule(); }); }];
    }

    // The app owns stdin; when it quits or restarts the helper, this process ends too.
    dispatch_source_t input = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);
    __block NSMutableData *buffer = [NSMutableData data];
    dispatch_source_set_event_handler(input, ^{
        char chunk[512];
        ssize_t count = read(STDIN_FILENO, chunk, sizeof chunk);
        if (count <= 0) exit(0);
        [buffer appendBytes:chunk length:(NSUInteger)count];
        if (buffer.length > 4096) exit(4);
        while (YES) {
            NSRange newline = [buffer rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buffer.length)];
            if (newline.location == NSNotFound) break;
            NSString *line = [[NSString alloc] initWithData:[buffer subdataWithRange:NSMakeRange(0, newline.location)] encoding:NSUTF8StringEncoding];
            [buffer replaceBytesInRange:NSMakeRange(0, newline.location + 1) withBytes:NULL length:0];
            if (line) handle(line);
        }
    });
    dispatch_resume(input);
    dispatch_async(queue, ^{ publish(); });
    CFRunLoopRun();
    exit(0);
}
