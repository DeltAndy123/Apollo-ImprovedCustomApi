// MARK: - Saved Categories Sort Fix
// This fixes a long-standing Apollo bug where saved categories appear in random order in various menus.
//
// Apollo iterates a Swift Dictionary to build the categories action sheet / context menu.
// Swift Dictionary iteration order is non-deterministic (hash-based), so categories
// appear in random order on each invocation. Two UI flows are affected:
//
// 1. ActionController (SavedPostsCommentsView) — bookmark button or title label tap
//    Fix: sort the actions array in-place after Apollo builds the controller.
//
// 2. UIContextMenu (SetSavedCategoryButton on the "Saved!" toast)
//    Fix: wrap the actionProvider block to sort UIMenu children before display.
//
// MARK: - Change Category Context Menu
// Adds a "Change Category" submenu to the long-press context menu for posts and comments
// when the user is in the Saved posts/comments view. Selecting a category moves the item
// to that category in the local NSUserDefaults database (same store Apollo reads from).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#import "ApolloCommon.h"


// RDKThing provides fullName (the Reddit "t3_xxx" / "t1_xxx" identifier) on all content objects.
@interface RDKThing : NSObject
- (NSString *)fullName;
@end

// MARK: - ActionController In-Place Sort

// Decode a Swift String stored as two raw 64-bit words into an NSString.
// Handles both small strings (≤15 bytes, inline) and large strings (native
// storage, shared, bridged NSString, etc.) by falling back to the Swift
// runtime's _bridgeToObjectiveC when the inline decode doesn't apply.
static NSString *decodeSwiftString(uint64_t w0, uint64_t w1) {
    // Small string: discriminator 0xE0-0xEF in MSB of w1 encodes length
    uint8_t disc = (uint8_t)(w1 >> 56);
    if (disc >= 0xE0 && disc <= 0xEF) {
        NSUInteger len = disc - 0xE0;
        if (len == 0) return @"";
        char buf[16] = {0};
        memcpy(buf, &w0, 8);
        uint64_t w1clean = w1 & 0x00FFFFFFFFFFFFFFULL;
        memcpy(buf + 8, &w1clean, 7);
        return [[NSString alloc] initWithBytes:buf length:len encoding:NSUTF8StringEncoding];
    }

    // Large string: call Swift.String._bridgeToObjectiveC() -> NSString
    // Symbol: $sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF
    // Takes String value in (x0=_countAndFlagsBits, x1=_object), returns +1 NSString.
    typedef NSString *(*BridgeFn)(uint64_t, uint64_t);
    static BridgeFn sBridge = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sBridge = (BridgeFn)dlsym(RTLD_DEFAULT,
            "$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF");
    });
    if (sBridge) {
        return sBridge(w0, w1);
    }
    return nil;
}

// Sort the category entries in an ActionController's actions array in-place.
// Keeps "All" (index 0) fixed; sorts only the category entries after it.
//
// ActionController.actions is a Swift Array of 0x30-byte value-type structs:
//   buffer+0x10 = count, elements at buffer+0x20, stride 0x30
//   Each element: +0x08 = title word0, +0x10 = title word1
//   (Verified from assembly: madd x8, idx, #0x30, buf; str [x8, #0x20..#0x48])
//
// ActionController.actionHandlers is a Swift Dictionary (NOT a parallel array)
// keyed by description string — handler lookup is by key, not position, so
// only the actions array needs to be reordered.
static void sortActionControllerCategories(id actionController) {
    Class cls = object_getClass(actionController);
    Ivar actionsIvar = class_getInstanceVariable(cls, "actions");
    if (!actionsIvar) return;

    uint8_t *acBase = (uint8_t *)(__bridge void *)actionController;
    void *actBuf = *(void **)(acBase + ivar_getOffset(actionsIvar));
    if (!actBuf) return;

    int64_t count = *(int64_t *)((uint8_t *)actBuf + 0x10);
    if (count < 3) return; // Need "All" + ≥2 categories

    // Sort range: indices 1..count-1 (skip "All" at index 0)
    int64_t lo = 1, hi = count - 1;

    // Insertion sort (category count is small, elements are pure value types)
    uint8_t tmpAct[0x30];
    for (int64_t i = lo + 1; i <= hi; i++) {
        uint8_t *elemI = (uint8_t *)actBuf + 0x20 + i * 0x30;
        NSString *titleI = decodeSwiftString(*(uint64_t *)(elemI + 0x08), *(uint64_t *)(elemI + 0x10));
        if (!titleI) continue;

        int64_t j = i - 1;
        while (j >= lo) {
            uint8_t *elemJ = (uint8_t *)actBuf + 0x20 + j * 0x30;
            NSString *titleJ = decodeSwiftString(*(uint64_t *)(elemJ + 0x08), *(uint64_t *)(elemJ + 0x10));
            if (!titleJ || [titleJ localizedCaseInsensitiveCompare:titleI] <= 0) break;
            j--;
        }
        if (j + 1 == i) continue; // already in place

        // Save element[i], shift [j+1..i-1] right, insert at j+1
        int64_t ins = j + 1;
        memcpy(tmpAct, elemI, 0x30);

        memmove((uint8_t *)actBuf + 0x20 + (ins + 1) * 0x30,
                (uint8_t *)actBuf + 0x20 + ins * 0x30,
                (i - ins) * 0x30);

        memcpy((uint8_t *)actBuf + 0x20 + ins * 0x30, tmpAct, 0x30);
    }
}

// MARK: - Saved Categories Database Helpers (for Change Category feature)

static NSString *const kGroupSuiteName = @"group.com.christianselig.apollo";
static NSString *const kSavedItemsDBKey = @"SavedItemsCategoriesDatabase";

// Returns sorted category names from the shared NSUserDefaults database.
static NSArray<NSString *> *readSortedCategoryNames(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kGroupSuiteName];
    NSData *data = [d dataForKey:kSavedItemsDBKey];
    if (!data) return @[];
    NSError *err = nil;
    NSDictionary *db = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![db[@"categories"] isKindOfClass:[NSDictionary class]]) return @[];
    return [[db[@"categories"] allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

// Returns the category name that currently contains fullName, or nil if uncategorised.
static NSString *currentCategoryForFullName(NSString *fullName) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kGroupSuiteName];
    NSData *data = [d dataForKey:kSavedItemsDBKey];
    if (!data) return nil;
    NSError *err = nil;
    NSDictionary *db = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err) return nil;
    NSDictionary *cats = db[@"categories"];
    for (NSString *cat in cats) {
        if ([cats[cat] containsObject:fullName]) return cat;
    }
    return nil;
}

// Moves fullName out of any current category and into newCategory (nil = uncategorised).
static void changeSavedItemCategory(NSString *fullName, NSString *newCategory) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kGroupSuiteName];
    NSData *data = [d dataForKey:kSavedItemsDBKey];
    if (!data) return;
    NSError *err = nil;
    NSMutableDictionary *db = [[NSJSONSerialization JSONObjectWithData:data
                                                               options:NSJSONReadingMutableContainers
                                                                 error:&err] mutableCopy];
    if (err || !db) return;

    NSMutableDictionary *cats = db[@"categories"];
    if (!cats) return;

    // Remove from all categories first.
    for (NSString *cat in cats.allKeys) {
        id rawItems = cats[cat];
        NSMutableArray *items = [rawItems isKindOfClass:[NSMutableArray class]]
            ? rawItems : [rawItems mutableCopy];
        cats[cat] = items;
        [items removeObject:fullName];
    }

    // Add to the chosen category.
    if (newCategory && cats[newCategory]) {
        NSMutableArray *items = cats[newCategory];
        if (![items containsObject:fullName]) {
            [items addObject:fullName];
        }
    }

    NSData *newData = [NSJSONSerialization dataWithJSONObject:db options:0 error:&err];
    if (!newData || err) return;
    [d setObject:newData forKey:kSavedItemsDBKey];
    [d synchronize];

    ApolloLog(@"[SavedCategories] Moved %@ to category: %@", fullName, newCategory ?: @"(none)");
}

// MARK: - State flags

static BOOL sSortNextActionController = NO;
// Set to YES while SavedPostsCommentsViewController is the visible VC so that
// the post/comment context menu hooks know to inject the Change Category submenu.
static BOOL sSavedViewActive = NO;
// Set to the fullName of the item being long-pressed when we want to inject
// the Change Category submenu into the next UIContextMenuConfiguration creation.
static NSString *sPendingCategoryFullName = nil;

// MARK: - SavedPostsCommentsViewController hooks

%hook _TtC6Apollo32SavedPostsCommentsViewController

- (void)viewWillAppear:(BOOL)animated {
    sSavedViewActive = YES;
    %orig;
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    sSavedViewActive = NO;
}

- (void)savedCategoriesButtonTappedWithSender:(id)sender {
    sSortNextActionController = YES;
    %orig;
    sSortNextActionController = NO;
}

- (void)titleViewTappedWithSender:(id)sender {
    sSortNextActionController = YES;
    %orig;
    sSortNextActionController = NO;
}

- (void)presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion {
    if (sSortNextActionController && [vc isKindOfClass:objc_getClass("_TtC6Apollo16ActionController")]) {
        sSortNextActionController = NO;
        sortActionControllerCategories(vc);
    }
    %orig;
}

%end

// MARK: - Post context menu: inject Change Category

%hook _TtC6Apollo19PostCellActionTaker

- (UIContextMenuConfiguration *)contextMenuInteraction:(id)interaction configurationForMenuAtLocation:(CGPoint)location {
    if (sSavedViewActive) {
        Ivar linkIvar = class_getInstanceVariable(object_getClass(self), "link");
        if (linkIvar) {
            RDKThing *link = (__bridge RDKThing *)(__bridge void *)object_getIvar(self, linkIvar);
            NSString *fullName = [link fullName];
            if (fullName.length > 0) {
                sPendingCategoryFullName = fullName;
            }
        }
    }
    UIContextMenuConfiguration *config = %orig;
    sPendingCategoryFullName = nil;
    return config;
}

%end

// MARK: - Comment context menu: inject Change Category

%hook _TtC6Apollo24CommentSectionController

- (UIContextMenuConfiguration *)contextMenuInteraction:(id)interaction configurationForMenuAtLocation:(CGPoint)location {
    if (sSavedViewActive) {
        Ivar commentIvar = class_getInstanceVariable(object_getClass(self), "comment");
        if (commentIvar) {
            RDKThing *comment = (__bridge RDKThing *)(__bridge void *)object_getIvar(self, commentIvar);
            NSString *fullName = [comment fullName];
            if (fullName.length > 0) {
                sPendingCategoryFullName = fullName;
            }
        }
    }
    UIContextMenuConfiguration *config = %orig;
    sPendingCategoryFullName = nil;
    return config;
}

%end

// MARK: - Set Saved Category Context Menu Sort Fix
// The "Set Category" button on the saved-post toast uses a UIContextMenu built
// from the same non-deterministic Swift Dictionary iteration. Fix: intercept the
// UIContextMenuConfiguration creation, wrap its actionProvider block with one
// that sorts the resulting UIMenu children alphabetically before display.

static BOOL sSortNextContextMenu = NO;

%hook _TtC6Apollo22SetSavedCategoryButton

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    sSortNextContextMenu = YES;
    UIContextMenuConfiguration *config = %orig;
    sSortNextContextMenu = NO;
    return config;
}

%end

%hook UIContextMenuConfiguration

+ (instancetype)configurationWithIdentifier:(id)identifier previewProvider:(id)previewProvider actionProvider:(UIMenu *(^)(NSArray<UIMenuElement *> *))actionProvider {
    BOOL doSort = sSortNextContextMenu && actionProvider != nil;
    NSString *changeCategoryFullName = (sPendingCategoryFullName && actionProvider != nil)
        ? [sPendingCategoryFullName copy] : nil;

    // Consume flags immediately so nested calls don't double-apply.
    if (doSort) sSortNextContextMenu = NO;
    if (changeCategoryFullName) sPendingCategoryFullName = nil;

    if (!doSort && !changeCategoryFullName) return %orig;

    UIMenu *(^originalProvider)(NSArray<UIMenuElement *> *) = [actionProvider copy];
    UIMenu *(^wrappedProvider)(NSArray<UIMenuElement *> *) = ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIMenu *menu = originalProvider(suggestedActions);
        if (!menu) return menu;

        NSArray<UIMenuElement *> *children = menu.children;

        // Sort fix: alphabetise category children, keeping the last "Add" item fixed.
        if (doSort) {
            if (children.count >= 3) {
                NSMutableArray<UIMenuElement *> *sortable = [[children subarrayWithRange:NSMakeRange(0, children.count - 1)] mutableCopy];
                [sortable sortUsingComparator:^NSComparisonResult(UIMenuElement *a, UIMenuElement *b) {
                    return [a.title localizedCaseInsensitiveCompare:b.title];
                }];
                [sortable addObject:children.lastObject];
                children = sortable;
                menu = [UIMenu menuWithTitle:menu.title image:menu.image identifier:menu.identifier options:menu.options children:children];
            }
        }

        // Change Category fix: append a "Change Category" submenu.
        if (changeCategoryFullName) {
            NSArray<NSString *> *categories = readSortedCategoryNames();
            if (categories.count > 0) {
                NSString *currentCat = currentCategoryForFullName(changeCategoryFullName);
                NSMutableArray<UIAction *> *catActions = [NSMutableArray array];

                // "No Category" — removes the item from all categories.
                UIAction *noCatAction = [UIAction
                    actionWithTitle:@"No Category"
                    image:[UIImage systemImageNamed:@"minus.circle"]
                    identifier:nil
                    handler:^(__kindof UIAction *a) {
                        changeSavedItemCategory(changeCategoryFullName, nil);
                    }];
                noCatAction.state = (currentCat == nil) ? UIMenuElementStateOn : UIMenuElementStateOff;
                [catActions addObject:noCatAction];

                // One action per category; checkmark the current one.
                for (NSString *cat in categories) {
                    NSString *capturedCat = cat;
                    UIAction *catAction = [UIAction
                        actionWithTitle:cat
                        image:nil
                        identifier:nil
                        handler:^(__kindof UIAction *a) {
                            changeSavedItemCategory(changeCategoryFullName, capturedCat);
                        }];
                    catAction.state = ([cat isEqualToString:currentCat]) ? UIMenuElementStateOn : UIMenuElementStateOff;
                    [catActions addObject:catAction];
                }

                UIMenu *changeCatMenu = [UIMenu
                    menuWithTitle:@"Change Category"
                    image:[UIImage systemImageNamed:@"folder"]
                    identifier:nil
                    options:0
                    children:catActions];

                NSMutableArray<UIMenuElement *> *newChildren = [children mutableCopy];
                [newChildren addObject:changeCatMenu];
                menu = [UIMenu menuWithTitle:menu.title image:menu.image identifier:menu.identifier options:menu.options children:newChildren];
            }
        }

        return menu;
    };
    return %orig(identifier, previewProvider, wrappedProvider);
}

%end
