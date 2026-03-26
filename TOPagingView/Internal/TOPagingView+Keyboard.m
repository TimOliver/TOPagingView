//
//  TOPagingView+Keyboard.m
//
//  Copyright 2018-2026 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "TOPagingView+Keyboard.h"

@implementation TOPagingView (Keyboard)

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (NSArray<UIKeyCommand *> *)keyCommands {
    SEL selector = @selector(arrowKeyPressed:);
    UIKeyCommand *leftArrowCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow modifierFlags:0 action:selector];

    UIKeyCommand *rightArrowCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow modifierFlags:0 action:selector];

    if (@available(iOS 15.0, *)) {
        leftArrowCommand.wantsPriorityOverSystemBehavior = YES;
        rightArrowCommand.wantsPriorityOverSystemBehavior = YES;
    }

    return @[leftArrowCommand, rightArrowCommand];
}

- (void)arrowKeyPressed:(UIKeyCommand *)command {
    if ([command.input isEqualToString:UIKeyInputLeftArrow]) {
        [self turnToLeftPageAnimated:YES];
    } else if ([command.input isEqualToString:UIKeyInputRightArrow]) {
        [self turnToRightPageAnimated:YES];
    }
}

@end
