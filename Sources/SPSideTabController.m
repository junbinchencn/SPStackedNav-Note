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

#import "SPSideTabController.h"

@interface SPSideTabController () <SPSideTabBarDelegate> {
    BOOL _bottomAttachmentHidden;
    NSArray *_additionalItems;
}
@property(nonatomic,readwrite,retain) SPSideTabBar *tabBar; 
@property(nonatomic,retain) UIView *mainContainer;//内容容器
@property(nonatomic,retain) UIView *bottomContainer;//底部容器，位于屏幕底部下方，看不到。不知有何作用
- (void)addBottomAttachmentToContainer;
@end

@implementation SPSideTabController
#define BOTTOM_BAR_HEIGHT 69

- (void)loadView
{
    CGRect afRect = [[UIScreen mainScreen] applicationFrame];
    CGRect pen = afRect;
    UIView *root = [[UIView alloc] initWithFrame:pen];
    self.view = root;
    
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    //生成Tabbar
    pen.origin = (CGPoint){0,0};
    pen.size.width = 80;
//    NSLog(@"pen-->%@",NSStringFromCGRect(pen));
    self.tabBar = [[SPSideTabBar alloc] initWithFrame:pen];
    self.tabBar.delegate = self;
    self.tabBar.backgroundColor = [UIColor yellowColor];
    [root addSubview:_tabBar];
    
    //生成主界面
    pen.origin.x += pen.size.width;
    pen.size.width = afRect.size.width-pen.size.width;
    pen.size.height -= BOTTOM_BAR_HEIGHT;
    _mainContainer = [[UIView alloc] initWithFrame:pen];
    _mainContainer.backgroundColor= [UIColor redColor];
//    NSLog(@"pen--_mainContainer>%@",NSStringFromCGRect(pen));
    [root addSubview:_mainContainer];
    
    pen.origin.y = CGRectGetMaxY(pen);
    pen.size.height = BOTTOM_BAR_HEIGHT;
    _bottomContainer = [[UIView alloc] initWithFrame:pen];
    _bottomContainer.backgroundColor = [UIColor greenColor];
    [_bottomContainer setClipsToBounds:NO];
    [root addSubview:_bottomContainer];
    
    [self addBottomAttachmentToContainer];

//    root.backgroundColor = [UIColor blackColor];
//    _mainContainer.backgroundColor = [UIColor blackColor];
//    _bottomContainer.backgroundColor = [UIColor colorWithRed:0.7 green:0.7 blue:0.7 alpha:1.0];
    
    if (_selectedViewController) {
        UIViewController *sel = _selectedViewController;
        [self setSelectedViewController:nil];
        [self setSelectedViewController:sel];
    }
    //添加底部附件View
//    [self addBottomAttachmentToContainer];
    [self setBottomAttachmentHidden:YES animated:NO];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // We just created the tab bar: make selection and contents match internal state
    NSArray *allItems = [_viewControllers valueForKey:@"tabBarItem"];
    NSMutableArray *validItems = [NSMutableArray array];
    for (int i = 0; i < [allItems count]; i++)
    {
        id item = allItems[i];
        if ([item isKindOfClass:[NSNull class]])
            NSLog(@"Error, NULL tab bar item from view controller '%@'.", _viewControllers[i]);
        else
            [validItems addObject:item];
    }
    _tabBar.items = validItems;
    _tabBar.additionalItems = self.additionalItems;
    _tabBar.selectedItem = (_tabBar.items)[self.selectedIndex];
    
    // If it was hidden before view was loaded
    [self setBottomAttachmentHidden:_bottomAttachmentHidden animated:NO];
}

- (void)viewDidUnload
{
    self.bottomContainer = nil;
    self.mainContainer = nil;
    self.tabBar.delegate = nil;
    self.tabBar = nil;
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return YES;
}

- (NSSet*)keyPathsForValuesAffectingValueForSelectedIndex
{
    return [NSSet setWithObject:@"selectedViewController"];
}
//设置TabViewController的viewControllers
- (void)setViewControllers:(NSArray *)viewControllers
{
    if ([viewControllers isEqual:_viewControllers]) return;
    
    [self setSelectedViewController:nil];
    
    for(UIViewController *vc in _viewControllers) [vc removeFromParentViewController];
    
    _viewControllers = [viewControllers copy];
    
    for(UIViewController *vc in _viewControllers) [self addChildViewController:vc];
    
    _tabBar.items = [_viewControllers valueForKey:@"tabBarItem"];
    self.selectedViewController = _viewControllers[0];
    
    for (UIViewController *vc in _viewControllers) [vc didMoveToParentViewController:self];
}

//设置TabViewController的选中ViewController
- (void)setSelectedViewController:(UIViewController *)newVC
{
    if (newVC == _selectedViewController) return;
    
    UIViewController *oldVC = _selectedViewController;
    _selectedViewController = newVC;
    
    if (![self isViewLoaded]) return;
    
    _tabBar.selectedItem = newVC.tabBarItem;

    UIView *oldView = oldVC.view;
    UIView *newView = newVC.view;
    
    CGRect centered = _mainContainer.bounds;
    
    CGRect above = _mainContainer.bounds;
    above.origin.y -= above.size.height;
    
    CGRect below = _mainContainer.bounds;
    below.origin.y += below.size.height;
    
    newView.frame = centered;

    [oldView removeFromSuperview];
    [_mainContainer addSubview:newView];
}
//选中的selectedViewController的索引
- (NSUInteger)selectedIndex
{
    return [_viewControllers indexOfObject:_selectedViewController];
}
//通过索引设置TabViewController的选中ViewController
- (void)setSelectedIndex:(NSUInteger)selectedIndex
{
    [self setSelectedViewController:_viewControllers[selectedIndex]];
}

- (NSArray *)additionalItems
{
    return _additionalItems;
}
//添加item到tabar的底部
- (void)setAdditionalItems:(NSArray *)additionalItems
{
    if (_additionalItems != additionalItems)
    {
        _additionalItems = additionalItems;
        if ([self isViewLoaded])
            [_tabBar setAdditionalItems:additionalItems];
    }
}

- (void)setBottomAttachment:(UIViewController *)bottomAttachment
{
    if (bottomAttachment == _bottomAttachment) {
        return;
    }

    [_bottomAttachment removeFromParentViewController];
    [_bottomAttachment.view removeFromSuperview];
    _bottomAttachment = bottomAttachment;

    [self addBottomAttachmentToContainer];
}

//添加底部附件View
- (void)addBottomAttachmentToContainer
{
    if (!self.bottomAttachment) {
        return;
    }

    [self addChildViewController:self.bottomAttachment];

    self.bottomAttachment.view.frame = self.bottomContainer.bounds;
    [self.bottomContainer addSubview:self.bottomAttachment.view];
    
    [self.bottomAttachment didMoveToParentViewController:self];
}
//tabBar点击
- (void)tabBar:(SPSideTabBar *)tabBar didSelectItem:(UITabBarItem *)item
{
    NSArray *vcItems = [self.viewControllers valueForKey:@"tabBarItem"];
    if ([vcItems containsObject:item]) {
        UIViewController *newVC = (self.viewControllers)[[vcItems indexOfObject:item]];
        if (newVC != self.selectedViewController)
            self.selectedViewController = newVC;
        else {
            if ([newVC respondsToSelector:@selector(popToRootViewControllerAnimated:)])
                [(id)newVC popToRootViewControllerAnimated:YES];
        }
    } else
        [_tabBarDelegate tabBar:tabBar didSelectItem:item];
}

- (BOOL)isBottomAttachmentHidden
{
    return _bottomAttachmentHidden;
}
//是否隐藏底部附件View
- (void)setBottomAttachmentHidden:(BOOL)hide animated:(BOOL)animated
{
    _bottomAttachmentHidden = hide;
    if (![self isViewLoaded]) return;
    
    CGRect mainFrame = _mainContainer.frame;
    CGRect bottomFrame = _bottomContainer.frame;
    
    if (!hide) {
        // 需要显示底部附件View，收缩mainframe
        // shrink main frame
        mainFrame.size.height = self.view.frame.size.height - BOTTOM_BAR_HEIGHT;
        bottomFrame.origin.y = CGRectGetMaxY(mainFrame);
    } else {
        // 不需要显示底部附件View，bottomFrame的坐标放到屏幕外面
        mainFrame.size.height = self.view.frame.size.height;
        bottomFrame.origin.y = CGRectGetMaxY(mainFrame) + 1;
    }
        
    if (animated) {
        static const CGFloat kAnimationDuration = .25;
        
        [UIView animateWithDuration:kAnimationDuration
                              delay:0
            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                             _bottomContainer.frame = bottomFrame;
                             
                             if (hide) {
                                 _mainContainer.frame = mainFrame;
                             }
                         }
                         completion:^(BOOL finished) {
                             /**
                              * NOTE<kristofersommestad>:
                              * Dispatch async since the main frame will be updated before the bottom frame otherwise (is the thread blocked?).
                              * That the main and bottom frames can't be animated at the same time is very strange, but this works for now... 
                              */
                             if (!hide) {
                                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kAnimationDuration * 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                     _mainContainer.frame = mainFrame;
                                 });   
                             }
                         }
        ];
    }
    else {
        _mainContainer.frame = mainFrame;
        _bottomContainer.frame = bottomFrame;
    }
}

//设置View的frame
- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    CGRect bounds = self.view.bounds;
//    NSLog(@"bounds-->%@",NSStringFromCGRect(bounds));
    
    _tabBar.frame = CGRectMake(0, 0, _tabBar.frame.size.width, bounds.size.height);
    
    if (_bottomAttachmentHidden)
    {
        _mainContainer.frame = CGRectMake(CGRectGetMaxX(_tabBar.frame),
                                          0,
                                          bounds.size.width - CGRectGetMaxX(_tabBar.frame),
                                          bounds.size.height);
//        NSLog(@"_mainContainer-->%@",NSStringFromCGRect(_mainContainer.frame));
        
        _bottomContainer.frame = CGRectMake(CGRectGetMaxX(_tabBar.frame),
                                            CGRectGetMaxY(bounds) + 1,
                                            bounds.size.width - CGRectGetMaxX(_tabBar.frame),
                                            BOTTOM_BAR_HEIGHT);
//        NSLog(@"_bottomContainer.frame-->%@",NSStringFromCGRect(_bottomContainer.frame));
    }
    else
    {
        _mainContainer.frame = CGRectMake(CGRectGetMaxX(_tabBar.frame),
                                          0,
                                          bounds.size.width - CGRectGetMaxX(_tabBar.frame),
                                          bounds.size.height - BOTTOM_BAR_HEIGHT);
        _bottomContainer.frame = CGRectMake(CGRectGetMaxX(_tabBar.frame),
                                            CGRectGetMaxY(_mainContainer.frame),
                                            bounds.size.width - CGRectGetMaxX(_tabBar.frame),
                                            BOTTOM_BAR_HEIGHT);
    }
    
    for (UIView *superview in @[_mainContainer, _bottomContainer])
         for (UIView *subview in superview.subviews)
         {
             subview.frame = superview.bounds;
             [subview setNeedsLayout];
         }
}

@end
//设置SPTabBarItem的内容
@implementation SPTabBarItem
@synthesize view = _buttonView;
@synthesize imageName = _imageName;
- (id)initWithTitle:(NSString *)title imageName:(NSString*)imageName tag:(NSInteger)tag
{
    if (!(self = [super init]))
        return nil;
    
    self.title = title;
    self.imageName = imageName;
    self.tag = tag;
    
    return self;
}
@end

