#import "ViewController.h"
#import "Photos/PhotoDatabaseScanner.h"
#import "Photos/PhotoDatabaseInspector.h"

static NSString *const kDefaultPhotosDatabase = @"/var/mobile/Media/PhotoData/Photos.sqlite";

#pragma mark - Phase 2 UI : asset inspector

@interface AssetInspectorViewController : UIViewController <UITextFieldDelegate>
@property(nonatomic, strong) UITextField *pathField;
@property(nonatomic, strong) UITextField *searchField;
@property(nonatomic, strong) UIButton *listButton;
@property(nonatomic, strong) UIButton *dumpButton;
@property(nonatomic, strong) UIButton *compareButton;
@property(nonatomic, strong) UIButton *exportButton;
@property(nonatomic, strong) UITextView *output;
@property(nonatomic, copy) NSString *report;
@end

@implementation AssetInspectorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Asset Inspector";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.pathField = [self makeField:@"database path" text:kDefaultPhotosDatabase];
    self.pathField.keyboardType = UIKeyboardTypeURL;
    self.searchField = [self makeField:@"filename / UUID / Z_PK - or A,B,C to compare" text:@""];

    self.listButton = [self makeButton:@"Asset list" action:@selector(listAssets:)];
    self.dumpButton = [self makeButton:@"Dump asset" action:@selector(dumpAsset:)];
    self.compareButton = [self makeButton:@"Compare" action:@selector(compareAssets:)];
    self.exportButton = [self makeButton:@"Export" action:@selector(export:)];
    self.exportButton.enabled = NO;

    UIStackView *row1 = [self buttonRow:@[self.listButton, self.dumpButton]];
    UIStackView *row2 = [self buttonRow:@[self.compareButton, self.exportButton]];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[row1, row2]];
    actions.axis = UILayoutConstraintAxisVertical;
    actions.spacing = 8;
    actions.distribution = UIStackViewDistributionFillEqually;

    self.output = [UITextView new];
    self.output.editable = NO;
    self.output.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.output.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.output.text = @"Asset Inspector - READ ONLY\n\n"
                        "1. \"Asset list\"  : newest ZASSET rows + the ZKIND/ZKINDSUBTYPE/ZSAVEDASSETTYPE census\n"
                        "2. \"Dump asset\"  : full record of one asset (ZASSET + every table referencing it)\n"
                        "3. \"Compare\"     : field-by-field diff of several assets\n\n"
                        "For 3., type the samples you prepared, e.g.  Screenshot.PNG,IMG_0002.PNG,IMG_0003.HEIC\n\n"
                        "Nothing on this screen writes to the database: the file is opened read-only\n"
                        "and the -wal/-shm sidecars are never touched.\n";

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.pathField, self.searchField, actions, self.output]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [self.pathField.heightAnchor constraintEqualToConstant:36],
        [self.searchField.heightAnchor constraintEqualToConstant:36],
        [actions.heightAnchor constraintEqualToConstant:96]
    ]];
}

#pragma mark UI helpers

- (UITextField *)makeField:(NSString *)placeholder text:(NSString *)text {
    UITextField *field = [UITextField new];
    field.placeholder = placeholder;
    field.text = text;
    field.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyGo;
    field.delegate = self;
    return field;
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIStackView *)buttonRow:(NSArray<UIView *> *)views {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:views];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFillEqually;
    return row;
}

- (void)setBusy:(BOOL)busy {
    self.listButton.enabled = !busy;
    self.dumpButton.enabled = !busy;
    self.compareButton.enabled = !busy;
    self.exportButton.enabled = !busy && self.report.length > 0;
}

- (void)alert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Asset Inspector"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

/* Runs a read-only inspection off the main thread. */
- (void)runTitle:(NSString *)title operation:(NSString * (^)(void))operation {
    [self setBusy:YES];
    self.output.text = [NSString stringWithFormat:@"%@ …\n", title];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *report = operation();
        dispatch_async(dispatch_get_main_queue(), ^{
            self.report = report;
            self.output.text = report;
            [self setBusy:NO];
        });
    });
}

- (NSString *)resolvedPath {
    NSString *path = [self.pathField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!path.length) {
        [self alert:@"Enter the path of a Photos SQLite database."];
        return nil;
    }
    return path;
}

- (NSArray<NSString *> *)searchTerms {
    NSString *text = self.searchField.text ?: @"";
    NSArray<NSString *> *pieces = [text componentsSeparatedByCharactersInSet:
                                   [NSCharacterSet characterSetWithCharactersInString:@",;"]];
    NSMutableArray<NSString *> *terms = [NSMutableArray array];
    for (NSString *piece in pieces) {
        NSString *trimmed = [piece stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length) [terms addObject:trimmed];
    }
    return terms;
}

#pragma mark Actions

- (void)listAssets:(id)sender {
    NSString *path = [self resolvedPath];
    if (!path) return;
    [self runTitle:@"Reading ZASSET" operation:^NSString * {
        PhotoDatabaseInspector *inspector = [[PhotoDatabaseInspector alloc] initWithDatabasePath:path];
        return [inspector assetListReportWithLimit:50];
    }];
}

- (void)dumpAsset:(id)sender {
    NSString *path = [self resolvedPath];
    if (!path) return;
    NSString *term = [self searchTerms].firstObject;
    if (!term.length) {
        [self alert:@"Enter one filename, UUID or Z_PK number to dump."];
        return;
    }
    [self runTitle:[NSString stringWithFormat:@"Dumping %@", term] operation:^NSString * {
        PhotoDatabaseInspector *inspector = [[PhotoDatabaseInspector alloc] initWithDatabasePath:path];
        return [inspector assetDumpReportForSearch:term];
    }];
}

- (void)compareAssets:(id)sender {
    NSString *path = [self resolvedPath];
    if (!path) return;
    NSArray<NSString *> *terms = [self searchTerms];
    if (terms.count < 2) {
        [self alert:@"Compare needs at least two comma-separated terms,\nfor example:  Screenshot.PNG,IMG_0002.PNG,IMG_0003.HEIC"];
        return;
    }
    [self runTitle:[NSString stringWithFormat:@"Comparing %lu assets", (unsigned long)terms.count] operation:^NSString * {
        PhotoDatabaseInspector *inspector = [[PhotoDatabaseInspector alloc] initWithDatabasePath:path];
        return [inspector assetCompareReportForSearches:terms];
    }];
}

- (void)export:(id)sender {
    if (!self.report.length) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.report]
                                                                         applicationActivities:nil];
    activity.modalPresentationStyle = UIModalPresentationPopover;
    activity.popoverPresentationController.sourceView = self.exportButton;
    activity.popoverPresentationController.sourceRect = self.exportButton.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    if (textField == self.searchField) [self dumpAsset:nil];
    return YES;
}

@end

#pragma mark - Phase 1 UI : schema scanner

@interface ViewController ()
@property(nonatomic, strong) UITextView *output;
@property(nonatomic, strong) UIButton *scanButton;
@property(nonatomic, strong) UIButton *assetButton;
@property(nonatomic, strong) UIButton *exportButton;
@property(nonatomic, copy) NSString *report;
@end

@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Photos DB Inspector";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.scanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.scanButton setTitle:@"Scan Photos DB" forState:UIControlStateNormal];
    self.scanButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.scanButton addTarget:self action:@selector(scan:) forControlEvents:UIControlEventTouchUpInside];

    self.assetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.assetButton setTitle:@"Asset Inspector" forState:UIControlStateNormal];
    self.assetButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.assetButton addTarget:self action:@selector(openAssetInspector:) forControlEvents:UIControlEventTouchUpInside];

    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.exportButton setTitle:@"Export…" forState:UIControlStateNormal];
    self.exportButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.exportButton.enabled = NO;
    [self.exportButton addTarget:self action:@selector(export:) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.scanButton, self.assetButton, self.exportButton]];
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.spacing = 8;
    buttons.distribution = UIStackViewDistributionFillEqually;

    self.output = [UITextView new];
    self.output.editable = NO;
    self.output.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.output.text = @"Ready.\n\nThis inspector is READ-ONLY.\n"
                        "\"Scan Photos DB\" performs the Phase 1 schema scan of /var/mobile/Media/PhotoData.\n"
                        "\"Asset Inspector\" reads real asset records from Photos.sqlite (Phase 2).\n\n"
                        "Neither path writes to any database.\n";

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[buttons, self.output]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [buttons.heightAnchor constraintEqualToConstant:152]
    ]];
}

- (void)scan:(id)sender {
    self.scanButton.enabled = NO;
    self.exportButton.enabled = NO;
    self.output.text = @"Scanning /var/mobile/Media/PhotoData…\n";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *report = [[PhotoDatabaseScanner shared] scanReport];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.report = report;
            self.output.text = report;
            self.scanButton.enabled = YES;
            self.exportButton.enabled = report.length > 0;
        });
    });
}

- (void)openAssetInspector:(id)sender {
    [self.navigationController pushViewController:[AssetInspectorViewController new] animated:YES];
}

- (void)export:(id)sender {
    if (!self.report.length) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.report]
                                                                         applicationActivities:nil];
    activity.modalPresentationStyle = UIModalPresentationPopover;
    activity.popoverPresentationController.sourceView = self.exportButton;
    activity.popoverPresentationController.sourceRect = self.exportButton.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}
@end
