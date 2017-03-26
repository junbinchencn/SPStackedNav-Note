// Copyright 2014 Spotify
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//  File created by Joachim Bengtsson on 2012-10-27.

#import "RootTestViewController.h"
#import <SPStackedNav/SPStackedNav.h>
#import "ChildTestViewController.h"

@implementation RootTestViewController

- (id)init
{
    if (!(self = [super init]))
        return nil;
    
//    self.view.backgroundColor = [UIColor redColor];
    return self;
}

- (SPStackedNavigationPageSize)stackedNavigationPageSize
{
    return kStackedPageFullSize;
}

- (IBAction)test:(id)sender
{
    ChildTestViewController *vc = [ChildTestViewController new];
    [self.stackedNavigationController pushViewController:vc animated:YES];
}

@end
