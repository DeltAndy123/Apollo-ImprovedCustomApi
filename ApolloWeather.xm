// ApolloWeather.xm
// Fixes the "Subreddit Weather and Time" feature gate that Apollo checks
// against the defunct apollogur.download backend.
//
// Root cause:
//   WeatherManager is a Swift singleton created via swift_once (token at
//   qword_100ca93e8, body sub_1003e497c). The body starts an async GET to
//   apollogur.download/api/is_subreddit_weather_enabled/ and, on success,
//   sets isEnabled=true at offset +0x10 on the singleton object.
//
//   SettingsGeneralViewController.viewDidLoad (sub_100138f1c) runs:
//     swift_once(token, body, 0)          ← creates singleton, fires async fetch
//     if (*(uint8_t *)(singleton + 0x10)) ← read isEnabled SYNCHRONOUSLY
//         // add "Subreddit Weather and Time" Eureka row
//
//   The async response never arrives (backend down) so isEnabled is always 0
//   and the toggle row is never added to the form.
//
// Fix:
//   Hook viewDidLoad. Before calling %orig:
//     1. dispatch_once_f with the same token → creates the singleton
//        (swift_once uses dispatch_once_f internally; predicates are compatible)
//     2. Force singleton[0x10] = 1
//   %orig then runs with isEnabled already true and adds the row.
//
//   We also register ApolloWeatherProtocol for the shared NSURLSession so the
//   background fetch Apollo fires completes silently instead of logging errors.
//
// NOTE: No MSHookFunction / code-section patching is used. All hooking goes
//       through Logos ObjC method swizzling to avoid W^X / code-signing issues.

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import "ApolloCommon.h"

// ─── Binary Address Offsets (Hopper static base 0x100000000) ─────────────────

// dispatch_once_t token for the WeatherManager swift_once call.
static const uintptr_t kOnceTokenOffset    = 0x100ca93e8 - 0x100000000;
// swift_once callback body that allocates WeatherManager and starts async fetch.
// Signature: void (*)(void *) — the void* arg is swift_once context (always NULL
// here) and is ignored by the function body.
static const uintptr_t kOnceBodyOffset     = 0x1003e497c - 0x100000000;
// __DATA global holding the WeatherManager singleton pointer after once runs.
static const uintptr_t kSingletonOffset    = 0x100cfd900 - 0x100000000;
// Byte offset of the isEnabled Bool within WeatherManager (confirmed via
// sub_1003e5110 success path: *(int8_t *)(singleton + 0x10) = 1).
static const ptrdiff_t kIsEnabledOffset    = 0x10;

// URL prefix for the global feature-gate check (used by the shared session).
static NSString *const kWeatherEnabledURL  = @"https://apollogur.download/api/is_subreddit_weather_enabled/";

// ─── Helper ───────────────────────────────────────────────────────────────────

// Finds Apollo's actual load address by name to be robust in substrate
// environments where image 0 may not be the main executable.
static uintptr_t apolloBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, ".app/Apollo") != NULL) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    ApolloLog(@"Weather: could not find Apollo image by name, falling back to image 0");
    return (uintptr_t)_dyld_get_image_header(0);
}

// ─── Settings VC Hook ─────────────────────────────────────────────────────────

%group WeatherFix

%hook _TtC6Apollo29SettingsGeneralViewController

- (void)viewDidLoad {
    uintptr_t base = apolloBase();

    // 1. Ensure the WeatherManager singleton exists.
    //    swift_once uses dispatch_once_f internally with compatible predicate
    //    layout, so dispatch_once_f with the same token is safe and idempotent.
    dispatch_once_t *token = (dispatch_once_t *)(base + kOnceTokenOffset);
    dispatch_function_t body = (dispatch_function_t)(base + kOnceBodyOffset);
    dispatch_once_f(token, NULL, body);

    // 2. Force isEnabled = true so viewDidLoad adds the weather toggle row.
    uint8_t **singletonPtr = (uint8_t **)(base + kSingletonOffset);
    uint8_t  *mgr          = *singletonPtr;
    if (mgr) {
        mgr[kIsEnabledOffset] = 1;
        ApolloLog(@"Weather: forced WeatherManager.isEnabled=true (singleton=%p)", mgr);
    } else {
        ApolloLog(@"Weather: WARNING singleton nil after dispatch_once_f");
    }

    // 3. Build the Eureka form — it now finds isEnabled=true and adds the row.
    %orig;
}

%end

%end // WeatherFix

// ─── NSURLProtocol: intercept is_subreddit_weather_enabled ───────────────────
//
// Apollo's WeatherManager uses [NSURLSession sharedSession] for the feature-gate
// fetch, which bypasses the defaultSessionConfiguration hook in ApolloTweetBuddy.
// Register a protocol for the global session so the async request completes
// cleanly with {"is_enabled":true} instead of logging network errors.

static NSString *const kWeatherHandledKey = @"ApolloWeatherProtocolHandled";

@interface ApolloWeatherProtocol : NSURLProtocol
@end

@implementation ApolloWeatherProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kWeatherHandledKey inRequest:request]) return NO;
    return [request.URL.absoluteString hasPrefix:kWeatherEnabledURL];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    ApolloLog(@"Weather: intercepted is_subreddit_weather_enabled, returning enabled=true");

    NSData *json = [NSJSONSerialization dataWithJSONObject:@{ @"is_enabled": @YES }
                                                   options:0
                                                     error:nil];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
        initWithURL:self.request.URL
         statusCode:200
        HTTPVersion:@"HTTP/1.1"
       headerFields:@{ @"Content-Type": @"application/json" }];

    [self.client URLProtocol:self didReceiveResponse:response
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:json];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// ─── Constructor ──────────────────────────────────────────────────────────────

%ctor {
    // Register the weather intercept protocol for [NSURLSession sharedSession].
    [NSURLProtocol registerClass:[ApolloWeatherProtocol class]];

    // Init the hook group with the mangled Swift class name.
    %init(WeatherFix,
          _TtC6Apollo29SettingsGeneralViewController =
              objc_getClass("_TtC6Apollo29SettingsGeneralViewController"));

    ApolloLog(@"Weather: ApolloWeatherProtocol registered, viewDidLoad hook installed");
}
