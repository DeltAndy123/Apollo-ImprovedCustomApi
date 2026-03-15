#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <os/log.h>

// On iOS 26, NSLog redacts strings, so use os_log: https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26-release-notes#NSLog
// Uses a dedicated subsystem so OSLogStore can efficiently filter our entries.
#define ApolloLog(fmt, ...) do { \
    NSString *logMessage = [NSString stringWithFormat:@"[ApolloFix] " fmt, ##__VA_ARGS__]; \
    os_log_with_type(ApolloFixLog(), OS_LOG_TYPE_DEFAULT, "%{public}s", [logMessage UTF8String]); \
} while(0)

__BEGIN_DECLS
os_log_t ApolloFixLog(void);
NSString *ApolloCollectLogs(void);
BOOL IsLiquidGlass(void);
NSURL *ApolloURLByConvertingResolvedURLToApolloScheme(NSURL *url);
BOOL ApolloRouteResolvedURLViaApolloScheme(NSURL *resolvedURL);
void ApolloFlushReadPostIDsToDefaults(void);

// Saved category icon helpers.
// Icons are stored as a separate JSON dict in the shared NSUserDefaults suite,
// keyed by category name. Values are SF Symbol system names.
NSString *ApolloIconForCategory(NSString *categoryName);
void ApolloSetIconForCategory(NSString *categoryName, NSString *symbolName);
void ApolloRemoveIconForCategory(NSString *categoryName);
void ApolloRenameIconForCategory(NSString *oldName, NSString *newName);
__END_DECLS
