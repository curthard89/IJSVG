//
//  IJSVGNode.h
//  IconJar
//
//  Created by Curtis Hard on 30/08/2014.
//  Copyright (c) 2014 Curtis Hard. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IJSVGStyle.h"

@class IJSVGDef;
@class IJSVGGradient;

typedef NS_OPTIONS( NSInteger, IJSVGNodeType ) {
    IJSVGNodeTypeGroup,
    IJSVGNodeTypePath,
    IJSVGNodeTypeDef,
    IJSVGNodeTypePolygon,
    IJSVGNodeTypePolyline,
    IJSVGNodeTypeRect,
    IJSVGNodeTypeLine,
    IJSVGNodeTypeCircle,
    IJSVGNodeTypeEllipse,
    IJSVGNodeTypeUse,
    IJSVGNodeTypeLinearGradient,
    IJSVGNodeTypeRadialGradient,
    IJSVGNodeTypeNotFound
};

typedef NS_OPTIONS( NSInteger, IJSVGWindingRule ) {
    IJSVGWindingRuleNonZero,
    IJSVGWindingRuleEvenOdd,
    IJSVGWindingRuleInherit
};

static CGFloat IJSVGInheritedFloatValue = -99.9999991;

@interface IJSVGNode : NSObject <NSCopying> {
    
    IJSVGNodeType type;
    NSString * name;
    
    CGFloat x;
    CGFloat y;
    CGFloat width;
    CGFloat height;
    
    IJSVGGradient * fillGradient;
    
    NSColor * fillColor;
    NSColor * strokeColor;
    
    CGFloat opacity;
    CGFloat strokeWidth;
    CGFloat fillOpacity;
    CGFloat strokeOpacity;
    
    NSString * identifier;
    
    IJSVGNode * parentNode;
    NSArray * transforms;
    
    IJSVGWindingRule windingRule;
    
    IJSVGDef * def;
    
}

@property ( nonatomic, assign ) IJSVGNodeType type;
@property ( nonatomic, copy ) NSString * name;
@property ( nonatomic, assign ) CGFloat x;
@property ( nonatomic, assign ) CGFloat y;
@property ( nonatomic, assign ) CGFloat width;
@property ( nonatomic, assign ) CGFloat height;
@property ( nonatomic, assign ) CGFloat opacity;
@property ( nonatomic, assign ) CGFloat fillOpacity;
@property ( nonatomic, assign ) CGFloat strokeOpacity;
@property ( nonatomic, assign ) CGFloat strokeWidth;
@property ( nonatomic, retain ) NSColor * fillColor;
@property ( nonatomic, retain ) NSColor * strokeColor;
@property ( nonatomic, copy ) NSString * identifier;
@property ( nonatomic, assign ) IJSVGNode * parentNode;
@property ( nonatomic, assign ) IJSVGWindingRule windingRule;
@property ( nonatomic, retain ) NSArray * transforms;
@property ( nonatomic, retain ) IJSVGDef * def;
@property ( nonatomic, retain ) IJSVGGradient * fillGradient;

+ (IJSVGNodeType)typeForString:(NSString *)string;

- (id)initWithDef:(BOOL)flag;
- (void)addDef:(IJSVGNode *)aDef;
- (IJSVGDef *)defForID:(NSString *)anID;

@end