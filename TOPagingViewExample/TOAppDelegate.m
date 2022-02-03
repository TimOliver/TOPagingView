//
//  AppDelegate.m
//  TOPagingViewExample
//
//  Created by Tim Oliver on 2020/03/23.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TOAppDelegate.h"
#import "TOViewController.h"

@interface TOAppDelegate ()

@end

@implementation TOAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[TOViewController alloc] init];
    [self.window makeKeyAndVisible];

#if TARGET_OS_MACCATALYST
    if (@available(iOS 13.0, *)) {
        self.window.windowScene.titlebar.titleVisibility = UITitlebarTitleVisibilityHidden;
    }
#endif

    return YES;
}

@end
