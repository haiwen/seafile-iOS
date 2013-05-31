//
//  M13InfiniteTabBar.m
//  M13InfiniteTabBar
/*
 Copyright (c) 2013 Brandon McQuilkin
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 One does not claim this software as ones own.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import "M13InfiniteTabBar.h"
#import "M13InfiniteTabBarItem.h"
#import "Debug.h"
@implementation M13InfiniteTabBar
{
    UITapGestureRecognizer *_singleTapGesture;
    UIView *_tabContainerView;
    NSUInteger _previousSelectedIndex;
    NSMutableArray *_visibleIcons; //Icons in the scrollview
    NSArray *_items;
    BOOL _scrollAnimationCheck;
}

- (id)initWithInfiniteTabBarItems:(NSArray *)items
{
    self = [super initWithFrame:CGRectMake(0, 0, [[UIScreen mainScreen] applicationFrame].size.width, 60)];
    if (self) {
        // Initialization code
        self.delegate = self;
        self.contentSize = self.frame.size;
        self.backgroundColor = [UIColor clearColor];
        
        //Content size
        self.contentSize = CGSizeMake(items.count * ((M13InfiniteTabBarItem *)[items lastObject]).frame.size.width * 4, self.frame.size.height); //Need to iterate 4 times for infinite animation
        _tabContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 10, self.contentSize.width, self.contentSize.height)];
        _tabContainerView.backgroundColor = [UIColor clearColor];
        _tabContainerView.userInteractionEnabled = NO;
        [self addSubview:_tabContainerView];
        
        //hide horizontal indicator so the recentering trick is not revealed
        [self setShowsHorizontalScrollIndicator:NO];
        [self setShowsVerticalScrollIndicator:NO];
        self.userInteractionEnabled = YES;
        
        //Add gesture for taps
        _singleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTapGestureCaptured:)];
        _singleTapGesture.cancelsTouchesInView = NO;
        _singleTapGesture.delegate = self;
        _singleTapGesture.delaysTouchesBegan = NO;
        [self addGestureRecognizer:_singleTapGesture];
        
        
        _visibleIcons = [[NSMutableArray alloc] initWithCapacity:items.count];
        _items = items;
        
        //Reindex
        int tag = 0;
        for (M13InfiniteTabBarItem *item in items) {
            item.frame = CGRectMake(2000.0, 10.0, item.frame.size.width, item.frame.size.height);
            item.tag = tag;
            tag += 1;
        }
        
        //Set Previous Index
        _previousSelectedIndex = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) ? 2 : 5;
        _selectedItem = [_items objectAtIndex:_previousSelectedIndex];
        [((M13InfiniteTabBarItem *)[_items objectAtIndex:_previousSelectedIndex]) setSelected:YES];
        
        [self rotateItemsToOrientation:[UIDevice currentDevice].orientation];
        NSLog(@"%@ : %@ : %@", NSStringFromCGRect(self.frame), NSStringFromCGSize(self.contentSize), NSStringFromCGRect(_tabContainerView.frame));
    }
    return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    //Allow the scroll view to work simintaniously with the tap gesture and pull view gesture
    if ((gestureRecognizer == self.panGestureRecognizer || otherGestureRecognizer == self.panGestureRecognizer) || (gestureRecognizer == _singleTapGesture || otherGestureRecognizer == _singleTapGesture)) {
        return YES;
    } else {
        return NO;
    }
}

//recenter peridocially to acheive the impression of infinite scrolling
- (void)recenterIfNecessary
{
    CGPoint currentOffset = [self contentOffset];
    CGFloat contentWidth = [self contentSize].width;
    CGFloat centerOffsetX = (contentWidth - [self bounds].size.width) / 2.0;
    CGFloat distanceFromCenter = fabs(currentOffset.x - centerOffsetX);
    
    if (distanceFromCenter > (contentWidth / 4.0)) {
        self.contentOffset = CGPointMake(centerOffsetX, currentOffset.y);
        
        // move content by the same amount so it appears to stay still
        for (M13InfiniteTabBarItem *view in _visibleIcons) {
            CGPoint center = [_tabContainerView convertPoint:view.center toView:self];
            center.x += (centerOffsetX - currentOffset.x);
            view.center = [self convertPoint:center toView:_tabContainerView];
        }
    }
}

//Retile content
- (void)layoutSubviews
{
    [super layoutSubviews];
    
    [self recenterIfNecessary];
    
    // tile content in visible bounds
    CGRect visibleBounds = [self convertRect:[self bounds] toView:_tabContainerView];
    CGFloat minimumVisibleX = CGRectGetMinX(visibleBounds);
    CGFloat maximumVisibleX = CGRectGetMaxX(visibleBounds);
    
    [self tileLabelsFromMinX:minimumVisibleX toMaxX:maximumVisibleX];
}

//Handle icon rotation on device rotation
- (void)rotateItemsToOrientation:(UIDeviceOrientation)orientation;
{
    CGFloat angle = 0;
    if ( orientation == UIDeviceOrientationLandscapeLeft ) angle = M_PI_2;
    else if ( orientation == UIDeviceOrientationLandscapeRight ) angle = -M_PI_2;
    else if ( orientation == UIDeviceOrientationPortraitUpsideDown ) angle = M_PI;
    for (M13InfiniteTabBarItem *item in _visibleIcons) {
        [item rotateToAngle:angle];
    }
    for (M13InfiniteTabBarItem *item in _items) {
        [item rotateToAngle:angle];
    }
}

//Tiling labels

- (CGFloat)placeNewLabelOnRight:(CGFloat)rightEdge
{
    //Get item of next index
    M13InfiniteTabBarItem *rightMostItem = [_visibleIcons lastObject];
    int rightMostIndex = rightMostItem.tag;
    int indexToInsert = rightMostIndex + 1;
    //Loop back if next index is past end of availableIcons
    if (indexToInsert == [_items count]) {
        indexToInsert = 0;
    }
    //M13InfiniteTabBarItem *itemToInsert = [(M13InfiniteTabBarItem *)[_items objectAtIndex:indexToInsert] copy];
    M13InfiniteTabBarItem *itemToInsert = (M13InfiniteTabBarItem *)[_items objectAtIndex:indexToInsert];

    itemToInsert.tag = indexToInsert;
    [_visibleIcons addObject:itemToInsert];
    
    CGRect frame = [itemToInsert frame];
    frame.origin.x = rightEdge;
    frame.origin.y = 0;
    [itemToInsert setFrame:frame];
    
    [_tabContainerView addSubview:itemToInsert];
    
    return CGRectGetMaxX(frame);
}

- (CGFloat)placeNewLabelOnLeft:(CGFloat)leftEdge
{
    //Get item of next index
    M13InfiniteTabBarItem *leftMostItem = [_visibleIcons objectAtIndex:0];
    int leftMostIndex = leftMostItem.tag;
    int indexToInsert = leftMostIndex - 1;
    //Loop back if next index is past end of availableIcons
    if (indexToInsert == -1) {
        indexToInsert = [_items count] - 1;
    }
    //M13InfiniteTabBarItem *itemToInsert = [(M13InfiniteTabBarItem *)[_items objectAtIndex:indexToInsert] copy];
    M13InfiniteTabBarItem *itemToInsert = (M13InfiniteTabBarItem *)[_items objectAtIndex:indexToInsert];

    itemToInsert.tag = indexToInsert;
    [_visibleIcons insertObject:itemToInsert atIndex:0];  // add leftmost label at the beginning of the array
    
    CGRect frame = [itemToInsert frame];
    frame.origin.x = leftEdge - frame.size.width;
    frame.origin.y = 0;
    [itemToInsert setFrame:frame];
    
    [_tabContainerView addSubview:itemToInsert];
    
    return CGRectGetMinX(frame);
}

- (void)tileLabelsFromMinX:(CGFloat)minimumVisibleX toMaxX:(CGFloat)maximumVisibleX {
    // the upcoming tiling logic depends on there already being at least one label in the visibleLabels array, so
    // to kick off the tiling we need to make sure there's at least one label
    if ([_visibleIcons count] == 0) {
        //M13InfiniteTabBarItem *itemToInsert = [(M13InfiniteTabBarItem *)[_items objectAtIndex:0] copy];
        M13InfiniteTabBarItem *itemToInsert = (M13InfiniteTabBarItem *)[_items objectAtIndex:0];
        itemToInsert.tag = 0;
        [_visibleIcons addObject:itemToInsert];
        
        CGRect frame = [itemToInsert frame];
        frame.origin.x = minimumVisibleX;
        frame.origin.y = 0;
        [itemToInsert setFrame:frame];
        
        [_tabContainerView addSubview:itemToInsert];
    }
    
    // add labels that are missing on right side
    M13InfiniteTabBarItem *lastItem = [_visibleIcons lastObject];
    CGFloat rightEdge = CGRectGetMaxX([lastItem frame]);
    while (rightEdge < maximumVisibleX) {
        rightEdge = [self placeNewLabelOnRight:rightEdge];
    }
    
    // add labels that are missing on left side
    M13InfiniteTabBarItem *firstItem = [_visibleIcons objectAtIndex:0];
    CGFloat leftEdge = CGRectGetMinX([firstItem frame]);
    while (leftEdge > minimumVisibleX) {
        leftEdge = [self placeNewLabelOnLeft:leftEdge];
    }
    
    // remove labels that have fallen off right edge
    lastItem = [_visibleIcons lastObject];
    while ([lastItem frame].origin.x > maximumVisibleX) {
        [lastItem removeFromSuperview];
        [_visibleIcons removeLastObject];
        lastItem = [_visibleIcons lastObject];
    }
    
    // remove labels that have fallen off left edge
    firstItem = [_visibleIcons objectAtIndex:0];
    while (CGRectGetMaxX([firstItem frame]) < minimumVisibleX) {
        [firstItem removeFromSuperview];
        [_visibleIcons removeObjectAtIndex:0];
        firstItem = [_visibleIcons objectAtIndex:0];
    }
}

//Actions

- (void)singleTapGestureCaptured:(UITapGestureRecognizer *)gesture
{
    M13InfiniteTabBarItem *item = (M13InfiniteTabBarItem *)[self viewAtLocation:[gesture locationInView:self]];
    if (self.contentOffset.x == (item.frame.origin.x + (item.frame.size.width / 2.0)) - (self.frame.size.width / 2.0)) {
        //center tab tapped
        [self scrollViewDidEndScrollingAnimation:self];
    } else {
        //Center tapped tab
        [self setContentOffset:CGPointMake((item.frame.origin.x + (item.frame.size.width / 2.0)) - (self.frame.size.width / 2.0), 0) animated:YES];
    }
}

- (void)setSelectedItem:(M13InfiniteTabBarItem *)selectedItem
{
    Debug("#%d %f\n", selectedItem.tag, selectedItem.frame.origin.x);
    if (self.contentOffset.x == (selectedItem.frame.origin.x + (selectedItem.frame.size.width / 2.0)) - (self.frame.size.width / 2.0)) {
        //center tab tapped
        [self scrollViewDidEndScrollingAnimation:self];
    } else {
        //Center tapped tab
        [self setContentOffset:CGPointMake((selectedItem.frame.origin.x + (selectedItem.frame.size.width / 2.0)) - (self.frame.size.width / 2.0), 0) animated:NO];
        [self scrollViewDidEndScrollingAnimation:self];
    }
}

- (UIView *) viewAtLocation:(CGPoint) touchLocation {
    for (UIView *subView in _tabContainerView.subviews)
        if (CGRectContainsPoint(subView.frame, touchLocation))
            return subView;
    return nil;
}

//Scroll View Delegate Animations
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate) {
        M13InfiniteTabBarItem *item = (M13InfiniteTabBarItem *)[self viewAtLocation:CGPointMake((self.frame.size.width / 2.0) + self.contentOffset.x , (self.frame.size.height/2.0) + self.contentOffset.y)];
        if (self.contentOffset.x != (item.frame.origin.x + (item.frame.size.width / 2.0)) - (self.frame.size.width / 2.0)) {
            [self setContentOffset:CGPointMake((item.frame.origin.x + (item.frame.size.width / 2.0)) - (self.frame.size.width / 2.0), 0) animated:YES];
        }
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    M13InfiniteTabBarItem *item = (M13InfiniteTabBarItem *)[self viewAtLocation:CGPointMake((self.frame.size.width / 2.0) + self.contentOffset.x , (self.frame.size.height/2.0) + self.contentOffset.y)];
    if (self.contentOffset.x != (item.frame.origin.x + (item.frame.size.width / 2.0)) - (self.frame.size.width / 2.0)) {
        [self setContentOffset:CGPointMake((item.frame.origin.x + (item.frame.size.width / 2.0)) - (self.frame.size.width / 2.0), 0) animated:YES];
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
    if (!_scrollAnimationCheck) {
        //Update View Controllers
        M13InfiniteTabBarItem *item = (M13InfiniteTabBarItem *)[self viewAtLocation:CGPointMake((self.frame.size.width / 2.0) + self.contentOffset.x , (self.frame.size.height/2.0) + self.contentOffset.y)];
        BOOL shouldUpdate = YES;
        if ([_tabBarDelegate respondsToSelector:@selector(infiniteTabBar:shouldSelectItem:)]) {
            shouldUpdate = [_tabBarDelegate infiniteTabBar:self shouldSelectItem:item];
        }
        
        if (shouldUpdate) {
            [UIView beginAnimations:@"TabChangedAnimation" context:nil];
            [UIView setAnimationDuration:.5];
            [UIView setAnimationDelegate:self];
            
            //Swap Nav controllers
            if ([_tabBarDelegate respondsToSelector:@selector(infiniteTabBar:animateInViewControllerForItem:)]) {
                [_tabBarDelegate infiniteTabBar:self animateInViewControllerForItem:item];
            }
           
            //Change Tabs
            //Set selected highlight tab on every visible tab with tag, and the one in the available array to highlight all icons while scrolling
            [item setSelected:YES];
            M13InfiniteTabBarItem *hiddenItem = [_items objectAtIndex:item.tag];
            [hiddenItem setSelected:YES];
            //Remove highlight on every other tab
            for (M13InfiniteTabBarItem *temp in _items) {
                if (temp.tag != item.tag) {
                    [temp setSelected:NO];
                }
            }
            for (M13InfiniteTabBarItem *temp in _visibleIcons) {
                if (temp.tag != item.tag) {
                    [temp setSelected:NO];
                }
            }
            
            _previousSelectedIndex = item.tag;
            _selectedItem = item;
            
            [UIView setAnimationDidStopSelector:@selector(didSelectItem)];
            
            [UIView commitAnimations];
        } else {
            //Scroll Back to nearest tab with previous index
            M13InfiniteTabBarItem *oldItem = nil;
            for (M13InfiniteTabBarItem *temp in _visibleIcons) {
                if (temp.tag == _previousSelectedIndex) {
                    oldItem = temp;
                }
            }
            if (oldItem == nil) {
                //calculate offset between current center view origin and next previous view origin.
                float offsetX = (_previousSelectedIndex - item.tag) * item.frame.size.width;
                //add this to the current offset
                offsetX += self.contentOffset.x;
                [self setContentOffset:CGPointMake(offsetX, 0) animated:YES];
            } else {
                //Use that view if exists
                [self setContentOffset:CGPointMake((oldItem.frame.origin.x + (oldItem.frame.size.width / 2.0)- (self.frame.size.width / 2.0)), 0) animated:YES];
            }
            _scrollAnimationCheck = YES;
        }
    } else {
        _scrollAnimationCheck = NO;
    }
    
}

//Finished tab change animation
- (void)didSelectItem
{
    if ([_tabBarDelegate respondsToSelector:@selector(infiniteTabBar:didSelectItem:)]) {
        [_tabBarDelegate infiniteTabBar:self didSelectItem:_selectedItem];
    }
}

@end
