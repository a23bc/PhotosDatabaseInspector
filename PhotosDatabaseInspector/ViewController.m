#import "ViewController.h"
#import "Photos/PhotoDatabaseScanner.h"

@interface ViewController ()
@property(nonatomic,strong) UITextView *output;
@property(nonatomic,strong) UIButton *scanButton;
@property(nonatomic,strong) UIButton *exportButton;
@property(nonatomic,copy) NSString *report;
@end

@implementation ViewController
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"Photos DB Inspector"; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.scanButton=[UIButton buttonWithType:UIButtonTypeSystem]; [self.scanButton setTitle:@"Scan Photos DB" forState:UIControlStateNormal]; self.scanButton.titleLabel.font=[UIFont boldSystemFontOfSize:17]; [self.scanButton addTarget:self action:@selector(scan:) forControlEvents:UIControlEventTouchUpInside];
    self.exportButton=[UIButton buttonWithType:UIButtonTypeSystem]; [self.exportButton setTitle:@"Export…" forState:UIControlStateNormal]; self.exportButton.titleLabel.font=[UIFont boldSystemFontOfSize:17]; self.exportButton.enabled=NO; [self.exportButton addTarget:self action:@selector(export:) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons=[[UIStackView alloc] initWithArrangedSubviews:@[self.scanButton,self.exportButton]]; buttons.axis=UILayoutConstraintAxisHorizontal; buttons.spacing=12; buttons.distribution=UIStackViewDistributionFillEqually;
    self.output=[UITextView new]; self.output.editable=NO; self.output.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular]; self.output.text=@"Ready.\n\nThis inspector is READ-ONLY.\nIt scans /var/mobile/Media/PhotoData and inspects SQLite schemas.\n";
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[buttons,self.output]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=12; stack.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],[stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],[stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],[stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],[buttons.heightAnchor constraintEqualToConstant:52]]]; }
- (void)scan:(id)sender { self.scanButton.enabled=NO; self.exportButton.enabled=NO; self.output.text=@"Scanning /var/mobile/Media/PhotoData…\n"; dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ NSString *r=[[PhotoDatabaseScanner shared] scanReport]; dispatch_async(dispatch_get_main_queue(),^{ self.report=r; self.output.text=r; self.scanButton.enabled=YES; self.exportButton.enabled=r.length>0; }); }); }
- (void)export:(id)sender { if(!self.report.length)return; UIActivityViewController *a=[[UIActivityViewController alloc] initWithActivityItems:@[self.report] applicationActivities:nil]; a.modalPresentationStyle=UIModalPresentationPopover; a.popoverPresentationController.sourceView=self.exportButton; a.popoverPresentationController.sourceRect=self.exportButton.bounds; [self presentViewController:a animated:YES completion:nil]; }
@end
