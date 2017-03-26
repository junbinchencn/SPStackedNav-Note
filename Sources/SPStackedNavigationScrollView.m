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

#import "SPStackedNavigationScrollView.h"
#import "SPStackedPageContainer.h"
#import <QuartzCore/QuartzCore.h>
#import "SPFunctional-mini.h"
#import "ChildTestViewController.h"

#ifndef CLAMP
#define CLAMP(v, min, max) ({ \
    __typeof(v) _v = v; \
    __typeof(min) _min = min; \
    __typeof(max) _max = max; \
    MAX(_min, MIN(_v, _max)); \
})
#endif
//fabs求绝对值
#define fcompare(actual, expected, epsilon) ({ \
    __typeof(actual) _actual = actual; \
    __typeof(expected) _expected = expected; \
    __typeof(epsilon) _epsilon = epsilon; \
    fabs(_actual - _expected) < _epsilon; \
})
#define fsign(f) ({ __typeof(f) _f = f; _f > 0. ? 1. : (_f < 0.) ? -1. : 0.; })

static const CGFloat kScrollDoneMarginOvershoot = 3;
static const CGFloat kScrollDoneMarginNormal = 1;
static const CGFloat kPanCaptureAngle = ((55.f) / 180.f * M_PI);
static const CGFloat kPanScrollViewDeceleratingCaptureAngle = ((40.f) / 180.f * M_PI);

@interface SPStackedNavigationScrollView () <UIGestureRecognizerDelegate>
@property(nonatomic,retain) UIPanGestureRecognizer *scrollRec;
@property(nonatomic,retain) CADisplayLink *scrollAnimationTimer;
@property(nonatomic,copy) void(^onScrollDone)();
- (void)scrollGesture:(UIPanGestureRecognizer*)grec;
- (void)updateContainerVisibilityByShowing:(BOOL)doShow byHiding:(BOOL)doHide;
@end

//理解 frame
//理解 bound
//理解 ContentOffSet
//模仿UIScrollView
@implementation SPStackedNavigationScrollView {
    //在 UIScrollView 滚动视图中，用户滚动时，滚动的是内容视图，
    CGPoint _actualOffset; //模拟 ScrollView 当前的 contentOffset
    CGPoint _targetOffset;// 将要滚动到的 contentOffset
    CGPoint _scrollAtStartOfPan;
    CGFloat _scrollDoneMargin;
    BOOL    _runningRunLoop;
    BOOL    _inRunLoop;
}
@synthesize scrollRec = _scrollRec;
@synthesize scrollAnimationTimer = _scrollAnimationTimer;
@synthesize onScrollDone = _onScrollDone;
@synthesize delegate = _delegate;

- (id)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    
    self.scrollRec = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrollGesture:)];
    _scrollRec.maximumNumberOfTouches = 1;
    _scrollRec.delaysTouchesBegan = _scrollRec.delaysTouchesEnded = NO;
    _scrollRec.cancelsTouchesInView = YES;
    _scrollRec.delegate = self;

    [self addGestureRecognizer:_scrollRec];
    
    return self;
}

#pragma mark Gesture recognizing
//计算ScrollView需要要滚动的范围
- (NSRange)scrollRangeForPageContainer:(SPStackedPageContainer*)pageC
{
    CGFloat width = 0.;
    for(SPStackedPageContainer *pc in self.subviews)
    {
        if (pc == pageC)
            break;
        if (pc.vc.stackedNavigationPageSize == kStackedPageFullSize)
            width += self.frame.size.width;
        else
            width += pc.frame.size.width;
    }
  
    return NSMakeRange(width, (pageC.vc.stackedNavigationPageSize  == kStackedPageFullSize ?
                               self.frame.size.width : 
                               pageC.frame.size.width));
}
//滚动范围
- (NSRange)scrollRange
{
    return [self scrollRangeForPageContainer:[self.subviews lastObject]];
}

//从页面从右向左划出
//添加pageC之后ScrollView的contentOffset计算
- (CGFloat)scrollOffsetForAligningPageWithRightEdge:(SPStackedPageContainer*)pageC
{
   //scrollRange是扣掉pageC之后的ScrollView的ContentSize
    NSRange scrollRange = [self scrollRangeForPageContainer:pageC];
    return scrollRange.location // align left edge with left edge of screen
        - self.frame.size.width // scroll it completely out of screen to the right
        + scrollRange.length; // scroll it back just so it's exactly on screen.
}


- (CGFloat)scrollOffsetForAligningPageWithLeftEdge:(SPStackedPageContainer*)pageC
{
    NSRange scrollRange = [self scrollRangeForPageContainer:pageC];
    return scrollRange.location;
}

//ScollView需要滚动到什么位置
- (CGFloat)scrollOffsetForAligningPage:(SPStackedPageContainer*)pageC position:(SPStackedNavigationPagePosition)position
{
    return (position == SPStackedNavigationPagePositionLeft ? 
            [self scrollOffsetForAligningPageWithLeftEdge:pageC] :
            [self scrollOffsetForAligningPageWithRightEdge:pageC]);
}
//获取对应VC的容器 SPStackedPageContainer
- (SPStackedPageContainer*)containerForViewController:(UIViewController*)viewController
{
    for (SPStackedPageContainer *pc in self.subviews)
    {
        if (pc.vc == viewController)
            return pc;
    }
    return nil;
}
//手势结束之后，View要滚动,这个方法在View边滚动的时候边调用
- (void)scrollAndSnapWithVelocity:(float)vel animated:(BOOL)animated
{
    // this is ugly, but we need to ensure that all views are loaded correctly to calculate left/right containers
    [self setNeedsLayout];
    [self layoutIfNeeded];
    
    // If swiping to the left, snap to the left; and vice versa.
    // 可以理解成scrollView的ContentOffSet
    CGFloat targetPoint;
    SPStackedPageContainer *target = nil;
    //左边容器是什么View
    //所有可见View的第一个
    SPStackedPageContainer *left = [self.subviews spstacked_any:^BOOL(id obj) { return [obj VCVisible]; }];
    //右边容器是什么View
    //所有可见View的集合的最后一个View
    SPStackedPageContainer *right = [self.subviews spstacked_filter:^BOOL(id obj) { return [obj VCVisible]; }].lastObject;
    
    ChildTestViewController *testLeftVC = (ChildTestViewController *)left.vc;
    ChildTestViewController *testRightVC = (ChildTestViewController *)right.vc;

    
    if (vel < 0) // trying to reveal to the left 展示左边，向右拖动
        target = left;
    else // trying to reveal to the right 展示右边，向左拖动
        target = right;
    
    // scroll extra far if user scrolls really fast
    // 滑动速度的快慢，判断需要滑到哪个View
    // 越快extraMove为越小负数
    // 滑动越快，越接近左边subviews的前几个View
    int extraMove = (fabs(vel) > 8500 ? 2 : (fabs(vel) > 5500) ? 1 : 0)*fsign(vel);
    if (extraMove != 0)
        target = (self.subviews)[CLAMP((int)[self.subviews indexOfObject:target]+extraMove, 0, (int)(self.subviews.count-1))];
    NSLog(@"_actualOffset-->%@",NSStringFromCGPoint(_actualOffset));
    // Align with left edge if scrolling left, or vice versa
    NSRange leftScrollRange = [self scrollRangeForPageContainer:left];
    // _actualOffset.x > (leftScrollRange.location + leftScrollRange.length/2)
    // 如果_actualOffset的位置大于left的滚动距离，那么使用left的下一个VC
    if (vel < 0 && extraMove == 0 && _actualOffset.x > (leftScrollRange.location + leftScrollRange.length/2)) {
        SPStackedPageContainer *targetView = (self.subviews)[CLAMP((int)[self.subviews indexOfObject:left]+1, 0, (int)(self.subviews.count-1))];
        if (UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation]))
            target = targetView;
        targetPoint = [self scrollOffsetForAligningPageWithRightEdge:targetView];
    } else if (vel < 0)
        targetPoint = [self scrollRangeForPageContainer:target].location;
    else
        targetPoint = [self scrollOffsetForAligningPageWithRightEdge:target];
    
    // Overshoot the target a bit
    if (animated)
    {
        __weak typeof(self) weakSelf = self;
        self.onScrollDone = ^{
            __strong __typeof(self) strongSelf = weakSelf;
            [strongSelf setContentOffset:CGPointMake(targetPoint, 0) animated:animated];
            [strongSelf->_delegate stackedNavigationScrollView:strongSelf
                            didStopAtPageContainer:target
                                      pagePosition:(target == left ? SPStackedNavigationPagePositionLeft :
                                                    SPStackedNavigationPagePositionRight)];
        };
    }
    //为什么要添加这个距离，用于做扯动动画？
    targetPoint += MAX(10, fabs(vel/150))*fsign(vel);
    NSLog(@"MAX(10, fabs(vel/150))*fsign(vel)-->%f",MAX(10, fabs(vel/150))*fsign(vel));
    
    [self setContentOffset:CGPointMake(targetPoint, 0) animated:animated];
    _scrollDoneMargin = kScrollDoneMarginOvershoot;
    
    if (!animated)
        [_delegate stackedNavigationScrollView:self
                        didStopAtPageContainer:target
                                  pagePosition:(target == left ? SPStackedNavigationPagePositionLeft :
                                                SPStackedNavigationPagePositionRight)];
}


- (void)scrollGesture:(UIPanGestureRecognizer*)grec
{
    if (grec.state == UIGestureRecognizerStateBegan) {
        _scrollAtStartOfPan = _actualOffset;
//        NSLog(@"_scrollAtStartOfPan--->%@",NSStringFromCGPoint(_scrollAtStartOfPan));
        [self startRunLoop];
//        NSLog(@"UIGestureRecognizerStateBegan");
    }
    else if (grec.state == UIGestureRecognizerStateChanged) {
        //手势移动的距离 手势加载self上 再将手势的坐标转成self上的坐标 那么这个方法 [grec translationInView:self].x) 取出来的x就是手势的移动距离;
        self.contentOffset = CGPointMake(_scrollAtStartOfPan.x-[grec translationInView:self].x, 0);
//        NSLog(@"UIGestureRecognizerStateChanged-->%@",NSStringFromCGPoint(self.contentOffset));
    } else if (grec.state == UIGestureRecognizerStateFailed || grec.state == UIGestureRecognizerStateCancelled) {
        [self stopRunLoop];
        [self setContentOffset:_scrollAtStartOfPan animated:YES];
//                NSLog(@"UIGestureRecognizerStateFailed || UIGestureRecognizerStateCancelled ");
    } else if (grec.state == UIGestureRecognizerStateRecognized) {
        // minus: swipe left means navigate to VC to the right
        //  减：向左滑动表示向右导航到VC
        [self stopRunLoop];
        NSLog(@"-[grec velocityInView:self].x-->%f",-[grec velocityInView:self].x);
      // velocity of the pan in points/second in the coordinate system of the specified view
//    向左为正速度、向右为负速度
        [self scrollAndSnapWithVelocity:-[grec velocityInView:self].x animated:YES];
//         NSLog(@"UIGestureRecognizerStateRecognized");
    }
}

// 控制RunLoop循环
- (void)startRunLoop
{
    if (!_runningRunLoop)
    {
        _runningRunLoop = YES;
        //Enqueues a block object on a given runloop to be executed as the runloop cycles in specified modes.
        CFRunLoopPerformBlock(CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, ^{
            //在手势识别的过程会执行以下过程
            if (_inRunLoop)
                return;
            _inRunLoop = YES;
            while (_runningRunLoop){
                //Runs the loop once, blocking for input in the specified mode until a given date
                //distantFuture : Creates and returns an NSDate object representing a date in the distant future
                //UITrackingRunLoopMode: 界面跟踪 Mode，用于 ScrollView 追踪触摸滑动，保证界面滑动时不受其他 Mode 影响
                [[NSRunLoop currentRunLoop] runMode:UITrackingRunLoopMode beforeDate:[NSDate distantFuture]];
            }

            _inRunLoop = NO;
        });
    }
}

- (void)stopRunLoop
{
    _runningRunLoop = NO;
}

//这个方法没被调用
//- (void)snapToClosest
//{
//    [self scrollAndSnapWithVelocity:0 animated:NO];
//}

- (UIPanGestureRecognizer *)panGestureRecognizer { return self.scrollRec; }

//根据滑动的角度判断是否需要接收手势事件
- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gestureRecognizer
{
    CGPoint velocity = [gestureRecognizer velocityInView:[gestureRecognizer view]];
    //滑动的角度
    CGFloat angle = velocity.x == 0.0 ?: atanf(fabsf(velocity.y / velocity.x));
    CGFloat captureAngle = kPanCaptureAngle;//((55.f) / 180.f * M_PI);
   //  decelerating:returns YES if user isn't dragging (touch up) but scroll view is still moving
    if ([[gestureRecognizer view] isKindOfClass:[UIScrollView class]] && [(UIScrollView*)[gestureRecognizer view] isDecelerating])
        captureAngle = kPanScrollViewDeceleratingCaptureAngle;//((40.f) / 180.f * M_PI)
    return captureAngle >= angle;
}

#pragma mark Animating content offset
@synthesize contentOffset = _targetOffset;
- (void)setContentOffset:(CGPoint)contentOffset
{
    [self setContentOffset:contentOffset animated:NO];
}
//手势释放的时候，View自动滚动
- (void)scrollAnimationFrame:(CADisplayLink*)cdl
{
    //offset的差别超过 _scrollDoneMargin
    // fabs(_targetOffset.x - _actualOffset.x) > _scrollDoneMargin
    if (fcompare(_targetOffset.x, _actualOffset.x, _scrollDoneMargin)) {
        //取消原来的定时器,停止滑动
        [self.scrollAnimationTimer invalidate]; self.scrollAnimationTimer = nil;
        [self setNeedsLayout];
        // 设置新的ScrollView contentOffset
        _actualOffset = _targetOffset;
        if (_onScrollDone) {
            self.onScrollDone();
            self.onScrollDone = nil;
        } else{
            // we're done animating, hide everything that needs to be hidden
            [self updateContainerVisibilityByShowing:YES byHiding:YES];
        }
        // TODO<nevyn>: Unblock processing
    }
    NSTimeInterval delta = cdl.duration;
    CGFloat diff = _targetOffset.x - _actualOffset.x;
    //CLAMP 取中值
    //每秒移动的距离
    CGFloat movementPerSecond = CLAMP(abs(diff)*14, 20, 4000)*fsign(diff);
    //在一个cdl.duration时间内的移动距离
    CGFloat movement = movementPerSecond * delta;
    if (abs(movement) > abs(diff)) movement = diff; // so we never step over the target point
    _actualOffset.x += movement;
    [self setNeedsLayout];
}

//手势释放的时候，View自动滚动
- (void)animateToTargetScrollOffset
{
    if (_scrollAnimationTimer) return;
    _scrollDoneMargin = kScrollDoneMarginNormal;
    //定时器
    self.scrollAnimationTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(scrollAnimationFrame:)];
    [_scrollAnimationTimer addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    // TODO<nevyn>: Block processing
}

//模仿 ScrollView 滚动到指定位置
- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated
{
    _targetOffset = contentOffset;
    if (animated)
        [self animateToTargetScrollOffset];
    else {
        _actualOffset = _targetOffset;
        if (_onScrollDone)
        {
            self.onScrollDone();
            self.onScrollDone = nil;
        }
        [self setNeedsLayout];
    }                                                                                                                         
}



- (void)layoutSubviews
{
    // pen 的作用是stretch scroll at start and end
    // 用于在第一屏从左向右拉扯和最后一屏从右向左拉扯，
    // 让手势拖动的距离2倍于View移动的距离。
    // _actualOffset 改变之后，通过特定的规则计算 pen 的 frame,然后将 frame 赋值给 View ，
    // 总之作用就是调整 View 的 frame 位置
    // 可以说 pen 就是对应的每个分屏的 frame
    CGRect pen = CGRectZero;

    // 为什么需要 -  _actualOffset.x ？
    // 为了得到每个分屏 View 的坐标的 X 值 （坐标原点是 SPStackedNavigationScrollView 的坐标原点，即在屏幕范围内的最左边的分屏 View 的左上角位置）
    // 详见 ContentOffset 的计算方法
    pen.origin.x = -_actualOffset.x;
    
    // stretch scroll at start and end
    if (_actualOffset.x < 0){
        // 第一页从左向右拉扯 _actualOffset.x < 0 才成立，
        // _actualOffset 就是当前模仿的 UIScrollView 的 contentOffset
        // 手势拖动的距离2倍于 View 移动的距离
        pen.origin.x = -_actualOffset.x/2;
    }

    CGFloat maxScroll = [self scrollOffsetForAligningPageWithRightEdge:self.subviews.lastObject];
    if (_actualOffset.x > maxScroll){
            pen.origin.x = -(maxScroll + (_actualOffset.x-maxScroll)/2);
    }

    int i = 0;
    // markedForSuperviewRemovalOffset 标记 pageC 自己的 offset 坐标
    // 用来给 superview 把 pageC 从当前位置移动到 markedForSuperviewRemovalOffset 指定的坐标
    // 可以让自己的 View 对边缘层叠效果做出对应的位置
    // 也可以让 pageC 自己全屏或者半屏,
    CGFloat markedForSuperviewRemovalOffset = pen.origin.x;// View 的坐标位置x
    NSMutableArray *stackedViews = [NSMutableArray array];
    
    for(SPStackedPageContainer *pageC in self.subviews) {
        pen.size = pageC.bounds.size;
        pen.size.height = self.frame.size.height;
        if (pageC.vc.stackedNavigationPageSize == kStackedPageFullSize)
            pen.size.width = self.frame.size.width;
        
        CGRect actualPen = pen;
        if (pageC.markedForSuperviewRemoval)
            actualPen.origin.x = markedForSuperviewRemovalOffset;
        // Stack on the left
        // 小于 （0，1，2，3）*3
        // 左边是一个 stackedViews，最多有3层边缘层叠效果
        if (actualPen.origin.x < (MIN(i, 3))*3){
           // 如果actualPen.origin.x 小于 (MIN(i, 3))*3 那么说明该 pageC 的位置不是在 stackedViews 最顶部的三个以内
           [stackedViews addObject:pageC];
        }else{
           pageC.hidden = NO;
        }

        if (self.scrollAnimationTimer == nil)
            // floorf取整操作
            actualPen.origin.x = floorf(actualPen.origin.x);
        // 改变pageC.frame，那么pageC就会动了
        pageC.frame = actualPen;
        // NSLog(@"pageC.frame---->%@",NSStringFromCGRect(pageC.frame));
        // pageC.frame---->{{-1416, 0}, {944, 768}} 第一屏 全屏
        // pageC.frame---->{{-472, 0}, {472, 768}}  第二屏 半屏
        // pageC.frame---->{{0, 0}, {472, 768}} 第三屏 半屏 显示在左边
        // pageC.frame---->{{472, 0}, {472, 768}} 第四屏 半屏 显示在右边
        markedForSuperviewRemovalOffset += pen.size.width;
        // NavVC 做 POP 操作的时候会将 markedForSuperviewRemoval 置为 YES
        // 前面 pen.origin.x = -_actualOffset.x;
        // 这里计算下一个屏幕的位置 frame 的 x 值
        // 所以需要加上 pen.size.width
        if (!pageC.markedForSuperviewRemoval)
            pen.origin.x += pen.size.width;
        
        // 覆盖不透明度
        if (actualPen.origin.x <= 0 && pageC != [self.subviews lastObject]) {
            // abs()绝对值函数
            pageC.overlayOpacity = 0.3/actualPen.size.width*abs(actualPen.origin.x);
        } else {
            pageC.overlayOpacity = 0.0;
        }

        i++;
    }
    
    i = 0;
    for (NSInteger index = 0; index < [stackedViews count]; index++)
    {
        SPStackedPageContainer *pageC = stackedViews[index];
        // stackedViews 包括 RootVC 的 View;
        // stackedViews 里面的最后3个 View 显示
        if ([stackedViews count] > 3 && index < ([stackedViews count]-3))
            pageC.hidden = YES;
        else
        {
            // 左边是一个 stackedViews，最多有3层边缘层叠效果
            pageC.hidden = NO;
            CGRect frame = pageC.frame;
            // 调整坐标，显示层叠效果
            frame.origin.x = 0 + MIN(i, 3)*3;
            pageC.frame = frame;
            i++;
        }
    }
    
    // Only make sure we show what we need to, don't unload stuff until we're done animating
    [self updateContainerVisibilityByShowing:YES byHiding:NO];
}

#pragma mark Visibility
//控制 pageC 的可见性
- (void)updateContainerVisibilityByShowing:(BOOL)doShow byHiding:(BOOL)doHide
{
    // fabsf 浮点数的绝对值
    // 分屏 View 是否需要弹跳效果
    BOOL bouncing = self.scrollAnimationTimer && fabsf(_targetOffset.x - _actualOffset.x) < 30;
    
    // layoutSubViews的 pen 是一个 frame、
    // 这里的 pen 是一个 frame 的 x 坐标
    // 但是用法和 layoutSubViews 的 pen 没什么区别
    CGFloat pen = -_actualOffset.x;
    
    // stretch scroll at start and end
    if (_actualOffset.x < 0)
        pen = -_actualOffset.x/2;
    
    CGFloat maxScroll = [self scrollOffsetForAligningPageWithRightEdge:self.subviews.lastObject];

    if (_actualOffset.x > maxScroll)
        pen = -(maxScroll + (_actualOffset.x-maxScroll)/2);
    // 用来让 SuperView 移动 pageC 的 x 坐标，原点是屏幕显示的最左边的分屏的 X 坐标
    CGFloat markedForSuperviewRemovalOffset = pen;
    
    NSMutableArray *viewsToDelete = [NSMutableArray array];
    for(SPStackedPageContainer *pageC in self.subviews) {
        CGFloat currentPen = pen;
        // 该 pageC 被做了 POP 操作，需要被 SuperView移除
        if (pageC.markedForSuperviewRemoval)
            currentPen = markedForSuperviewRemovalOffset;
        // 该分屏是否是在屏幕可见的分屏的右边同时无法看见该分屏
        BOOL isOffScreenToTheRight = currentPen >= self.bounds.size.width;

        NSRange scrollRange = [self scrollRangeForPageContainer:pageC];
        // View 是否被其他 View 覆盖了
        BOOL isCovered = currentPen + scrollRange.length <= 0;
        
        // View 现在是否可见
        BOOL isVisible = !isOffScreenToTheRight && !isCovered;
        

        // pageC 的可见性发生变化 && （ (isVisible == NO  && doHide == Yes)  ||  isVisible == Yes && doShow ==Yes）
        // 只要 pageC 的可见性发生变化，不管是隐藏还是显示都执行下面的if条件分支
        if (pageC.VCVisible != isVisible && ((!isVisible && doHide) || (isVisible && doShow)))
        {
            
            // pageC分屏将出现
            // pageC分屏将离开屏幕
            //(isVisible == No || bouncing == No || (isVisible ==Yes && needsInitialPresentation == Yes))
            if (!isVisible || !bouncing || (isVisible && pageC.needsInitialPresentation)) {
                pageC.needsInitialPresentation = NO;
                pageC.VCVisible = isVisible;
            }
        }
        // 要隐藏 pageC 并且该 pageC 被标记为销毁的
        //(doHide ==Yes && pageC.markedForSuperviewRemoval ==Yes)
        // 将 pageC 加入销毁数组 viewsToDelete
        if (doHide && pageC.markedForSuperviewRemoval)
            [viewsToDelete addObject:pageC];
        
        //经过 Demo 验证 pen 和 markedForSuperviewRemovalOffset 的值一样
        markedForSuperviewRemovalOffset += pageC.frame.size.width;
        
        // markedForSuperviewRemoval = No
        // 计算 pen 的值，该值为下一个分屏的 X 坐标
        if (!pageC.markedForSuperviewRemoval)
            pen += pageC.frame.size.width;
    }
    // 对viewsToDelete数组里面的View执行销毁操作
    [viewsToDelete makeObjectsPerformSelector:@selector(removeFromSuperview)];
}

@end
