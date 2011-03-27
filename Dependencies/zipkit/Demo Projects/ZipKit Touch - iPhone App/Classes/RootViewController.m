#import "RootViewController.h"
#import "ZKDefs.h"
#import "ZKDataArchive.h"

@implementation RootViewController
@synthesize nextViewController;
@synthesize imageView;
@synthesize textView;
@synthesize archive;

- (void) awakeFromNib {
	self.nextViewController = [UIViewController new];
	
	self.imageView = [UIImageView new];	
	self.textView = [UITextView new];
	self.textView.editable = NO;
	
	NSString *archivePath = [[NSBundle mainBundle] pathForResource:@"ZipKitTest" ofType:@"zip"];
	self.archive = [ZKDataArchive archiveWithArchivePath:archivePath];
	[self.archive inflateAll];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"ZipKit Touch";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *) tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *) tableView numberOfRowsInSection:(NSInteger) section {
	return [self.archive.inflatedFiles count];
}

- (UITableViewCell *)tableView:(UITableView *) tableView cellForRowAtIndexPath:(NSIndexPath *) indexPath {
	static NSString *CellIdentifier = @"Cell";
	
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil)
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
	
	NSDictionary *entry = [self.archive.inflatedFiles objectAtIndex:[indexPath row]];
	cell.textLabel.text = [entry objectForKey:ZKPathKey];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	
	return cell;
}

- (void)tableView:(UITableView *) tableView didSelectRowAtIndexPath:(NSIndexPath *) indexPath {
	NSUInteger row = [indexPath row];
	NSDictionary *fileDict = [self.archive.inflatedFiles objectAtIndex:row];
	NSData *fileData = [fileDict objectForKey:ZKFileDataKey];
	NSString *fileName = [fileDict objectForKey:ZKPathKey];
	
	NSString *ext = [fileName pathExtension];
	if ([ext isEqualToString:@"txt"]) {
		[self.textView setText:[[[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding] autorelease]];
		self.nextViewController.view = self.textView;
	} else if ([ext isEqualToString:@"png"]) {
		[self.imageView setImage:[UIImage imageWithData:fileData]];
		self.nextViewController.view = self.imageView;
	} else {
		[self.textView setText:@"Only txt and PNG files are supported"];
		self.nextViewController.view = self.textView;
	}
	
	[self.navigationController pushViewController:nextViewController animated:YES];
}

- (void)dealloc {
	[archive release];
	[nextViewController release];
	[imageView release];
	[textView release];
	[super dealloc];
}

@end