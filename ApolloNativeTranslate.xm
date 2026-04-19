#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

#import "ApolloCommon.h"

@interface NativeTranslationPresenter : NSObject
+ (BOOL)canPresentNativeTranslation;
+ (void)presentFromViewController:(UIViewController *)viewController text:(NSString *)text sourceView:(UIView *)sourceView;
@end

static NSString *ApolloNativeTranslateExtractTextFromURL(NSURL *url) {
    if (![url isKindOfClass:[NSURL class]]) {
        return nil;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"text"] && item.value.length > 0) {
            return item.value;
        }
    }
    return nil;
}

static NSString *ApolloNativeTranslateTextForController(UIViewController *controller) {
    if (!controller) {
        return nil;
    }

    Ivar webViewIvar = class_getInstanceVariable([controller class], "webView");
    id webView = webViewIvar ? object_getIvar(controller, webViewIvar) : nil;
    if (![webView isKindOfClass:[WKWebView class]]) {
        ApolloLog(@"NativeTranslate: TranslatorViewController.webView missing or unexpected class: %@", webView);
        return nil;
    }

    WKWebView *wkWebView = (WKWebView *)webView;
    NSString *text = ApolloNativeTranslateExtractTextFromURL(wkWebView.URL);
    if (text.length > 0) {
        return text;
    }

    NSURL *initialURL = wkWebView.backForwardList.currentItem.initialURL;
    text = ApolloNativeTranslateExtractTextFromURL(initialURL);
    if (text.length > 0) {
        return text;
    }

    ApolloLog(@"NativeTranslate: could not decode text from WKWebView URL %@", wkWebView.URL);
    return nil;
}

%group NativeTranslate

%hook UIViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)animated completion:(void (^)(void))completion {
    if ([NativeTranslationPresenter canPresentNativeTranslation]
        && [viewControllerToPresent isKindOfClass:objc_getClass("_TtC6Apollo24TranslatorViewController")]) {
        // Force Apollo's translator to construct its internal WKWebView and request
        // off-screen so we can decode the original text before Apollo starts its custom modal.
        [viewControllerToPresent view];
        NSString *textToTranslate = ApolloNativeTranslateTextForController(viewControllerToPresent);
        if (textToTranslate.length > 0) {
            ApolloLog(@"NativeTranslate: bypassing TranslatorViewController presentation");
            [NativeTranslationPresenter presentFromViewController:(UIViewController *)self text:textToTranslate sourceView:nil];
            if (completion) {
                completion();
            }
            return;
        }
    }

    %orig;
}

%end

%end

%ctor {
    %init(NativeTranslate);
    ApolloLog(@"NativeTranslate: presentation hook installed");
}
