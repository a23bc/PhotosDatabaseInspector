#import "ViewController.h"
#import "Photos/PhotoDatabaseScanner.h"
#import "Photos/PhotoDatabaseInspector.h"

static NSString *const kDefaultPhotosDatabase = @"/var/mobile/Media/PhotoData/Photos.sqlite";

#pragma mark - Shared UI helpers

static UIButton *MakeButton(NSString *title, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static UIStackView *MakeButtonRow(NSArray<UIView *> *views) {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:views];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFillEqually;
    return row;
}

#pragma mark - Report screen

/* Deliberately contains no text input and no alert: version 0.2.0 crashed inside CoreImage
   the first time the keyboard was shown, so this screen only displays and exports text.
   See docs/PHOTOS_DATABASE_HANDOVER.md. */
@interface ReportViewController : UIViewController
@property(nonatomic, copy) NSString *reportName;
@property(nonatomic, copy) NSString *reportText;
@property(nonatomic, strong) UITextView *output;
@property(nonatomic, strong) UIButton *clipboardButton;
@property(nonatomic, strong) UIButton *shareButton;
@end

@implementation ReportViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.reportName.length ? self.reportName : @"Report";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.clipboardButton = MakeButton(@"Copy", self, @selector(putInClipboard:));
    self.shareButton = MakeButton(@"Share…", self, @selector(shareReport:));
    UIStackView *buttons = MakeButtonRow(@[self.clipboardButton, self.shareButton]);
    buttons.translatesAutoresizingMaskIntoConstraints = NO;

    self.output = [UITextView new];
    self.output.editable = NO;
    self.output.selectable = NO;   /* no edit menu: keep this screen free of extra UIKit chrome */
    self.output.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.output.text = self.reportText ?: @"";
    self.output.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:buttons];
    [self.view addSubview:self.output];
    [NSLayoutConstraint activateConstraints:@[
        [buttons.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [buttons.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [buttons.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [buttons.heightAnchor constraintEqualToConstant:40],
        [self.output.topAnchor constraintEqualToAnchor:buttons.bottomAnchor constant:8],
        [self.output.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.output.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.output.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]
    ]];
}

/* Not named -copy...: a "copy" prefix puts the method in the ObjC copy method family,
   which ARC requires to return an owned object. */
- (void)putInClipboard:(id)sender {
    UIPasteboard.generalPasteboard.string = self.reportText ?: @"";
    NSString *previous = self.title;
    self.title = @"Copied to clipboard";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1500000000), dispatch_get_main_queue(), ^{
        self.title = previous;
    });
}

- (void)shareReport:(id)sender {
    if (!self.reportText.length) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.reportText]
                                                                         applicationActivities:nil];
    activity.modalPresentationStyle = UIModalPresentationPopover;
    activity.popoverPresentationController.sourceView = self.shareButton;
    activity.popoverPresentationController.sourceRect = self.shareButton.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

@end

#pragma mark - Asset row cell

@interface AssetCell : UITableViewCell
@property(nonatomic, strong) UILabel *line1;
@property(nonatomic, strong) UILabel *line2;
@end

@implementation AssetCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _line1 = [UILabel new];
        _line1.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        _line1.translatesAutoresizingMaskIntoConstraints = NO;
        _line2 = [UILabel new];
        _line2.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
        _line2.textColor = UIColor.secondaryLabelColor;
        _line2.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_line1];
        [self.contentView addSubview:_line2];
        [NSLayoutConstraint activateConstraints:@[
            [_line1.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_line1.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_line1.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [_line2.topAnchor constraintEqualToAnchor:_line1.bottomAnchor constant:2],
            [_line2.leadingAnchor constraintEqualToAnchor:_line1.leadingAnchor],
            [_line2.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-8]
        ]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}
@end

#pragma mark - Asset list screen

@interface AssetListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *moreButton;
@property(nonatomic, strong) UIButton *censusButton;
@property(nonatomic, strong) UIButton *detailButton;
@property(nonatomic, strong) UIButton *compareButton;
@property(nonatomic, strong) NSArray<NSDictionary<NSString *, NSString *> *> *rows;
@property(nonatomic, strong) NSMutableIndexSet *selected;
@property(nonatomic, copy) NSString *error;
@property(nonatomic) NSInteger limit;
@property(nonatomic, copy) NSString *total;
@end

@implementation AssetListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Assets";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.rows = @[];
    self.selected = [NSMutableIndexSet indexSet];
    self.limit = 50;
    self.total = @"?";

    self.statusLabel = [UILabel new];
    self.statusLabel.numberOfLines = 3;
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    /* CGRectZero is a real CoreGraphics symbol; this target links UIKit and Foundation only,
       so use the inline CGRectMake instead. The frame is replaced by Auto Layout anyway. */
    self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 0, 0) style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 48;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.table registerClass:[AssetCell class] forCellReuseIdentifier:@"asset"];

    self.moreButton = MakeButton(@"More", self, @selector(loadMore:));
    self.censusButton = MakeButton(@"Census", self, @selector(showCensus:));
    self.detailButton = MakeButton(@"Detail", self, @selector(showDetail:));
    self.compareButton = MakeButton(@"Compare", self, @selector(compareSelected:));
    UIStackView *row1 = MakeButtonRow(@[self.moreButton, self.censusButton]);
    UIStackView *row2 = MakeButtonRow(@[self.detailButton, self.compareButton]);
    row1.translatesAutoresizingMaskIntoConstraints = NO;
    row2.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.table];
    [self.view addSubview:row1];
    [self.view addSubview:row2];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],

        [self.table.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:6],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:row1.topAnchor constant:-6],

        [row1.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [row1.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [row1.heightAnchor constraintEqualToConstant:40],

        [row2.topAnchor constraintEqualToAnchor:row1.bottomAnchor constant:6],
        [row2.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [row2.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [row2.heightAnchor constraintEqualToConstant:40],
        [row2.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-6]
    ]];

    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateStatus];
}

#pragma mark Loading

- (void)setBusy:(BOOL)busy {
    self.moreButton.enabled = !busy;
    self.censusButton.enabled = !busy;
    [self updateStatus];
}

- (void)reload {
    [self setBusy:YES];
    self.statusLabel.text = [NSString stringWithFormat:@"reading %ld rows from Photos.sqlite…", (long)self.limit];
    NSInteger limit = self.limit;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        PhotoDatabaseInspector *inspector = [[PhotoDatabaseInspector alloc] initWithDatabasePath:kDefaultPhotosDatabase];
        NSDictionary<NSString *, id> *overview = [inspector assetOverviewWithLimit:limit];
        NSArray<NSDictionary<NSString *, NSString *> *> *rows = overview[@"rows"];
        NSString *total = overview[@"total"];
        NSString *error = overview[@"error"];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.rows = rows ?: @[];
            self.total = total ?: @"?";
            self.error = error;
            [self.selected removeAllIndexes];
            [self.table reloadData];
            [self setBusy:NO];
            [self updateStatus];
        });
    });
}

- (void)updateStatus {
    if (self.error.length) {
        self.statusLabel.text = [NSString stringWithFormat:@"ERROR: %@\n%@", self.error, kDefaultPhotosDatabase];
        self.detailButton.enabled = NO;
        self.compareButton.enabled = NO;
        return;
    }
    self.statusLabel.text = [NSString stringWithFormat:
        @"loaded %lu of %@ assets   selected: %lu\n%@\ntap a row to select; Detail = 1 row, Compare = 2+ rows",
        (unsigned long)self.rows.count, self.total, (unsigned long)self.selected.count, kDefaultPhotosDatabase];
    self.detailButton.enabled = (self.selected.count >= 1);
    self.compareButton.enabled = (self.selected.count >= 2);
}

- (void)loadMore:(id)sender {
    self.limit = MIN(self.limit * 4, 20000);
    [self reload];
}

- (NSArray<NSString *> *)selectedPrimaryKeys {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    [self.selected enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        if (index < self.rows.count) {
            NSString *key = self.rows[index][@"Z_PK"];
            if (key.length) [keys addObject:key];
        }
    }];
    return keys;
}

#pragma mark Actions

- (void)showCensus:(id)sender {
    [self setBusy:YES];
    self.statusLabel.text = @"reading the ZASSET class census…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        PhotoDatabaseInspector *inspector = [[PhotoDatabaseInspector alloc] initWithDatabasePath:kDefaultPhotosDatabase];
        NSString *report = [inspector assetCensusReport];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            [self pushReportNamed:@"Census" text:report];
        });
    });
}

- (void)showDetail:(id)sender {
    NSArray<NSString *> *keys = [self selectedPrimaryKeys];
    if (!keys.count) return;
    NSString *key = keys.firstObject;
    [self setBusy:YES];
    self.statusLabel.text = [NSString stringWithFormat:@"dumping Z_PK=%@…", key];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        PhotoDatabaseInspector *inspector = [[PhotoDatabaseInspector alloc] initWithDatabasePath:kDefaultPhotosDatabase];
        NSString *report = [inspector assetDumpReportForSearch:key];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            [self pushReportNamed:[NSString stringWithFormat:@"Z_PK=%@", key] text:report];
        });
    });
}

- (void)compareSelected:(id)sender {
    NSArray<NSString *> *keys = [self selectedPrimaryKeys];
    if (keys.count < 2) return;
    [self setBusy:YES];
    self.statusLabel.text = [NSString stringWithFormat:@"comparing %lu assets…", (unsigned long)keys.count];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        PhotoDatabaseInspector *inspector = [[PhotoDatabaseInspector alloc] initWithDatabasePath:kDefaultPhotosDatabase];
        NSString *report = [inspector assetCompareReportForSearches:keys];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            [self pushReportNamed:@"Compare" text:report];
        });
    });
}

- (void)pushReportNamed:(NSString *)name text:(NSString *)text {
    ReportViewController *report = [ReportViewController new];
    report.reportName = name;
    report.reportText = text;
    [self.navigationController pushViewController:report animated:YES];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AssetCell *cell = [tableView dequeueReusableCellWithIdentifier:@"asset" forIndexPath:indexPath];
    NSDictionary<NSString *, NSString *> *row = self.rows[(NSUInteger)indexPath.row];
    BOOL isSelected = [self.selected containsIndex:(NSUInteger)indexPath.row];
    cell.line1.text = [NSString stringWithFormat:@"%@ %@", isSelected ? @"[x]" : @"[ ]", row[@"ZFILENAME"]];
    cell.line2.text = [NSString stringWithFormat:@"Z_PK=%@  %@/%@/%@  %@  %@",
                       row[@"Z_PK"], row[@"ZKIND"], row[@"ZKINDSUBTYPE"], row[@"ZSAVEDASSETTYPE"],
                       row[@"ZUNIFORMTYPEIDENTIFIER"], row[@"ZDATECREATED"]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger index = (NSUInteger)indexPath.row;
    if ([self.selected containsIndex:index]) [self.selected removeIndex:index];
    else [self.selected addIndex:index];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateStatus];
}

@end

#pragma mark - Root screen (Phase 1)

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

    self.scanButton = MakeButton(@"Scan Photos DB", self, @selector(scan:));
    self.scanButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.assetButton = MakeButton(@"Asset Inspector", self, @selector(openAssetInspector:));
    self.assetButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.exportButton = MakeButton(@"Export…", self, @selector(export:));
    self.exportButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.exportButton.enabled = NO;

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.scanButton, self.assetButton, self.exportButton]];
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.spacing = 8;
    buttons.distribution = UIStackViewDistributionFillEqually;

    self.output = [UITextView new];
    self.output.editable = NO;
    self.output.selectable = NO;
    self.output.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.output.text = @"Ready.\n\nThis inspector is READ-ONLY.\n"
                        "\"Scan Photos DB\" runs the Phase 1 schema scan of /var/mobile/Media/PhotoData.\n"
                        "\"Asset Inspector\" reads real asset records from Photos.sqlite (Phase 2). Samples are\n"
                        "chosen by tapping rows - there is no text input, because showing the keyboard\n"
                        "crashed version 0.2.0 on iOS 15.8.8 (see the crash report in logs/).\n\n"
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
    [self.navigationController pushViewController:[AssetListViewController new] animated:YES];
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
