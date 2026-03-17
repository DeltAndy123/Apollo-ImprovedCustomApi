#import "SavedCategoriesViewController.h"
#import "ApolloCommon.h"

static NSString *const kGroupSuiteName = @"group.com.christianselig.apollo";

// MARK: - SF Symbol Picker

static NSArray<NSString *> *AllCategorySymbols(void) {
    return @[
        // Numbers & Letters
        @"0.circle.fill", @"1.circle.fill", @"2.circle.fill", @"3.circle.fill",
        @"4.circle.fill", @"5.circle.fill", @"6.circle.fill", @"7.circle.fill",
        @"8.circle.fill", @"9.circle.fill",
        @"a.circle.fill", @"b.circle.fill", @"c.circle.fill", @"d.circle.fill",
        @"e.circle.fill", @"f.circle.fill", @"g.circle.fill", @"h.circle.fill",
        @"i.circle.fill", @"j.circle.fill", @"k.circle.fill", @"l.circle.fill",
        @"m.circle.fill", @"n.circle.fill", @"o.circle.fill", @"p.circle.fill",
        @"q.circle.fill", @"r.circle.fill", @"s.circle.fill", @"t.circle.fill",
        @"u.circle.fill", @"v.circle.fill", @"w.circle.fill", @"x.circle.fill",
        @"y.circle.fill", @"z.circle.fill",
        // Organisation & Filing
        @"folder.fill", @"folder.badge.plus", @"folder.badge.minus",
        @"folder.badge.questionmark", @"folder.circle.fill",
        @"tray.fill", @"tray.2.fill", @"tray.full.fill",
        @"tray.and.arrow.down.fill", @"tray.and.arrow.up.fill",
        @"archivebox.fill", @"archivebox.circle.fill",
        @"xmark.bin.fill", @"externaldrive.fill",
        @"list.bullet", @"list.bullet.circle.fill", @"list.dash",
        @"list.number", @"list.star", @"list.clipboard.fill",
        @"checklist", @"checklist.checked", @"checklist.unchecked",
        @"square.grid.2x2.fill", @"square.grid.3x3.fill",
        @"rectangle.grid.2x2.fill",
        // Bookmarks, Tags & Pins
        @"bookmark.fill", @"bookmark.circle.fill", @"bookmark.slash.fill",
        @"tag.fill", @"tag.circle.fill", @"tag.slash.fill",
        @"pin.fill", @"pin.circle.fill", @"pin.slash.fill",
        @"flag.fill", @"flag.circle.fill", @"flag.slash.fill",
        @"flag.checkered", @"flag.2.crossed.fill",
        // Stars, Hearts & Ratings
        @"star.fill", @"star.circle.fill", @"star.slash.fill",
        @"star.leadinghalf.filled", @"star.square.fill",
        @"heart.fill", @"heart.circle.fill", @"heart.slash.fill",
        @"heart.rectangle.fill", @"heart.square.fill",
        @"suit.heart.fill", @"suit.diamond.fill",
        @"suit.club.fill", @"suit.spade.fill",
        @"hand.thumbsup.fill", @"hand.thumbsdown.fill",
        @"hands.clap.fill",
        // Fire, Lightning & Energy
        @"flame.fill", @"flame.circle.fill",
        @"bolt.fill", @"bolt.circle.fill", @"bolt.shield.fill",
        @"sparkles", @"sparkle", @"wand.and.sparkles",
        @"wand.and.stars", @"wand.and.rays",
        @"sun.max.fill", @"sun.min.fill", @"sunrise.fill", @"sunset.fill",
        @"sun.and.horizon.fill", @"moon.fill", @"moon.circle.fill",
        @"moon.stars.fill", @"cloud.fill", @"cloud.sun.fill",
        @"cloud.bolt.fill", @"cloud.rain.fill", @"snow",
        @"wind", @"tornado", @"hurricane",
        // Trophies, Awards & Games
        @"trophy.fill", @"trophy.circle.fill",
        @"medal.fill", @"rosette",
        @"crown.fill", @"crown",
        @"gamecontroller.fill", @"gamecontroller",
        @"dice.fill", @"die.face.6.fill",
        @"puzzlepiece.fill", @"puzzlepiece.extension.fill",
        @"checkerboard.rectangle",
        // Documents & Writing
        @"doc.fill", @"doc.circle.fill",
        @"doc.text.fill", @"doc.richtext.fill",
        @"doc.text.magnifyingglass",
        @"doc.badge.plus", @"doc.badge.arrow.up.fill",
        @"note.text", @"note.text.badge.plus",
        @"newspaper.fill", @"newspaper.circle.fill",
        @"book.fill", @"book.circle.fill",
        @"book.closed.fill", @"books.vertical.fill",
        @"menucard.fill", @"magazine.fill",
        @"text.book.closed.fill",
        @"pencil", @"pencil.circle.fill",
        @"pencil.and.outline", @"square.and.pencil",
        @"highlighter", @"paintbrush.fill",
        @"paintbrush.pointed.fill",
        @"scribble", @"scribble.variable",
        @"signature", @"textformat",
        @"bold", @"italic", @"underline",
        @"paragraphsign", @"quote.opening", @"quote.closing",
        // Photos & Media
        @"photo.fill", @"photo.circle.fill",
        @"photo.stack.fill", @"photo.on.rectangle.fill",
        @"camera.fill", @"camera.circle.fill",
        @"camera.viewfinder",
        @"video.fill", @"video.circle.fill",
        @"film.fill", @"film.circle",
        @"play.fill", @"play.circle.fill",
        @"play.rectangle.fill",
        @"pause.fill", @"stop.fill",
        @"backward.fill", @"forward.fill",
        @"music.note", @"music.note.list",
        @"music.mic", @"music.quarternote.3",
        @"headphones", @"headphones.circle.fill",
        @"speaker.wave.3.fill", @"speaker.slash.fill",
        @"mic.fill", @"mic.circle.fill", @"mic.slash.fill",
        @"radio.fill",
        @"tv.fill", @"tv.circle.fill",
        @"display", @"laptopcomputer", @"iphone",
        // People & Social
        @"person.fill", @"person.circle.fill",
        @"person.2.fill", @"person.2.circle.fill",
        @"person.3.fill", @"person.3.sequence.fill",
        @"person.crop.circle.fill",
        @"person.crop.square.fill",
        @"figure.walk", @"figure.run",
        @"figure.wave", @"figure.stand",
        @"brain", @"brain.head.profile",
        @"eye.fill", @"eye.circle.fill",
        @"eye.slash.fill",
        @"face.smiling.fill", @"face.dashed.fill",
        @"bubble.left.fill", @"bubble.right.fill",
        @"bubble.left.and.bubble.right.fill",
        @"message.fill", @"message.circle.fill",
        @"text.bubble.fill", @"captions.bubble.fill",
        @"quote.bubble.fill",
        @"phone.fill", @"phone.circle.fill",
        @"envelope.fill", @"envelope.circle.fill",
        @"envelope.open.fill",
        @"at", @"at.circle.fill",
        // Nature & Animals
        @"leaf.fill", @"leaf.circle.fill",
        @"tree.fill", @"tree.circle.fill",
        @"lizard.fill", @"bird.fill",
        @"fish.fill", @"ant.fill",
        @"hare.fill", @"tortoise.fill",
        @"pawprint.fill", @"pawprint.circle.fill",
        @"drop.fill", @"drop.circle.fill",
        @"flame.fill",
        // Maps, Navigation & Travel
        @"map.fill", @"map.circle.fill",
        @"mappin.and.ellipse", @"mappin.circle.fill",
        @"location.fill", @"location.circle.fill",
        @"location.slash.fill",
        @"globe", @"globe.americas.fill",
        @"globe.europe.africa.fill", @"globe.asia.australia.fill",
        @"house.fill", @"house.circle.fill",
        @"building.fill", @"building.2.fill",
        @"building.columns.fill",
        @"airplane", @"airplane.circle.fill",
        @"car.fill", @"car.circle.fill",
        @"bus.fill", @"tram.fill",
        @"bicycle", @"bicycle.circle.fill",
        @"figure.outdoor.cycle",
        @"mountain.2.fill",
        @"beach.umbrella.fill",
        @"tent.fill", @"tent.2.fill",
        // Time, Calendar & Alerts
        @"clock.fill", @"clock.circle.fill",
        @"clock.badge.fill", @"clock.badge.checkmark.fill",
        @"clock.badge.exclamationmark.fill",
        @"alarm.fill", @"alarm.waves.left.and.right.fill",
        @"timer", @"timer.circle.fill",
        @"stopwatch.fill",
        @"calendar", @"calendar.circle.fill",
        @"calendar.badge.plus", @"calendar.badge.minus",
        @"calendar.badge.exclamationmark",
        @"bell.fill", @"bell.circle.fill",
        @"bell.slash.fill", @"bell.badge.fill",
        @"exclamationmark.circle.fill",
        @"exclamationmark.triangle.fill",
        @"checkmark.circle.fill", @"checkmark.seal.fill",
        @"xmark.circle.fill", @"xmark.octagon.fill",
        @"questionmark.circle.fill",
        @"info.circle.fill",
        // Food & Drink
        @"fork.knife", @"fork.knife.circle.fill",
        @"cup.and.saucer.fill", @"mug.fill",
        @"wineglass.fill", @"waterbottle.fill",
        @"birthday.cake.fill", @"popcorn.fill",
        @"carrot.fill", @"apple.logo",
        // Health & Fitness
        @"heart.fill", @"waveform.path.ecg",
        @"stethoscope", @"stethoscope.circle.fill",
        @"cross.fill", @"cross.circle.fill",
        @"bandage.fill", @"pills.fill",
        @"syringe.fill", @"testtube.2",
        @"dumbbell.fill", @"figure.strengthtraining.traditional",
        @"figure.yoga", @"figure.cooldown",
        @"figure.gymnastics",
        @"bed.double.fill", @"zzz",
        // Science & Tech
        @"atom",
        @"globe.badge.chevron.backward",
        @"cpu.fill", @"memorychip.fill",
        @"server.rack", @"network",
        @"wifi", @"wifi.slash",
        @"antenna.radiowaves.left.and.right",
        @"antenna.radiowaves.left.and.right.slash",
        @"bolt.horizontal.fill",
        @"powerplug.fill", @"battery.100.bolt",
        @"light.beacon.max.fill",
        @"flashlight.on.fill",
        @"magnifyingglass", @"magnifyingglass.circle.fill",
        @"binoculars.fill",
        // Commerce & Objects
        @"cart.fill", @"cart.circle.fill",
        @"basket.fill", @"bag.fill", @"bag.circle.fill",
        @"creditcard.fill", @"creditcard.circle.fill",
        @"banknote.fill", @"dollarsign.circle.fill",
        @"bitcoinsign.circle.fill",
        @"gift.fill", @"gift.circle.fill",
        @"shippingbox.fill", @"shippingbox.circle.fill",
        @"tag.fill",
        @"scissors", @"scissors.circle.fill",
        @"hammer.fill", @"hammer.circle.fill",
        @"wrench.fill", @"wrench.and.screwdriver.fill",
        @"screwdriver.fill",
        @"eyedropper.full",
        @"camera.filters",
        @"key.fill", @"key.horizontal.fill",
        @"lock.fill", @"lock.circle.fill",
        @"lock.open.fill", @"lock.slash.fill",
        @"shield.fill", @"shield.lefthalf.filled",
        @"shield.slash.fill",
        // Arrows & Directions
        @"arrow.up.circle.fill", @"arrow.down.circle.fill",
        @"arrow.left.circle.fill", @"arrow.right.circle.fill",
        @"arrow.up.right.circle.fill",
        @"arrow.clockwise.circle.fill",
        @"arrow.counterclockwise.circle.fill",
        @"arrow.triangle.2.circlepath.circle.fill",
        @"arrow.up.arrow.down.circle.fill",
        @"chevron.up.circle.fill", @"chevron.down.circle.fill",
        @"chevron.left.circle.fill", @"chevron.right.circle.fill",
        @"return.left", @"return.right",
        // Misc UI & Symbols
        @"square.and.arrow.up.fill", @"square.and.arrow.down.fill",
        @"square.and.arrow.up.on.square.fill",
        @"paperplane.fill", @"paperplane.circle.fill",
        @"link", @"link.circle.fill", @"link.badge.plus",
        @"safari.fill",
        @"command", @"command.circle.fill",
        @"option", @"control", @"function",
        @"cursorarrow.rays", @"cursorarrow.click.badge.clock",
        @"keyboard.fill",
        @"rectangle.on.rectangle.fill",
        @"square.on.square.fill",
        @"circle.fill", @"circle.hexagongrid.fill",
        @"square.fill", @"triangle.fill",
        @"diamond.fill", @"hexagon.fill",
        @"octagon.fill", @"seal.fill",
        @"infinity", @"infinity.circle.fill",
        @"plus.circle.fill", @"minus.circle.fill",
        @"multiply.circle.fill", @"divide.circle.fill",
        @"equal.circle.fill",
        @"percent", @"number.circle.fill",
        @"dollarsign", @"eurosign", @"sterlingsign",
        @"yensign", @"indianrupeesign",
    ];
}

@interface SFSymbolPickerViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) void (^selectionHandler)(NSString *symbolNameOrNil);
- (instancetype)initWithCurrentSymbol:(NSString *)currentSymbol;
@end

@implementation SFSymbolPickerViewController {
    NSArray<NSString *> *_allSymbols;
    NSArray<NSString *> *_filteredSymbols;
    NSString *_currentSymbol;
    UISearchController *_searchController;
}

- (instancetype)initWithCurrentSymbol:(NSString *)currentSymbol {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _currentSymbol = [currentSymbol copy];
        _allSymbols = AllCategorySymbols();
        _filteredSymbols = _allSymbols;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Choose Icon";

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"Search symbols";
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancel)];

    // Scroll to the currently-selected symbol so the user can see it.
    if (_currentSymbol) {
        NSUInteger idx = [_allSymbols indexOfObject:_currentSymbol];
        if (idx != NSNotFound) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)idx inSection:1];
                [self.tableView scrollToRowAtIndexPath:ip
                                     atScrollPosition:UITableViewScrollPositionMiddle
                                             animated:NO];
            });
        }
    }
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Two sections: 0 = "No Icon", 1 = symbol list
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (section == 0) ? 1 : (NSInteger)_filteredSymbols.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return (section == 1) ? @"Symbols" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SymCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SymCell"];
    }

    if (indexPath.section == 0) {
        cell.textLabel.text = @"No Icon";
        cell.imageView.image = [UIImage systemImageNamed:@"nosign"];
        cell.accessoryType = (_currentSymbol == nil)
            ? UITableViewCellAccessoryCheckmark
            : UITableViewCellAccessoryNone;
    } else {
        NSString *symName = _filteredSymbols[indexPath.row];
        cell.textLabel.text = symName;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
            configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
        cell.imageView.image = [UIImage systemImageNamed:symName withConfiguration:cfg];
        cell.accessoryType = ([symName isEqualToString:_currentSymbol])
            ? UITableViewCellAccessoryCheckmark
            : UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *selected = (indexPath.section == 0) ? nil : _filteredSymbols[indexPath.row];
    if (self.selectionHandler) {
        self.selectionHandler(selected);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

// UISearchResultsUpdating
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text;
    if (query.length == 0) {
        _filteredSymbols = _allSymbols;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"SELF CONTAINS[c] %@", query];
        _filteredSymbols = [_allSymbols filteredArrayUsingPredicate:pred];
    }
    [self.tableView reloadData];
}

@end

// MARK: - AddCategoryViewController
// Full-screen form (name field + icon picker row) replacing the plain UIAlertController.
// Validates for duplicate names before dismissing, and stores the selected SF Symbol
// icon via ApolloSetIconForCategory before calling the completion handler.

@interface AddCategoryViewController : UITableViewController
@property (nonatomic, copy) NSArray<NSString *> *existingCategoryNames;
@property (nonatomic, copy) void (^completionHandler)(NSString *name, NSString *iconName);
@end

@implementation AddCategoryViewController {
    UITextField *_nameField;
    NSString *_selectedIconName;
    UIBarButtonItem *_saveButton;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"New Category";

    _saveButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
        target:self action:@selector(save)];
    _saveButton.enabled = NO;
    self.navigationItem.rightBarButtonItem = _saveButton;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancel)];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_nameField becomeFirstResponder];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Name" : @"Icon";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        _nameField = [[UITextField alloc] init];
        _nameField.placeholder = @"Category Name";
        _nameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
        _nameField.returnKeyType = UIReturnKeyDone;
        _nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
        [_nameField addTarget:self action:@selector(nameChanged) forControlEvents:UIControlEventEditingChanged];
        _nameField.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:_nameField];
        [NSLayoutConstraint activateConstraints:@[
            [_nameField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [_nameField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [_nameField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [_nameField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        ]];
        return cell;
    }

    // Icon row
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    if (_selectedIconName) {
        cell.imageView.image = [UIImage systemImageNamed:_selectedIconName withConfiguration:cfg];
        cell.textLabel.text = _selectedIconName;
    } else {
        cell.imageView.image = [[UIImage systemImageNamed:@"nosign" withConfiguration:cfg]
            imageWithTintColor:[UIColor tertiaryLabelColor]
            renderingMode:UIImageRenderingModeAlwaysOriginal];
        cell.textLabel.text = @"No Icon";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tv shouldHighlightRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == 1;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != 1) return;
    [tv deselectRowAtIndexPath:ip animated:YES];
    [_nameField resignFirstResponder];

    SFSymbolPickerViewController *picker = [[SFSymbolPickerViewController alloc]
        initWithCurrentSymbol:_selectedIconName];
    __weak typeof(self) weakSelf = self;
    picker.selectionHandler = ^(NSString *symbolName) {
        AddCategoryViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_selectedIconName = symbolName;
        [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:1]]
                                   withRowAnimation:UITableViewRowAnimationNone];
    };
    // Present the picker modally in its own nav controller so the picker's built-in
    // Cancel button (which calls dismissViewControllerAnimated:) works correctly and
    // returns here rather than dismissing this whole form.
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)nameChanged {
    NSString *text = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _saveButton.enabled = text.length >= 3;
}

- (void)save {
    NSString *name = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    for (NSString *existing in self.existingCategoryNames) {
        if ([existing caseInsensitiveCompare:name] == NSOrderedSame) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"Name Already Used"
                message:@"A saved category already exists with that name, please choose a unique name."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
    }
    if (self.completionHandler) self.completionHandler(name, _selectedIconName);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

// MARK: - SavedCategoriesViewController

@implementation SavedCategoriesViewController

#pragma mark - Helpers

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)reloadCategories {
    _categoryNames = [self sortedCategoryNames];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Saved Categories";
    _categoryNames = [self sortedCategoryNames];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addCategory)];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _categoryNames.count > 0 ? (NSInteger)_categoryNames.count : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_categoryNames.count == 0) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"Cell_Cat_Empty"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell_Cat_Empty"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        cell.textLabel.text = @"No saved categories";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.imageView.image = nil;
        return cell;
    }

    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"Cell_Cat_Item"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell_Cat_Item"];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    NSString *name = _categoryNames[indexPath.row];
    cell.textLabel.text = name;
    cell.textLabel.textColor = [UIColor labelColor];

    NSString *iconName = ApolloIconForCategory(name);
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
    if (iconName) {
        cell.imageView.image = [UIImage systemImageNamed:iconName withConfiguration:cfg];
        cell.imageView.tintColor = self.view.tintColor;
    } else {
        // Placeholder — muted folder keeps the layout consistent
        cell.imageView.image = [[UIImage systemImageNamed:@"folder" withConfiguration:cfg]
            imageWithTintColor:[UIColor tertiaryLabelColor]
            renderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (_categoryNames.count == 0) return;

    NSString *name = _categoryNames[indexPath.row];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Set Icon" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self setIconForCategoryWithName:name];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self renameCategoryWithName:name];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self deleteCategoryWithName:name];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_categoryNames.count == 0) return nil;

    NSString *name = _categoryNames[indexPath.row];

    UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:@"Rename"
        handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self renameCategoryWithName:name];
            completionHandler(YES);
        }];
    renameAction.backgroundColor = [UIColor systemBlueColor];

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Delete"
        handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self deleteCategoryWithName:name];
            completionHandler(YES);
        }];

    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, renameAction]];
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return _categoryNames.count > 0;
}

#pragma mark - Saved Categories CRUD

- (NSMutableDictionary *)readSavedCategoriesDatabase {
    NSUserDefaults *groupDefaults = [[NSUserDefaults alloc] initWithSuiteName:kGroupSuiteName];
    NSData *data = [groupDefaults dataForKey:@"SavedItemsCategoriesDatabase"];
    if (!data) return nil;

    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (error || ![json isKindOfClass:[NSDictionary class]]) return nil;

    return [json mutableCopy];
}

- (void)writeSavedCategoriesDatabase:(NSDictionary *)database {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:database options:0 error:&error];
    if (error || !data) return;

    NSUserDefaults *groupDefaults = [[NSUserDefaults alloc] initWithSuiteName:kGroupSuiteName];
    [groupDefaults setObject:data forKey:@"SavedItemsCategoriesDatabase"];
    [groupDefaults synchronize];
}

- (NSArray<NSString *> *)sortedCategoryNames {
    NSDictionary *db = [self readSavedCategoriesDatabase];
    NSDictionary *categories = db[@"categories"];
    if (!categories || ![categories isKindOfClass:[NSDictionary class]]) return @[];
    return [[categories allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (BOOL)isValidCategoryName:(NSString *)name {
    if (!name) return NO;
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return trimmed.length >= 3;
}

- (void)setIconForCategoryWithName:(NSString *)categoryName {
    NSString *current = ApolloIconForCategory(categoryName);
    SFSymbolPickerViewController *picker = [[SFSymbolPickerViewController alloc]
        initWithCurrentSymbol:current];
    __weak typeof(self) weakSelf = self;
    picker.selectionHandler = ^(NSString *symbolName) {
        ApolloSetIconForCategory(categoryName, symbolName);
        [weakSelf reloadCategories];
    };
    UINavigationController *nav = [[UINavigationController alloc]
        initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)addCategory {
    AddCategoryViewController *addVC = [[AddCategoryViewController alloc] init];
    addVC.existingCategoryNames = _categoryNames;
    __weak typeof(self) weakSelf = self;
    addVC.completionHandler = ^(NSString *name, NSString *iconName) {
        NSMutableDictionary *db = [weakSelf readSavedCategoriesDatabase];
        if (!db) {
            db = [@{@"categories": [NSMutableDictionary dictionary]} mutableCopy];
        }
        NSMutableDictionary *categories = db[@"categories"];
        if (!categories) {
            categories = [NSMutableDictionary dictionary];
            db[@"categories"] = categories;
        }
        categories[name] = @[];
        if (iconName) {
            ApolloSetIconForCategory(name, iconName);
        }
        [weakSelf writeSavedCategoriesDatabase:db];
        [weakSelf reloadCategories];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:addVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)renameCategoryWithName:(NSString *)oldName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Category"
        message:nil
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = oldName;
        textField.placeholder = @"Category Name";
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *renameAction = [UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (newName.length == 0 || [newName isEqualToString:oldName]) return;

        NSMutableDictionary *db = [self readSavedCategoriesDatabase];
        if (!db) return;
        NSMutableDictionary *categories = db[@"categories"];
        if (!categories) return;

        // Check for duplicate (case-insensitive), excluding the old name being renamed
        for (NSString *existing in categories.allKeys) {
            if ([existing caseInsensitiveCompare:oldName] == NSOrderedSame) continue;
            if ([existing caseInsensitiveCompare:newName] == NSOrderedSame) {
                [self showAlertWithTitle:@"Name Already Used" message:@"A saved category already exists with that name, please choose a unique name."];
                return;
            }
        }

        id value = categories[oldName];
        [categories removeObjectForKey:oldName];
        categories[newName] = value ?: @[];
        [self writeSavedCategoriesDatabase:db];
        ApolloRenameIconForCategory(oldName, newName);
        [self reloadCategories];
    }];

    // Disable "Rename" until input is non-empty
    renameAction.enabled = [self isValidCategoryName:oldName];
    __weak UIAlertController *weakAlert = alert;
    __weak typeof(self) weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:UITextFieldTextDidChangeNotification
        object:alert.textFields.firstObject
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            NSString *text = weakAlert.textFields.firstObject.text;
            renameAction.enabled = [weakSelf isValidCategoryName:text];
        }];

    [alert addAction:cancelAction];
    [alert addAction:renameAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteCategoryWithName:(NSString *)name {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Category"
        message:[NSString stringWithFormat:@"Are you sure you want to delete \"%@\"? Items saved to this category will not be deleted.", name]
        preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSMutableDictionary *db = [self readSavedCategoriesDatabase];
        if (!db) return;
        NSMutableDictionary *categories = db[@"categories"];
        if (!categories) return;

        [categories removeObjectForKey:name];
        [self writeSavedCategoriesDatabase:db];
        ApolloRemoveIconForCategory(name);
        [self reloadCategories];
    }];

    [alert addAction:cancelAction];
    [alert addAction:deleteAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
