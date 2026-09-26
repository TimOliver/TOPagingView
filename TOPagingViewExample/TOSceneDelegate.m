//
//  TOSceneDelegate.m
//  TOPagingViewExample
//
//  Copyright © 2026 Tim Oliver. All rights reserved.
//

#import "TOSceneDelegate.h"
#import "TOViewController.h"

@implementation TOSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = [[TOViewController alloc] init];
    [self.window makeKeyAndVisible];

#if TARGET_OS_MACCATALYST
    windowScene.titlebar.titleVisibility = UITitlebarTitleVisibilityHidden;
#endif
}

@end
