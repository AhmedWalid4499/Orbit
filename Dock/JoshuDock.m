// The Dock asks this plug-in for Joshu's icon, even while Joshu is closed. With Joshu Pro it shows the Pro icon;
// otherwise the app's usual one. Joshu saves the choice as "pro.dockIcon" and posts com.personal.orbit.dockIcon
// when it changes. Built and signed into Orbit.app/Contents/PlugIns by scripts/build-dock.sh.
#import <AppKit/AppKit.h>

@interface JoshuDockTile : NSObject <NSDockTilePlugIn>
@property (strong) NSDockTile *tile;
@property (strong) id observer;
@end

@implementation JoshuDockTile

- (void)setDockTile:(NSDockTile *)dockTile {
    if (self.observer) {
        [[NSDistributedNotificationCenter defaultCenter] removeObserver:self.observer];
        self.observer = nil;
    }
    self.tile = dockTile;
    if (!dockTile) return;
    [self update];
    __weak JoshuDockTile *weakSelf = self;
    self.observer = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"com.personal.orbit.dockIcon"
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weakSelf update]; }];
}

- (void)update {
    CFPreferencesAppSynchronize(CFSTR("com.personal.orbit"));
    Boolean found = false;
    Boolean pro = CFPreferencesGetAppBooleanValue(CFSTR("pro.dockIcon"), CFSTR("com.personal.orbit"), &found);
    NSURL *url = [[NSBundle bundleForClass:[self class]] URLForResource:@"AppIconPro" withExtension:@"png"];
    NSImage *image = (found && pro && url) ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (image) {
        NSImageView *view = [NSImageView imageViewWithImage:image];
        view.imageScaling = NSImageScaleProportionallyUpOrDown;
        self.tile.contentView = view;
    } else {
        self.tile.contentView = nil;   // the app's usual icon
    }
    [self.tile display];
}

@end
