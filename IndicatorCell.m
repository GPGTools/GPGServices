//
//  IndicatorCell.m
//  GPGServices
//
//  Created by Moritz Ulrich on 13.07.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "IndicatorCell.h"

#import <Cocoa/Cocoa.h>

@implementation IndicatorCell

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _color = [[NSColor redColor] retain];
    }
    return self;
}

- (void)dealloc {
    [_color release];
    [super dealloc];
}

- (void)setObjectValue:(id<NSCopying>)obj {
    [_color release];
    _color = [obj copyWithZone:nil];
    
    [(NSControl *)[self controlView] updateCell:self];
}

- (id)objectValue {
    return _color;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if(_color) {
        CGFloat sidelength = MIN(cellFrame.size.height, cellFrame.size.width);
        NSRect rect = NSMakeRect(cellFrame.origin.x, cellFrame.origin.y, 
                                 sidelength, sidelength);
        NSBezierPath* path = [NSBezierPath bezierPathWithOvalInRect:rect];
        [path setLineWidth:1];
        [_color set];
        [[NSColor blackColor] setStroke];
        [path fill];
        [path stroke];
    }
}

@end
