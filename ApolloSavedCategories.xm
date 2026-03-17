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
#include <mach-o/dyld.h>
#import "ApolloCommon.h"


// RDKThing provides fullName (the Reddit "t3_xxx" / "t1_xxx" identifier) on all content objects.
@interface RDKThing : NSObject
- (NSString *)fullName;
@end

// ASCellNode (AsyncDisplayKit/Texture) — exposes the backing UIView.
@interface ASCellNode : NSObject
- (UIView *)view;
@end

// AddCategoryViewController is defined in SavedCategoriesViewController.m.
// Forward-declare enough to instantiate it and set its properties from this file.
@interface AddCategoryViewController : UITableViewController
@property (nonatomic, copy) NSArray<NSString *> *existingCategoryNames;
@property (nonatomic, copy) void (^completionHandler)(NSString *name, NSString *iconName);
- (instancetype)init;
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

    // Notify visible cells to refresh their badges.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ApolloFixSavedCategoryChanged"
                                                            object:nil];
    });
}

// MARK: - "Added new category!" toast
//
// Apollo's toast system (Holla class) is pure Swift with no ObjC-visible entry
// points.  The call chain is:
//
//   sub_100658eb8 (UIAlertController OK handler):
//     ldr  x20, [x8, #0x608]       ; x20 = Holla singleton (*qword_100cfe608)
//     bl   sub_100518214            ; builds capture block, dispatches async
//
//   sub_100518214 entry:
//     mov  x28, x20                 ; captures caller's x20 (Holla) into x28
//     ...stores x28 into the block at offset +0x18...
//
//   block body (sub_100521600) on main queue:
//     r1 = block[0x18]              ; = Holla instance
//     sub_10051847c(r0, r1, ...)    ; actual display
//
// sub_100518214 takes the Holla instance via the CALLER's x20 register (Swift
// context/implicit-self), not as a normal argument.  We therefore need a naked
// trampoline to place Holla in x20 before branching.
//
// String args for "Added new category!" (19 chars, immortal ASCII):
//   word1 = 0xd000000000000013  (discriminant 0xd0, count 19)
//   word2 = (string_content_addr - 0x20) | 0x8000000000000000
//   string content at Hopper address 0x100a73f40

__attribute__((naked)) static void _apolloToastTrampoline(
    void *holla,    // x0  →  x20 (Swift context register)
    void *funcPtr,  // x1  →  branch target
    uint64_t sw1,   // x2  →  x1  (Swift String word 1)
    uint64_t sw2    // x3  →  x2  (Swift String word 2)
) {
    __asm__(
        // Prologue: save frame, lr, and callee-saved x19/x20.
        "stp  fp, lr, [sp, #-32]!\n"      // [sp]   = old fp, [sp+8] = lr
        "stp  x19, x20, [sp, #16]\n"      // [sp+16] = x19,  [sp+24] = old x20
        "mov  fp, sp\n"                    // fp points to our frame base
        // Set Swift context register and save func pointer to a scratch reg.
        "mov  x9,  x1\n"                   // x9 = funcPtr  (x9 is caller-saved)
        "mov  x20, x0\n"                   // x20 = Holla instance
        // Build the real argument registers for sub_100518214.
        "mov  x0, #0\n"                    // arg0 = 0
        "mov  x1, x2\n"                    // arg1 = sw1 (was in x2)
        "mov  x2, x3\n"                    // arg2 = sw2 (was in x3)
        "movz x3, #0x4000, lsl #48\n"      // arg3 = 0x4000000000000000
        "mov  x4, #0\n"
        "mov  x5, #0\n"
        "mov  x6, #0\n"
        "mov  x7, #0\n"
        // Push two zero stack arguments (arg8, arg9 in the original call).
        "stp  xzr, xzr, [sp, #-16]!\n"
        // Branch to sub_100518214 with x20 = Holla.
        "blr  x9\n"
        // sub_100518214 saves/restores x19-x28 internally, so after it returns
        // x20 still holds Holla.  We restore the caller's x20 from our save slot.
        "add  sp, sp, #16\n"               // pop stack args
        "ldp  x19, x20, [fp, #16]\n"       // restore x19, x20
        "ldp  fp, lr, [fp]\n"              // restore fp, lr
        "add  sp, sp, #32\n"               // deallocate frame
        "ret\n"
    );
}

// Show Apollo's category toast via the Holla singleton.
// Pass savedToCategory=YES to show "Saved to new category!" (when the item was
// also auto-assigned), or NO to show "Added new category!" (category created alone).
// Must be called on the main thread.
static void apolloShowCategoryToast(BOOL savedToCategory) {
    // Image 0 is always the main executable (Apollo) when running inside the app.
    uintptr_t slide = _dyld_get_image_vmaddr_slide(0);

    // Ensure the Holla swift_once initializer has run.
    // Predicate: qword_100ca9678, initializer: sub_1005181e8
    uintptr_t *onceToken = (uintptr_t *)(0x100ca9678 + slide);
    if (*onceToken != (uintptr_t)-1) {
        typedef void (*SwiftOnceFn)(uintptr_t *, void (*)(void), void *);
        SwiftOnceFn swift_once_fn = (SwiftOnceFn)dlsym(RTLD_DEFAULT, "swift_once");
        if (swift_once_fn) {
            void (*hollaInit)(void) = (void (*)(void))(0x1005181e8 + slide);
            swift_once_fn(onceToken, hollaInit, NULL);
        }
    }

    // Read the Holla singleton from *qword_100cfe608.
    void *hollaInstance = *(void **)(0x100cfe608 + slide);
    if (!hollaInstance) {
        ApolloLog(@"[SavedCategories] Toast skipped: Holla singleton is nil");
        return;
    }

    // Swift large string layout: word2 = (content_ptr - 0x20) | 0x8000000000000000
    // "Added new category!"  — 19 chars (0x13), Hopper 0x100a73f40
    // "Saved to new category!" — 22 chars (0x16), Hopper 0x100a6bc80
    uintptr_t contentAddr;
    uint64_t sw1;
    if (savedToCategory) {
        contentAddr = 0x100a6bc80 + slide;
        sw1 = 0xd000000000000016ULL;  // discriminant 0xd0, length 22 = 0x16
        ApolloLog(@"[SavedCategories] Showing 'Saved to new category!' toast");
    } else {
        contentAddr = 0x100a73f40 + slide;
        sw1 = 0xd000000000000013ULL;  // discriminant 0xd0, length 19 = 0x13
        ApolloLog(@"[SavedCategories] Showing 'Added new category!' toast");
    }
    uint64_t sw2 = (contentAddr - 0x20) | 0x8000000000000000ULL;

    void *funcPtr = (void *)(0x100518214 + slide);
    _apolloToastTrampoline(hollaInstance, funcPtr, sw1, sw2);
}

// Creates a new category with the given name and optional SF Symbol icon.
// Mirrors the logic in SavedCategoriesViewController.addCategory so both the
// settings screen and the in-app shortcut write to the same database.
static void createSavedCategory(NSString *name, NSString *iconName, BOOL savedToCategory) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kGroupSuiteName];
    NSData *data = [d dataForKey:kSavedItemsDBKey];
    NSError *err = nil;
    NSMutableDictionary *db = data
        ? [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&err] mutableCopy]
        : nil;
    if (!db || err) db = [@{@"categories": [NSMutableDictionary dictionary]} mutableCopy];
    NSMutableDictionary *cats = db[@"categories"];
    if (!cats) { cats = [NSMutableDictionary dictionary]; db[@"categories"] = cats; }
    cats[name] = @[];
    if (iconName) ApolloSetIconForCategory(name, iconName);
    NSData *newData = [NSJSONSerialization dataWithJSONObject:db options:0 error:&err];
    if (newData && !err) { [d setObject:newData forKey:kSavedItemsDBKey]; [d synchronize]; }
    ApolloLog(@"[SavedCategories] Created category: %@ icon: %@", name, iconName ?: @"(none)");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ApolloFixSavedCategoryChanged" object:nil];
        apolloShowCategoryToast(savedToCategory);
    });
}

// MARK: - Toast fullName capture
//
// When "Add Saved Category" is tapped from the toast's long-press context menu,
// Apollo presents the "New Saved Category" alert from a closure that captured a
// weak reference to HollaSavedItemStatusView. That view's savedItemFullName ivar
// holds the Reddit fullName of the item being saved. We read it here so our
// replacement AddCategoryViewController can auto-assign the item to the new
// category — matching Apollo's native "Saved to new category!" behaviour.

static NSString *hollaFullName(id view) {
    Ivar ivar = class_getInstanceVariable(object_getClass(view), "savedItemFullName");
    if (!ivar) return nil;
    uint8_t *base = (uint8_t *)(__bridge void *)view + ivar_getOffset(ivar);
    uint64_t w0, w1;
    memcpy(&w0, base, sizeof(uint64_t));
    memcpy(&w1, base + sizeof(uint64_t), sizeof(uint64_t));
    return decodeSwiftString(w0, w1);
}

static NSString *findHollaFullName(UIView *view, Class hollaClass) {
    if (!view) return nil;
    if ([view isKindOfClass:hollaClass]) {
        NSString *fn = hollaFullName(view);
        if (fn.length > 0) return fn;
    }
    for (UIView *sub in view.subviews) {
        NSString *result = findHollaFullName(sub, hollaClass);
        if (result) return result;
    }
    return nil;
}

// MARK: - Category Picker Sheet
//
// Presented when the user taps "Change Category" in the 3-dot ActionController.
// Uses UISheetPresentationController (iOS 15+) so it slides up as a native
// bottom sheet rather than a UIAlertController popup.

@interface ApolloFixCategoryPickerVC : UITableViewController
@property (nonatomic, copy) NSString *fullName;
@property (nonatomic, copy) NSArray<NSString *> *categories;
@property (nonatomic, copy) NSString *currentCategory;
@end

@implementation ApolloFixCategoryPickerVC

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ApolloFixCatCell"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Change Category" : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Section 0: "No Category" + all categories. Section 1: "Add Category".
    return section == 0 ? 1 + (NSInteger)self.categories.count : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ApolloFixCatCell" forIndexPath:indexPath];
    if (indexPath.section == 1) {
        cell.textLabel.text = @"Add Category";
        cell.imageView.image = [UIImage systemImageNamed:@"plus"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    NSString *title;
    NSString *symbolName = nil;
    BOOL isCurrent;
    if (indexPath.row == 0) {
        title = @"No Category";
        isCurrent = (self.currentCategory == nil);
        symbolName = @"minus.circle";
    } else {
        title = self.categories[indexPath.row - 1];
        isCurrent = [title isEqualToString:self.currentCategory];
        symbolName = ApolloIconForCategory(title);
    }
    cell.textLabel.text = title;
    cell.accessoryType = isCurrent ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.imageView.image = symbolName ? [UIImage systemImageNamed:symbolName] : nil;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        // Present AddCategoryViewController on top of this sheet; refresh list on completion.
        AddCategoryViewController *addVC = [[AddCategoryViewController alloc] init];
        addVC.existingCategoryNames = readSortedCategoryNames();
        __weak ApolloFixCategoryPickerVC *weakSelf = self;
        addVC.completionHandler = ^(NSString *name, NSString *iconName) {
            createSavedCategory(name, iconName, NO);
            dispatch_async(dispatch_get_main_queue(), ^{
                ApolloFixCategoryPickerVC *s = weakSelf;
                if (!s) return;
                s.categories = readSortedCategoryNames();
                [s.tableView reloadData];
            });
        };
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:addVC];
        [self presentViewController:nav animated:YES completion:nil];
        return;
    }
    NSString *cat = (indexPath.row == 0) ? nil : self.categories[indexPath.row - 1];
    changeSavedItemCategory(self.fullName, cat);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

// MARK: - State flags

static BOOL sSortNextActionController = NO;
// Set to YES while SavedPostsCommentsViewController is the visible VC so that
// the post/comment context menu hooks know to inject the Change Category submenu.
static BOOL sSavedViewActive = NO;
// Set to the fullName of the item being long-pressed when we want to inject
// the Change Category submenu into the next UIContextMenuConfiguration creation.
static NSString *sPendingCategoryFullName = nil;
// Set to the fullName when the 3-dot ActionController is about to be presented,
// so we can inject a "Change Category" row into it.
static NSString *sPendingACFullName = nil;

// Associated object keys for ActionController row injection.
static const void *kACFullNameKey      = &kACFullNameKey;      // NSString fullName stored on AC
static const void *kACInjectedRowKey   = &kACInjectedRowKey;   // NSNumber: original row count (injected row index)
// Style cache: copied from the first real IconActionTableViewCell so the injected
// row matches Apollo's theme (custom themes differ from UIColor.label).
static const void *kACStyleFontKey     = &kACStyleFontKey;     // UIFont for actionTitleLabel
static const void *kACStyleColorKey    = &kACStyleColorKey;    // UIColor for actionTitleLabel.textColor
static const void *kACStyleIconTintKey = &kACStyleIconTintKey; // UIColor for iconImageView.tintColor

// MARK: - SavedPostsCommentsViewController hooks

%hook _TtC6Apollo32SavedPostsCommentsViewController

- (void)viewWillAppear:(BOOL)animated {
    sSavedViewActive = YES;
    %orig;
    // During an interactive swipe-back, ASDisplayKit fires didEnterVisibleState on
    // cells BEFORE UIKit calls viewWillAppear:, so sSavedViewActive is still NO at
    // that point and refreshPostBadge returns early without showing badges. The
    // per-cell observers ARE registered by didEnterVisibleState regardless, so
    // posting this notification now (with sSavedViewActive = YES) causes those
    // observers to re-run the badge refresh. On first appearance or regular tap-back
    // there are no observers yet, so this is a harmless no-op.
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"ApolloFixSavedCategoryChanged"
        object:nil];
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

// MARK: - "Add Category" alert intercept
// Apollo presents a "New Saved Category" UIAlertController in two contexts:
//   1. From the saved view's ActionController → "Add Category" row (sub_100658d64).
//   2. From the "Saved!" toast long-press context menu → "Add Saved Category" action
//      (sub_10051d69c), which fires anywhere in the app, not just the saved view.
// Both present via [navigationController presentViewController:...] rather than via
// self, so the SavedPostsCommentsViewController hook above doesn't catch them.
// Hook UIViewController globally without the sSavedViewActive gate so both paths
// get the custom AddCategoryViewController sheet instead of the stock alert.

%hook UIViewController

- (void)presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion {
    // Tag the 3-dot ActionController with the fullName so its UITableView hooks can inject
    // a "Change Category" row. Must be done before %orig so the AC is tagged at presentation time.
    if (sSavedViewActive && sPendingACFullName &&
        [vc isKindOfClass:objc_getClass("_TtC6Apollo16ActionController")]) {
        objc_setAssociatedObject(vc, kACFullNameKey, sPendingACFullName, OBJC_ASSOCIATION_COPY_NONATOMIC);
        sPendingACFullName = nil;
    }

    if ([vc isKindOfClass:[UIAlertController class]] &&
        [[(UIAlertController *)vc title] isEqualToString:@"New Saved Category"]) {
        // Dismiss the ActionController (currently presented on self), then show
        // AddCategoryViewController so the two presentations don't overlap.
        UIViewController *presentedAC = self.presentedViewController;

        // Toast path: no AC is presented — the alert came from the long-press context
        // menu on the "Saved!" toast. Walk the window hierarchy to find the
        // HollaSavedItemStatusView so we can auto-assign after creation, matching
        // Apollo's native "Saved to new category!" behaviour (sub_10051d814).
        NSString *toastFullName = nil;
        if (!presentedAC) {
            Class hollaClass = objc_getClass("_TtC6Apollo24HollaSavedItemStatusView");
            if (hollaClass) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                    for (UIWindow *window in [(UIWindowScene *)scene windows]) {
                        toastFullName = findHollaFullName(window, hollaClass);
                        if (toastFullName) break;
                    }
                    if (toastFullName) break;
                }
            }
            ApolloLog(@"[SavedCategories] toast Add Category fullName: %@", toastFullName ?: @"(not found)");
        }

        __weak UIViewController *weakSelf = self;
        NSString *capturedToastFullName = toastFullName;
        void (^showAddVC)(void) = ^{
            UIViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            AddCategoryViewController *addVC = [[AddCategoryViewController alloc] init];
            addVC.existingCategoryNames = readSortedCategoryNames();
            addVC.completionHandler = ^(NSString *name, NSString *iconName) {
                BOOL assigns = capturedToastFullName.length > 0;
                createSavedCategory(name, iconName, assigns);
                if (assigns) {
                    changeSavedItemCategory(capturedToastFullName, name);
                }
            };
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:addVC];
            [strongSelf presentViewController:nav animated:YES completion:nil];
        };
        if (presentedAC) {
            [presentedAC dismissViewControllerAnimated:YES completion:showAddVC];
        } else {
            showAddVC();
        }
        return;
    }
    %orig;
}

%end

// MARK: - ActionController icon injection + Change Category row injection
// Apollo's native saved-categories ActionController uses IconActionTableViewCell,
// which sets its iconImageView from a fixed per-action-type image. We post-process
// each cell after %orig to replace that image with the user's custom SF Symbol.
// We gate on sSavedViewActive so we only touch the saved categories AC, not others.
//
// For the 3-dot menu ActionController in the saved view, we inject an extra
// "Change Category" row by:
//   1. Adding +1 to numberOfRowsInSection when the AC is tagged with a fullName.
//   2. Returning a custom cell for that last row (without calling %orig, which would
//      attempt an out-of-bounds Swift array access).
//   3. Blocking heightForRowAtIndexPath %orig for the same reason.
//   4. On selection, dismissing the AC and presenting a UIAlertController picker.

%hook _TtC6Apollo16ActionController

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = %orig;
    if (objc_getAssociatedObject(self, kACFullNameKey)) {
        // Register IconActionTableViewCell under our own identifier so we can dequeue
        // a native Apollo-styled cell for the injected row.
        [tableView registerClass:objc_getClass("_TtC6Apollo23IconActionTableViewCell")
          forCellReuseIdentifier:@"ApolloFixChangeCategoryCell"];
        // Store the injected row index (= original count) so cell/height/select hooks
        // can identify it without recalculating.
        objc_setAssociatedObject(self, kACInjectedRowKey, @(count), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return count + 1;
    }
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Intercept the injected row BEFORE %orig to avoid an out-of-bounds Swift array access.
    NSNumber *injectedRow = objc_getAssociatedObject(self, kACInjectedRowKey);
    if (injectedRow && indexPath.row == injectedRow.integerValue) {
        // Dequeue a native IconActionTableViewCell and configure it exactly as Apollo does
        // for icon-backed rows, so it matches the visual style of the other menu items.
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ApolloFixChangeCategoryCell"
                                                                forIndexPath:indexPath];

        Ivar titleIvar = class_getInstanceVariable(object_getClass(cell), "actionTitleLabel");
        if (titleIvar) {
            UILabel *label = object_getIvar(cell, titleIvar);
            label.text = @"Change Category";
            // Apply cached font/color from a real Apollo row so the theme matches.
            UIFont *font = objc_getAssociatedObject(self, kACStyleFontKey);
            UIColor *color = objc_getAssociatedObject(self, kACStyleColorKey);
            if (font) label.font = font;
            if (color) label.textColor = color;
        }

        Ivar iconIvar = class_getInstanceVariable(object_getClass(cell), "iconImageView");
        if (iconIvar) {
            UIImageView *imageView = object_getIvar(cell, iconIvar);
            // Use Apollo's own saved-category asset so the size matches other icons
            // (Apollo stores these as app-bundle images, not SF Symbols).
            imageView.image = [UIImage imageNamed:@"option-saved-category"];
            UIColor *tint = objc_getAssociatedObject(self, kACStyleIconTintKey);
            if (tint) imageView.tintColor = tint;
        }

        Ivar enabledIvar = class_getInstanceVariable(object_getClass(cell), "actionsEnabled");
        if (enabledIvar) {
            *(BOOL *)((uint8_t *)(__bridge void *)cell + ivar_getOffset(enabledIvar)) = YES;
        }
        [cell setUserInteractionEnabled:YES];
        return cell;
    }

    UITableViewCell *cell = %orig;

    // Cache font/color/tintColor from the first real IconActionTableViewCell so the
    // injected row can match the current Apollo theme exactly.
    if (injectedRow && !objc_getAssociatedObject(self, kACStyleFontKey) &&
        [cell isKindOfClass:objc_getClass("_TtC6Apollo23IconActionTableViewCell")]) {
        Ivar lIvar = class_getInstanceVariable(object_getClass(cell), "actionTitleLabel");
        if (lIvar) {
            UILabel *lbl = object_getIvar(cell, lIvar);
            if (lbl.font)      objc_setAssociatedObject(self, kACStyleFontKey,  lbl.font,      OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (lbl.textColor) objc_setAssociatedObject(self, kACStyleColorKey, lbl.textColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        Ivar ivIvar = class_getInstanceVariable(object_getClass(cell), "iconImageView");
        if (ivIvar) {
            UIImageView *iv = object_getIvar(cell, ivIvar);
            UIColor *tc = iv.tintColor;
            if (tc) objc_setAssociatedObject(self, kACStyleIconTintKey, tc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    if (!sSavedViewActive) return cell;

    // Only category rows use IconActionTableViewCell.
    if (![cell isKindOfClass:objc_getClass("_TtC6Apollo23IconActionTableViewCell")]) return cell;

    // Read the title to look up a custom icon.
    Ivar titleIvar = class_getInstanceVariable(object_getClass(cell), "actionTitleLabel");
    if (!titleIvar) return cell;
    UILabel *titleLabel = object_getIvar(cell, titleIvar);
    NSString *title = titleLabel.text;
    if (!title.length) return cell;

    NSString *iconName = ApolloIconForCategory(title);
    if (!iconName) return cell;
    UIImage *icon = [UIImage systemImageNamed:iconName];
    if (!icon) return cell;

    // Replace the iconImageView's image with the custom SF Symbol.
    Ivar imageViewIvar = class_getInstanceVariable(object_getClass(cell), "iconImageView");
    if (!imageViewIvar) return cell;
    UIImageView *imageView = object_getIvar(cell, imageViewIvar);
    [imageView setImage:icon];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Block %orig for the injected row — it would attempt an out-of-bounds Swift array access.
    // Instead, delegate to row 0 so the height matches real rows exactly.
    NSNumber *injectedRow = objc_getAssociatedObject(self, kACInjectedRowKey);
    if (injectedRow && indexPath.row == injectedRow.integerValue) {
        NSIndexPath *refPath = [NSIndexPath indexPathForRow:0 inSection:0];
        return %orig(tableView, refPath);
    }
    return %orig;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSNumber *injectedRow = objc_getAssociatedObject(self, kACInjectedRowKey);
    if (injectedRow && indexPath.row == injectedRow.integerValue) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        NSString *fullName = objc_getAssociatedObject(self, kACFullNameKey);
        if (!fullName.length) return;

        NSArray<NSString *> *categories = readSortedCategoryNames();
        NSString *currentCat = currentCategoryForFullName(fullName);
        UIViewController *selfVC = (UIViewController *)self;
        UIViewController *presentingVC = selfVC.presentingViewController;
        [selfVC dismissViewControllerAnimated:YES completion:^{
            if (!presentingVC) return;

            ApolloFixCategoryPickerVC *picker = [[ApolloFixCategoryPickerVC alloc]
                initWithStyle:UITableViewStyleInsetGrouped];
            picker.fullName = fullName;
            picker.categories = categories;
            picker.currentCategory = currentCat;
            picker.modalPresentationStyle = UIModalPresentationPageSheet;
            if (@available(iOS 15.0, *)) {
                UISheetPresentationController *sheet = picker.sheetPresentationController;
                sheet.detents = @[
                    [UISheetPresentationControllerDetent mediumDetent],
                    [UISheetPresentationControllerDetent largeDetent],
                ];
                sheet.prefersGrabberVisible = YES;
                sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
            }
            [presentingVC presentViewController:picker animated:YES completion:nil];
        }];
        return;
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
        // Also inject per-category custom SF Symbol icons where set.
        if (doSort) {
            if (children.count >= 3) {
                NSMutableArray<UIMenuElement *> *sortable = [[children subarrayWithRange:NSMakeRange(0, children.count - 1)] mutableCopy];
                [sortable sortUsingComparator:^NSComparisonResult(UIMenuElement *a, UIMenuElement *b) {
                    return [a.title localizedCaseInsensitiveCompare:b.title];
                }];

                // Rebuild UIActions with custom icons where a category has one stored.
                // UIAction.handler is public (iOS 14+) so we can copy it into a new action.
                for (NSUInteger i = 0; i < sortable.count; i++) {
                    UIMenuElement *elem = sortable[i];
                    if (![elem isKindOfClass:[UIAction class]]) continue;
                    UIAction *action = (UIAction *)elem;
                    NSString *iconName = ApolloIconForCategory(action.title);
                    if (!iconName) continue;
                    UIImage *icon = [UIImage systemImageNamed:iconName];
                    if (!icon) continue;
                    // UIAction.handler is not in older SDK headers; access via KVC.
                    typedef void (^UIActionHandlerBlock)(__kindof UIAction *);
                    UIActionHandlerBlock handler = [action valueForKey:@"handler"];
                    if (!handler) continue;
                    UIAction *replacement = [UIAction
                        actionWithTitle:action.title
                        image:icon
                        identifier:action.identifier
                        handler:handler];
                    replacement.state = action.state;
                    replacement.attributes = action.attributes;
                    sortable[i] = replacement;
                }

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
                    NSString *iconName = ApolloIconForCategory(cat);
                    UIImage *catIcon = iconName
                        ? [UIImage systemImageNamed:iconName]
                        : nil;
                    UIAction *catAction = [UIAction
                        actionWithTitle:cat
                        image:catIcon
                        identifier:nil
                        handler:^(__kindof UIAction *a) {
                            changeSavedItemCategory(changeCategoryFullName, capturedCat);
                        }];
                    catAction.state = ([cat isEqualToString:currentCat]) ? UIMenuElementStateOn : UIMenuElementStateOff;
                    [catActions addObject:catAction];
                }

                // "Add Category" — creates a new category and assigns the item to it.
                NSString *capturedFullNameForAdd = changeCategoryFullName;
                UIAction *addCatAction = [UIAction
                    actionWithTitle:@"Add Category"
                    image:[UIImage systemImageNamed:@"plus"]
                    identifier:nil
                    handler:^(__kindof UIAction *a) {
                        UIWindow *keyWindow = nil;
                        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                            if ([scene isKindOfClass:[UIWindowScene class]]) {
                                keyWindow = [(UIWindowScene *)scene keyWindow];
                                if (keyWindow) break;
                            }
                        }
                        UIViewController *topVC = keyWindow.rootViewController;
                        while (topVC.presentedViewController) topVC = topVC.presentedViewController;
                        if (!topVC) return;
                        AddCategoryViewController *addVC = [[AddCategoryViewController alloc] init];
                        addVC.existingCategoryNames = readSortedCategoryNames();
                        addVC.completionHandler = ^(NSString *name, NSString *iconName) {
                            createSavedCategory(name, iconName, YES);
                            // Assign the item to the newly created category, matching
                            // Apollo's original "New Saved Category" alert handler behavior.
                            changeSavedItemCategory(capturedFullNameForAdd, name);
                        };
                        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:addVC];
                        [topVC presentViewController:nav animated:YES completion:nil];
                    }];
                [catActions addObject:addCatAction];

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

// MARK: - Category Badge
// Shows a small pill at the bottom-right of each saved post/comment cell in the Saved view,
// offset left to avoid covering Apollo's green saved indicator.
//
// Uses didEnterVisibleState (fires on initial display AND on scroll) instead of
// cellNodeVisibilityEvent: (which only fires on scroll). Each visible cell also observes
// ApolloFixSavedCategoryChanged so it refreshes instantly when the user changes a category.

static const void *kCategoryBadgeKey    = &kCategoryBadgeKey;    // UIVisualEffectView on cellView
static const void *kCategoryObserverKey = &kCategoryObserverKey; // NSObject observer token on node

static UIView *categoryBadgeViewForNode(UIView *cellView, CGFloat indicatorWidth) {
    UIView *badge = objc_getAssociatedObject(cellView, kCategoryBadgeKey);
    if (badge) return badge;

    UIVisualEffectView *blurView = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blurView.layer.cornerRadius = 10;
    blurView.layer.masksToBounds = YES;
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.alpha = 0;

    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = [UIColor whiteColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.tag = 101;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    label.textColor = [UIColor whiteColor];
    label.tag = 102;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, label]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 3;
    stack.alignment = UIStackViewAlignmentCenter;

    UIView *content = blurView.contentView;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:6],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-6],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:3],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-3],
        [iconView.widthAnchor constraintEqualToConstant:12],
        [iconView.heightAnchor constraintEqualToConstant:12],
    ]];

    [cellView addSubview:blurView];
    // Bottom-right, shifted left by indicatorWidth to clear the green saved indicator.
    [NSLayoutConstraint activateConstraints:@[
        [blurView.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-(indicatorWidth + 6)],
        [blurView.bottomAnchor constraintEqualToAnchor:cellView.bottomAnchor constant:-4],
    ]];

    objc_setAssociatedObject(cellView, kCategoryBadgeKey, blurView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return blurView;
}

static void showCategoryBadge(UIView *cellView, NSString *categoryName, CGFloat indicatorWidth) {
    if (!cellView) return;
    UIVisualEffectView *badge = (UIVisualEffectView *)categoryBadgeViewForNode(cellView, indicatorWidth);

    UILabel *label = (UILabel *)[badge.contentView viewWithTag:102];
    UIImageView *iconView = (UIImageView *)[badge.contentView viewWithTag:101];

    label.text = categoryName;

    NSString *iconName = ApolloIconForCategory(categoryName);
    UIImage *icon = iconName
        ? [UIImage systemImageNamed:iconName
                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10
                                                                                    weight:UIImageSymbolWeightSemibold]]
        : nil;
    iconView.image = icon;
    iconView.hidden = (icon == nil);

    badge.alpha = 0.9;
}

static void hideCategoryBadge(UIView *cellView) {
    if (!cellView) return;
    UIView *badge = objc_getAssociatedObject(cellView, kCategoryBadgeKey);
    if (badge) badge.alpha = 0;
}

static BOOL isCategoryBadgeEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowSavedCategoryBadge"];
}

// Refresh badge for a post node (link ivar).
static void refreshPostBadge(id node, CGFloat indicatorWidth) {
    if (!sSavedViewActive || !isCategoryBadgeEnabled()) return;
    UIView *cellView = [(ASCellNode *)(id)node view];
    Ivar linkIvar = class_getInstanceVariable(object_getClass(node), "link");
    if (!linkIvar) { hideCategoryBadge(cellView); return; }
    RDKThing *link = object_getIvar(node, linkIvar);
    NSString *fullName = [link fullName];
    if (!fullName.length) { hideCategoryBadge(cellView); return; }
    NSString *cat = currentCategoryForFullName(fullName);
    if (cat) showCategoryBadge(cellView, cat, indicatorWidth);
    else hideCategoryBadge(cellView);
}

// Refresh badge for a comment node (comment ivar).
static void refreshCommentBadge(id node) {
    if (!sSavedViewActive || !isCategoryBadgeEnabled()) return;
    UIView *cellView = [(ASCellNode *)(id)node view];
    Ivar commentIvar = class_getInstanceVariable(object_getClass(node), "comment");
    if (!commentIvar) { hideCategoryBadge(cellView); return; }
    RDKThing *comment = object_getIvar(node, commentIvar);
    NSString *fullName = [comment fullName];
    if (!fullName.length) { hideCategoryBadge(cellView); return; }
    NSString *cat = currentCategoryForFullName(fullName);
    if (cat) showCategoryBadge(cellView, cat, 18);
    else hideCategoryBadge(cellView);
}

// Register a notification observer that re-runs refreshBlock when a category changes.
// Stored on the node; removed in unregisterCategoryObserver (called from didExitVisibleState).
static void registerCategoryObserver(id node, void (^refreshBlock)(void)) {
    if (objc_getAssociatedObject(node, kCategoryObserverKey)) return;
    id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName:@"ApolloFixSavedCategoryChanged"
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *n) { refreshBlock(); }];
    objc_setAssociatedObject(node, kCategoryObserverKey, obs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void unregisterCategoryObserver(id node) {
    id obs = objc_getAssociatedObject(node, kCategoryObserverKey);
    if (!obs) return;
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    objc_setAssociatedObject(node, kCategoryObserverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// MARK: - LargePostCellNode badge + 3-dot menu

%hook _TtC6Apollo17LargePostCellNode

- (void)didEnterVisibleState {
    %orig;
    __weak id weakSelf = self;
    refreshPostBadge(self, 24);
    registerCategoryObserver(self, ^{ refreshPostBadge(weakSelf, 24); });
}

- (void)didExitVisibleState {
    %orig;
    hideCategoryBadge([(ASCellNode *)(id)self view]);
    unregisterCategoryObserver(self);
}

// Capture the post's fullName before the 3-dot ActionController is presented.
- (void)moreOptionsButtonTappedWithSender:(id)sender {
    if (sSavedViewActive) {
        Ivar linkIvar = class_getInstanceVariable(object_getClass(self), "link");
        if (linkIvar) {
            RDKThing *link = object_getIvar(self, linkIvar);
            NSString *fn = [link fullName];
            if (fn.length > 0) sPendingACFullName = fn;
        }
    }
    %orig;
    sPendingACFullName = nil;
}

%end

// MARK: - CompactPostCellNode badge + 3-dot menu

%hook _TtC6Apollo19CompactPostCellNode

- (void)didEnterVisibleState {
    %orig;
    __weak id weakSelf = self;
    refreshPostBadge(self, 24);
    registerCategoryObserver(self, ^{ refreshPostBadge(weakSelf, 24); });
}

- (void)didExitVisibleState {
    %orig;
    hideCategoryBadge([(ASCellNode *)(id)self view]);
    unregisterCategoryObserver(self);
}

// Capture the post's fullName before the 3-dot ActionController is presented.
- (void)moreOptionsButtonTappedWithSender:(id)sender {
    if (sSavedViewActive) {
        Ivar linkIvar = class_getInstanceVariable(object_getClass(self), "link");
        if (linkIvar) {
            RDKThing *link = object_getIvar(self, linkIvar);
            NSString *fn = [link fullName];
            if (fn.length > 0) sPendingACFullName = fn;
        }
    }
    %orig;
    sPendingACFullName = nil;
}

%end

// MARK: - CommentCellNode badge + 3-dot menu

%hook _TtC6Apollo15CommentCellNode

- (void)didEnterVisibleState {
    %orig;
    __weak id weakSelf = self;
    refreshCommentBadge(self);
    registerCategoryObserver(self, ^{ refreshCommentBadge(weakSelf); });
}

- (void)didExitVisibleState {
    %orig;
    hideCategoryBadge([(ASCellNode *)(id)self view]);
    unregisterCategoryObserver(self);
}

// Capture the comment's fullName before the 3-dot ActionController is presented.
- (void)moreOptionsTappedWithSender:(id)sender {
    if (sSavedViewActive) {
        Ivar commentIvar = class_getInstanceVariable(object_getClass(self), "comment");
        if (commentIvar) {
            RDKThing *comment = object_getIvar(self, commentIvar);
            NSString *fn = [comment fullName];
            if (fn.length > 0) sPendingACFullName = fn;
        }
    }
    %orig;
    sPendingACFullName = nil;
}

%end
