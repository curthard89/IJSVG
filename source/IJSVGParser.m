//
//  IJSVGParser.m
//  IconJar
//
//  Created by Curtis Hard on 30/08/2014.
//  Copyright (c) 2014 Curtis Hard. All rights reserved.
//

#import "IJSVGParser.h"

@implementation IJSVGParser

@synthesize viewBox;
@synthesize proposedViewSize;

+ (IJSVGParser *)groupForFileURL:(NSURL *)aURL
{
    return [[self class] groupForFileURL:aURL
                                   error:nil
                                delegate:nil];
}

+ (IJSVGParser *)groupForFileURL:(NSURL *)aURL
                        delegate:(id<IJSVGParserDelegate>)delegate
{
    return [[self class] groupForFileURL:aURL
                                   error:nil
                                delegate:delegate];
}

+ (IJSVGParser *)groupForFileURL:(NSURL *)aURL
                           error:(NSError **)error
                        delegate:(id<IJSVGParserDelegate>)delegate
{
    return [[[[self class] alloc] initWithFileURL:aURL
                                            error:error
                                         delegate:delegate] autorelease];
}

- (void)dealloc
{
    [_glyphs release], _glyphs = nil;
    [super dealloc];
}

- (id)initWithFileURL:(NSURL *)aURL
                error:(NSError **)error
             delegate:(id<IJSVGParserDelegate>)delegate
{
    return [self initWithFileURL:aURL
                        encoding:NSUTF8StringEncoding
                           error:error
                        delegate:delegate];
}

- (id)initWithFileURL:(NSURL *)aURL
             encoding:(NSStringEncoding)encoding
                error:(NSError **)error
             delegate:(id<IJSVGParserDelegate>)delegate
{
    if( ( self = [super init] ) != nil )
    {
        _delegate = delegate;        
        _glyphs = [[NSMutableArray alloc] init];
        
        // load the document / file, assume its UTF8
        NSError * anError = nil;
        NSString * str = [[[NSString alloc] initWithContentsOfURL:aURL
                                                         encoding:encoding
                                                            error:&anError] autorelease];
        
        // error grabbing contents from the file :(
        if( anError != nil )
        {
            *error = [[[NSError alloc] initWithDomain:IJSVGErrorDomain
                                                 code:IJSVGErrorReadingFile
                                             userInfo:nil] autorelease];
            [self release], self = nil;
            return nil;
        }
            
        
        // use NSXMLDocument as its the easiest thing to do on OSX
        anError = nil;
        @try {
            _document = [[NSXMLDocument alloc] initWithXMLString:str
                                                         options:0
                                                           error:&anError];
        }
        @catch (NSException *exception) {
        }
        
        // error parsing the XML document
        if( anError != nil )
        {
            *error = [[[NSError alloc] initWithDomain:IJSVGErrorDomain
                                                 code:IJSVGErrorParsingFile
                                             userInfo:nil] autorelease];
            [_document release], _document = nil;
            [self release], self = nil;
            return nil;
        }
        
        // where the fun begin...
        [self _parse];
        
        anError = nil;
        if( ![self _validateParse:&anError] )
        {
            *error = anError;
            [_document release], _document = nil;
            [self release], self = nil;
            return nil;
        }
        
        // we have actually finished with the document at this point
        // so just get rid of it
        [_document release], _document = nil;
        
    }
    return self;
}

- (BOOL)_validateParse:(NSError **)error
{
    // check is font
    if( self.isFont )
        return YES;
    
    // check the viewbox
    if( NSEqualRects( self.viewBox, NSZeroRect ) )
    {
        if( error != NULL )
            *error = [[[NSError alloc] initWithDomain:IJSVGErrorDomain
                                                 code:IJSVGErrorInvalidViewBox
                                             userInfo:nil] autorelease];
        return NO;
    }
    return YES;
}

- (NSSize)size
{
    return viewBox.size;
}

- (void)_parse
{
    NSXMLElement * svgElement = [_document rootElement];
    
    // find the sizebox!
    NSXMLNode * attribute = nil;
    if( ( attribute = [svgElement attributeForName:@"viewBox"] ) != nil )
    {
        
        // we have a viewbox...
        CGFloat * box = [IJSVGUtils parseViewBox:[attribute stringValue]];
        viewBox = NSMakeRect( box[0], box[1], box[2], box[3]);
        free(box);
        
    } else {
        
        // there is no view box so find the width and height
        CGFloat w = [[[svgElement attributeForName:@"width"] stringValue] floatValue];
        CGFloat h = [[[svgElement attributeForName:@"height"] stringValue] floatValue];
        viewBox = NSMakeRect( 0.f, 0.f, w, h );
    }
    
    CGFloat w = [[[svgElement attributeForName:@"width"] stringValue] floatValue];
    CGFloat h = [[[svgElement attributeForName:@"height"] stringValue] floatValue];
    if( w == 0.f && h == 0.f )
    {
        w = viewBox.size.width;
        h = viewBox.size.height;
    }
    proposedViewSize = NSMakeSize( w, h );
    
    // find foreign objects...
    NSXMLElement * switchElement = nil;
    NSArray * switchElements = [svgElement nodesForXPath:@"switch"
                                                   error:nil];
    if( [switchElements count] != 0 )
    {
        // for performance reasons, ask for this once!
        BOOL handlesShouldHandle = [_delegate respondsToSelector:@selector(svgParser:shouldHandleForeignObject:)];
        BOOL handlesHandle = [_delegate respondsToSelector:@selector(svgParser:handleForeignObject:document:)];
        
        // we have a switch, work out what the objects are...
        switchElement = switchElements[0];
        NSXMLElement * child = nil;
        if( _delegate != nil )
        {
            for( child in [switchElement children] )
            {
                if( [[child name] isEqualToString:@"foreignObject"] )
                {
                    // create the temp foreign object
                    IJSVGForeignObject * foreignObject = [[[IJSVGForeignObject alloc] init] autorelease];
                    
                    // grab the common attributes
                    [self _parseElementForCommonAttributes:child
                                                      node:foreignObject];
                    foreignObject.requiredExtension = [[child attributeForName:@"requiredExtensions"] stringValue];
                    
                    // ask the delegate
                    if( handlesShouldHandle && [_delegate svgParser:self
                                          shouldHandleForeignObject:foreignObject] && handlesHandle )
                    {
                        [_delegate svgParser:self
                         handleForeignObject:foreignObject
                                    document:_document];
                        break;
                    }
                }
            }
        }
        // set the main element to the switch
        svgElement = switchElement;
    }
    
    // the root element is SVG, so iterate over its children
    // recursively
    self.name = svgElement.name;
    [self _parseBlock:svgElement
            intoGroup:self
                  def:NO];
    
}

- (void)_parseElementForCommonAttributes:(NSXMLElement *)element
                                    node:(IJSVGNode *)node
{
    
    // unicode
    NSXMLNode * unicodeAttribute = [element attributeForName:@"unicode"];
    if( unicodeAttribute != nil )
    {
        NSString * str = [unicodeAttribute stringValue];
        node.unicode = [NSString stringWithFormat:@"%04x",[str characterAtIndex:0]];
    }
    
    // x and y
    NSXMLNode * xAttribute = [element attributeForName:@"x"];
    if( xAttribute != nil )
        node.x = [[xAttribute stringValue] floatValue];
    
    NSXMLNode * yAttribute = [element attributeForName:@"y"];
    if( yAttribute )
        node.y = [[yAttribute stringValue] floatValue];
    
    // width
    NSXMLNode * widthAttribute = [element attributeForName:@"width"];
    if( widthAttribute != nil )
    {
        if( [[widthAttribute stringValue] isEqualToString:@"100%"] )
            node.width = self.viewBox.size.width;
        else
            node.width = [IJSVGUtils floatValue:[widthAttribute stringValue]];
    }
    
    // height
    NSXMLNode * heightAttribute = [element attributeForName:@"height"];
    if( heightAttribute != nil )
    {
        if( [[heightAttribute stringValue] isEqualToString:@"100%"] )
            node.height = self.viewBox.size.height;
        else
            node.height = [IJSVGUtils floatValue:[heightAttribute stringValue]];
    }
    
    // any clippath?
    NSXMLNode * clipPathAttribute = [element attributeForName:@"clip-path"];
    if( clipPathAttribute != nil )
    {
        NSString * clipID = [IJSVGUtils defURL:[clipPathAttribute stringValue]];
        if( clipID )
            node.clipPath = (IJSVGGroup *)[node defForID:clipID];
    }
    
    // any mask?
    NSXMLNode * maskAttribute = [element attributeForName:@"mask"];
    if( maskAttribute != nil )
    {
        NSString * maskID = [IJSVGUtils defURL:[maskAttribute stringValue]];
        if( maskID )
            node.clipPath = (IJSVGGroup *)[node defForID:maskID];
    }
    
    // ID
    NSXMLNode * idAttribute = [element attributeForName:@"id"];
    if( idAttribute != nil )
        node.identifier = [idAttribute stringValue];
    
    // transforms
    NSXMLNode * transformAttribute = [element attributeForName:@"transform"];
    if( transformAttribute != nil )
    {
        NSMutableArray * tran = [[[NSMutableArray alloc] init] autorelease];
        [tran addObjectsFromArray:[IJSVGTransform transformsForString:[transformAttribute stringValue]]];
        if( node.transforms != nil )
            [tran addObjectsFromArray:node.transforms];
        node.transforms = tran;
    }
    
    if( node.type == IJSVGNodeTypeMask )
        return;
    
    
#pragma mark Styles
    
    // any line cap style?
    NSXMLNode * lineCapAttribute = [element attributeForName:@"stroke-linecap"];
    if( lineCapAttribute != nil )
        node.lineCapStyle = [IJSVGUtils lineCapStyleForString:[lineCapAttribute stringValue]];
    
    // any line join style?
    NSXMLNode * lineJoinAttribute = [element attributeForName:@"stroke-linejoin"];
    if( lineJoinAttribute != nil )
        node.lineJoinStyle = [IJSVGUtils lineJoinStyleForString:[lineCapAttribute stringValue]];
    
    // work out any extra attributes
    // opacity
    NSXMLNode * opacityAttribute = [element attributeForName:@"opacity"];
    if( opacityAttribute != nil )
        node.opacity = [IJSVGUtils floatValue:[opacityAttribute stringValue]];
    
    NSXMLNode * strokeOpacityAttribute = [element attributeForName:@"stroke-opacity"];
    if( strokeOpacityAttribute != nil )
        node.strokeOpacity = [IJSVGUtils floatValue:[strokeOpacityAttribute stringValue]];
    
    // stroke color
    NSXMLNode * strokeAttribute = [element attributeForName:@"stroke"];
    if( strokeAttribute != nil )
    {
        node.strokeColor = [IJSVGColor colorFromString:[strokeAttribute stringValue]];
        if( node.strokeOpacity != 1.f )
            node.strokeColor = [IJSVGColor changeAlphaOnColor:node.strokeColor
                                                           to:node.strokeOpacity];
    }
    
    // dash node
    NSXMLNode * dashArrayAttribute = [element attributeForName:@"stroke-dasharray"];
    if( dashArrayAttribute != nil )
    {
        NSInteger paramCount = 0;
        CGFloat * params = [IJSVGUtils commandParameters:[dashArrayAttribute stringValue]
                                                   count:&paramCount];
        node.strokeDashArray = params;
        node.strokeDashArrayCount = paramCount;
    }
    
    // dash offset
    NSXMLNode * dashOffsetAttribute = [element attributeForName:@"stroke-dashoffset"];
    if( dashOffsetAttribute != nil )
        node.strokeDashOffset = [[dashOffsetAttribute stringValue] floatValue];
    
    // fill opacity
    NSXMLNode * fillOpacityAttribute = [element attributeForName:@"fill-opacity"];
    if( fillOpacityAttribute != nil )
        node.fillOpacity = [IJSVGUtils floatValue:[fillOpacityAttribute stringValue]];
    
    // fill color
    NSXMLNode * fillAttribute = [element attributeForName:@"fill"];
    if( fillAttribute != nil )
    {
        NSString * defID = [IJSVGUtils defURL:[fillAttribute stringValue]];
        if( defID != nil ) {
            IJSVGGradient * grad = (IJSVGGradient *)[node defForID:defID];
            node.fillGradient = grad;
            node.gradientTransforms = grad.gradientTransforms;
        } else {
            // change the fill color over if its allowed
            node.fillColor = [IJSVGColor colorFromString:[fillAttribute stringValue]];
            if( node.fillOpacity != 1.f )
                node.fillColor = [IJSVGColor changeAlphaOnColor:node.fillColor
                                                             to:node.fillOpacity];
        }
    }
    
    // stroke width
    NSXMLNode * strokeWidthAttribute = [element attributeForName:@"stroke-width"];
    if( strokeWidthAttribute != nil )
        node.strokeWidth = [IJSVGUtils floatValue:[strokeWidthAttribute stringValue]];
    
    
    // gradient transforms
    NSXMLNode * gradTransformAttribute = [element attributeForName:@"gradientTransform"];
    if( gradTransformAttribute != nil )
    {
        NSMutableArray * tran = [[[NSMutableArray alloc] init] autorelease];
        [tran addObjectsFromArray:[IJSVGTransform transformsForString:[gradTransformAttribute stringValue]]];
        if( node.gradientTransforms != nil )
            [tran addObjectsFromArray:node.gradientTransforms];
        node.gradientTransforms = tran;
    }
    
    // winding rule
    NSXMLNode * windingRuleAttribute = [element attributeForName:@"fill-rule"];
    if( windingRuleAttribute != nil )
    {
        node.windingRule = [IJSVGUtils windingRuleForString:[windingRuleAttribute stringValue]];
    } else
        node.windingRule = IJSVGWindingRuleInherit;
    
    // display
    NSXMLNode * displayAttribute = [element attributeForName:@"display"];
    if( [[[displayAttribute stringValue] lowercaseString] isEqualToString:@"none"] )
        node.shouldRender = NO;
 
#pragma mark style sheets
    
    // now we need to work out if there is any style...apparently this is a thing now,
    // people use the style attribute... -_-
    // style
    NSXMLNode * styleNode = [element attributeForName:@"style"];
    if( styleNode != nil )
    {
        IJSVGStyle * style = [IJSVGStyle parseStyleString:[styleNode stringValue]];
        
        // actual display
        NSString * display = nil;
        if( ( display = [style property:@"display"] ) != nil )
        {
            if( [display isEqualToString:@"none"] )
                node.shouldRender = NO;
        }
        
        // fill color
        NSColor * fill = nil;
        if( ( fill = [style property:@"fill"] ) != nil )
        {
            if( [fill isKindOfClass:[NSString class]] )
            {
                NSString * defID = [IJSVGUtils defURL:(NSString *)fill];
                if( defID != nil ) {
                    IJSVGGradient * grad = (IJSVGGradient *)[node defForID:defID];
                    node.fillGradient = grad;
                    node.gradientTransforms = grad.gradientTransforms;
                }
            } else {
                if( [IJSVGColor computeColor:fill] != nil )
                    node.fillColor = fill;
            }
        }
        
        // fill opacity
        NSNumber * num = nil;
        if( ( num = [style property:@"fill-opacity"] ) != nil )
            node.fillOpacity = num.floatValue;
        
        // stroke colour
        NSColor * stroke = nil;
        if( ( stroke = [style property:@"stroke"] ) != nil )
        {
            if( [IJSVGColor computeColor:stroke] )
                node.strokeColor = stroke;
        }
        
        // stroke width
        if( [style property:@"stroke-width"] != 0 )
            node.strokeWidth = [[style property:@"stroke-width"] floatValue];
        
        // line cap style
        if( [style property:@"stroke-linecap"] != nil )
            node.lineCapStyle = [IJSVGUtils lineCapStyleForString:[style property:@"stroke-linecap"]];
        
        // line join style
        if( [style property:@"stroke-linejoin"] != nil )
            node.lineJoinStyle = [IJSVGUtils lineJoinStyleForString:[style property:@"stroke-linejoin"]];
        
        // opacity
        if( [style property:@"opacity"] != nil )
            node.opacity = [[style property:@"opacity"] floatValue];
        
        // stroke opacity
        if( [style property:@"stroke-opacity"] != nil )
            node.strokeOpacity = [[style property:@"stroke-opacity"] floatValue];
        
        // dash
        if( [style property:@"stroke-dasharray"] != nil )
        {
            NSInteger paramCount = 0;
            CGFloat * params = [IJSVGUtils commandParameters:[style property:@"stroke-dasharray"]
                                                       count:&paramCount];
            node.strokeDashArray = params;
            node.strokeDashArrayCount = paramCount;
        }
        
        // dash offset
        if( [style property:@"stroke-dashoffset"] != nil )
            node.strokeDashOffset = [[style property:@"stroke-dashoffset"] floatValue];
        
        // winding rule
        if( [style property:@"fill-rule"] != nil )
            node.windingRule = [IJSVGUtils windingRuleForString:[style property:@"fill-rule"]];
        
    }
    
}

- (BOOL)isFont
{
    return [_glyphs count] != 0;
}

- (NSArray *)glyphs
{
    return _glyphs;
}

- (void)addGlyph:(IJSVGNode *)glyph
{
    [_glyphs addObject:glyph];
}

- (void)_parseBlock:(NSXMLElement *)anElement
          intoGroup:(IJSVGGroup*)parentGroup
                def:(BOOL)flag
{
    for( NSXMLElement * element in [anElement children] )
    {
        NSString * subName = element.name;
        IJSVGNodeType aType = [IJSVGNode typeForString:subName];
        switch( aType )
        {
            default:
            case IJSVGNodeTypeNotFound:
                continue;
                
                // def
            case IJSVGNodeTypeDef: {
                [self _parseBlock:element
                        intoGroup:parentGroup
                              def:YES];
                continue;
            }
                
            // glyph
            case IJSVGNodeTypeGlyph: {
                
                // no path data
                if( [element attributeForName:@"d"] == nil || [[element attributeForName:@"d"] stringValue].length == 0 )
                    continue;
                
                IJSVGPath * path = [[[IJSVGPath alloc] init] autorelease];
                path.type = aType;
                path.name = subName;
                path.parentNode = parentGroup;
                
                // find common attributes
                [self _parseElementForCommonAttributes:element
                                                  node:path];
                
                // pass the commands for it
                [self _parsePathCommandData:[[element attributeForName:@"d"] stringValue]
                                   intoPath:path];
                
                // check the size...
                if( NSIsEmptyRect([path path].controlPointBounds) )
                    continue;
                
                // add the glyph
                [self addGlyph:path];
                continue;
            }
                
                // group
            case IJSVGNodeTypeFont:
            case IJSVGNodeTypeMask:
            case IJSVGNodeTypeGroup: {
                IJSVGGroup * group = [[[IJSVGGroup alloc] init] autorelease];
                group.type = aType;
                group.name = subName;
                group.parentNode = parentGroup;
                
                // find common attributes
                [self _parseElementForCommonAttributes:element
                                                  node:group];
                
                if( !flag )
                    [parentGroup addChild:group];
                
                // recursively parse blocks
                [self _parseBlock:element
                        intoGroup:group
                              def:NO];
                
                // could be defined
                if( flag || [element attributeForName:@"id"] != nil )
                    [parentGroup addDef:group];
                continue;
            }
                
                // path
            case IJSVGNodeTypePath: {
                IJSVGPath * path = [[[IJSVGPath alloc] init] autorelease];
                path.type = aType;
                path.name = subName;
                path.parentNode = parentGroup;
                
                // find common attributes
                [self _parseElementForCommonAttributes:element
                                                  node:path];
                [self _parsePathCommandData:[[element attributeForName:@"d"] stringValue]
                                   intoPath:path];
                
                if( !flag )
                    [parentGroup addChild:path];
                
                // could be defined
                if( flag || [element attributeForName:@"id"] != nil )
                    [parentGroup addDef:path];
                continue;
            }
                
                // polygon
            case IJSVGNodeTypePolygon: {
                IJSVGPath * path = [[[IJSVGPath alloc] init] autorelease];
                path.type = aType;
                path.name = subName;
                path.parentNode = parentGroup;
                
                // find common attributes
                [self _parseElementForCommonAttributes:element
                                                  node:path];
                [self _parsePolygon:element
                           intoPath:path];
                
                if( !flag )
                    [parentGroup addChild:path];
                
                // could be defined
                if( flag || [element attributeForName:@"id"] != nil )
                    [parentGroup addDef:path];
                continue;
            }
                
                // polyline
            case IJSVGNodeTypePolyline: {
                IJSVGPath * path = [[[IJSVGPath alloc] init] autorelease];
                path.type = aType;
                path.name = subName;
                path.parentNode = parentGroup;
                
                // find common attributes
                [self _parseElementForCommonAttributes:element
                                                  node:path];
                [self _parsePolyline:element
                            intoPath:path];
                
                if( !flag )
                    [parentGroup addChild:path];
                
                // could be defined
                if( flag || [element attributeForName:@"id"] != nil )
                    [parentGroup addDef:path];
                continue;
            }
                
                // rect
            case IJSVGNodeTypeRect: {
                IJSVGPath * path = [[[IJSVGPath alloc] init] autorelease];
                path.type = aType;
                path.name = subName;
                path.parentNode = parentGroup;
                
                // find common attributes
                [self _parseRect:element
                        intoPath:path];
                
                [self _parseElementForCommonAttributes:element
                                                  node:path];
                
                if( !flag )
                    [parentGroup addChild:path];
                
                // could be defined
                if( flag || [element attributeForName:@"id"] != nil )
                    [parentGroup addDef:path];
                continue;
            }
                
                // line
            case IJSVGNodeTypeLine: {
                IJSVGPath * path = [[[IJSVGPath alloc] init] autorelease];
                path.type = aType;
                path.name = subName;
                path.parentNode = parentGroup;
                
                // find common attributes
                [self _parseElementForCommonAttributes:element
                                                  node:path];
                [self _parseLine:element
                        intoPath:path];
                [parentGroup addChild:path];
                
                // could be defined
                if( flag || [element attributeForName:@"id"] != nil )
                    [parentGroup addDef:path];
                continue;
            }
                
                // circle
            case IJSVGNodeTypeCircle: {
                IJSVGPath * path = [[[IJSVGPath alloc] init] autorelease];
                path.type = aType;
                path.name = subName;
                path.parentNode = parentGroup;
                
                // find common attributes
                [self _parseElementForCommonAttributes:element
                                                  node:path];
                [self _parseCircle:element
                          intoPath:path];
                
                if( !flag )
                    [parentGroup addChild:path];
                
                // could be defined
                if( flag || [element attributeForName:@"id"] != nil)
                    [parentGroup addDef:path];
                continue;
            }
                
                // ellipse
            case IJSVGNodeTypeEllipse: {
                IJSVGPath * path = [[[IJSVGPath alloc] init] autorelease];
                path.type = aType;
                path.name = subName;
                path.parentNode = parentGroup;
                
                // find common attributes
                [self _parseElementForCommonAttributes:element
                                                  node:path];
                [self _parseEllipse:element
                           intoPath:path];
                
                if( !flag )
                    [parentGroup addChild:path];
                
                // could be defined
                if( flag || [element attributeForName:@"id"] != nil )
                    [parentGroup addDef:path];
                continue;
            }
                
                // use
            case IJSVGNodeTypeUse: {
                
                NSString * xlink = [[element attributeForName:@"xlink:href"] stringValue];
                NSString * xlinkID = [xlink substringFromIndex:1];
                IJSVGNode * node = [parentGroup defForID:xlinkID];
                
                // could be an alias, aswell as a def...
                if( [element attributeForName:@"id"] != nil )
                {
                    IJSVGNode * theNode = [[node copy] autorelease];
                    theNode.parentNode = parentGroup;
                    
                    // grab common attributes
                    [self _parseElementForCommonAttributes:element
                                                      node:theNode];
                    
                    // add them
                    [parentGroup addDef:theNode];
                    [parentGroup addChild:theNode];
                    continue;
                }
                
                if( node != nil )
                {
                    // copy the node
                    node = [[node copy] autorelease];
                    node.parentNode = parentGroup;
                    
                    // grab the common attributes
                    [self _parseElementForCommonAttributes:element
                                                      node:node];
                    [parentGroup addChild:node];
                }
                continue;
            }
                
                // linear gradient
            case IJSVGNodeTypeLinearGradient: {
                
                NSString * xlink = [[element attributeForName:@"xlink:href"] stringValue];
                NSString * xlinkID = [xlink substringFromIndex:1];
                IJSVGNode * node = [parentGroup defForID:xlinkID];
                if( node != nil )
                {
                    // we are a clone
                    IJSVGLinearGradient * grad = [[[IJSVGLinearGradient alloc] init] autorelease];
                    grad.type = aType;
                    [grad applyPropertiesFromNode:node];
                    grad.gradient = [[[(IJSVGGradient *)node gradient] copy] autorelease];
                    [IJSVGLinearGradient parseGradient:element
                                              gradient:grad];
                    [self _parseElementForCommonAttributes:element
                                                      node:grad];
                    [parentGroup addDef:grad];
                    continue;
                }
                
                IJSVGLinearGradient * gradient = [[[IJSVGLinearGradient alloc] init] autorelease];
                gradient.type = aType;
                gradient.gradient = [IJSVGLinearGradient parseGradient:element
                                                              gradient:gradient];
                [self _parseElementForCommonAttributes:element
                                                  node:gradient];
                [parentGroup addDef:gradient];
                continue;
            }
                
                // radial gradient
            case IJSVGNodeTypeRadialGradient: {
                
                NSString * xlink = [[element attributeForName:@"xlink:href"] stringValue];
                NSString * xlinkID = [xlink substringFromIndex:1];
                IJSVGNode * node = [parentGroup defForID:xlinkID];
                if( node != nil )
                {
                    // we are a clone
                    IJSVGRadialGradient * grad = [[[IJSVGRadialGradient alloc] init] autorelease];
                    grad.type = aType;
                    [grad applyPropertiesFromNode:node];
                    grad.gradient = [[[(IJSVGGradient *)node gradient] copy] autorelease];
                    [IJSVGRadialGradient parseGradient:element
                                              gradient:grad];
                    [self _parseElementForCommonAttributes:element
                                                      node:grad];
                    [parentGroup addDef:grad];
                    continue;
                }
                
                IJSVGRadialGradient * gradient = [[[IJSVGRadialGradient alloc] init] autorelease];
                gradient.type = aType;
                gradient.gradient = [IJSVGRadialGradient parseGradient:element
                                                              gradient:gradient];
                [self _parseElementForCommonAttributes:element
                                                  node:gradient];
                [parentGroup addDef:gradient];
                continue;
            }
                
                // clippath
            case IJSVGNodeTypeClipPath: {
                
                IJSVGGroup * group = [[[IJSVGGroup alloc] init] autorelease];
                group.type = aType;
                group.name = subName;
                group.parentNode = parentGroup;
                
                // find common attributes
                [self _parseElementForCommonAttributes:element
                                                  node:group];
                
                // recursively parse blocks
                [self _parseBlock:element
                        intoGroup:group
                              def:NO];
                
                // add it as a def
                [parentGroup addDef:group];
            }
                
        }
    }
}

static NSCharacterSet * _commandCharSet = nil;

+ (NSCharacterSet *)_commandCharSet
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _commandCharSet = [[NSCharacterSet characterSetWithCharactersInString:@"MmZzLlHhVvCcSsQqTtAa"] retain];
    });
    return _commandCharSet;
}

#pragma mark Parser stuff!

- (void)_parsePathCommandData:(NSString *)command
                     intoPath:(IJSVGPath *)path
{
    // invalid command
    
    if( command == nil || command.length == 0 )
        return;
    
    NSCharacterSet * set = [[self class] _commandCharSet];
    NSUInteger len = [command length];
    
    // allocate memory for the string buffer for reading
    unichar * buffer = (unichar *)calloc( len+1, sizeof(unichar));
    [command getCharacters:buffer
                     range:NSMakeRange(0, len)];
    
    NSString * currentCommandString = nil;
    NSString * previousCommand = nil;
    
    unichar * commandBuffer = NULL;
    int defaultBufferSize = 200;
    int currentBufferSize = 0;
    int currentSize = defaultBufferSize;
    
    for( int i = 0; i < len; i++ )
    {
        unichar currentChar = buffer[i];
        BOOL atEnd = i == len-1;
        if( [set characterIsMember:currentChar] || atEnd )
        {
            // we are at the end, make sure we have a buffer...
            if( atEnd )
            {
                if( commandBuffer == NULL )
                    commandBuffer = (unichar *)malloc(sizeof(unichar)*defaultBufferSize);
                commandBuffer[currentBufferSize++] = currentChar;
            }
            
            // if we have a buffer then add it to the parse command list
            if( commandBuffer != NULL )
            {
                // copy the characters from the buffer into a smaller accurate char buffer
                currentCommandString = [NSString stringWithCharacters:commandBuffer
                                                               length:currentBufferSize];
                
                // parse the command
                [self _parseCommandString:currentCommandString
                          previousCommand:previousCommand
                                 intoPath:path];
                previousCommand = [[currentCommandString copy] autorelease];
                
                // free the memory used by this command and reset
                // any temp counters we have been using
                free(commandBuffer);
                commandBuffer = NULL;
                currentBufferSize = 0;
                currentSize = defaultBufferSize;
            }
            
            // make sure we only allocate the memory if we are not the last character
            if( !atEnd )
                commandBuffer = (unichar *)malloc(sizeof(unichar)*defaultBufferSize);
            else
                break;
        }
        
        // add the buffer char to the command buffer
        if( ( currentBufferSize + 1 ) == currentSize )
        {
            currentSize += defaultBufferSize;
            commandBuffer = (unichar *)realloc( commandBuffer, sizeof(unichar)*currentSize);
        }
        
        // append the char
        if( commandBuffer != NULL )
            commandBuffer[currentBufferSize++] = currentChar;
    }
    
    // free the buffer
    free(buffer);
}

- (void)_parseCommandString:(NSString *)string
            previousCommand:(NSString *)previous
                   intoPath:(IJSVGPath *)path
{
    // work out the last command - the reason this is so long is because the command
    // could be a series of the same commands, so work it out by the number of parameters
    // there is per command string
    @autoreleasepool {
        IJSVGCommand * preCommand = nil;
        if( previous != nil )
        {
            IJSVGCommand * pre = [[[IJSVGCommand alloc] initWithCommandString:previous] autorelease];
            preCommand = (IJSVGCommand *)[[pre subCommands] lastObject];
        }
        
        // main commands
        IJSVGCommand * command = [[[IJSVGCommand alloc] initWithCommandString:string] autorelease];
        for( IJSVGCommand * subCommand in [command subCommands] )
        {
            [subCommand.commandClass runWithParams:subCommand.parameters
                                        paramCount:subCommand.parameterCount
                                           command:subCommand
                                   previousCommand:preCommand
                                              type:subCommand.type
                                              path:path];
            preCommand = subCommand;
        }
    }
}

- (void)_parseLine:(NSXMLElement *)element
          intoPath:(IJSVGPath *)path
{
    // convert a line into a command,
    // basically MX1 Y1LX2 Y2
    CGFloat x1 = [[[element attributeForName:@"x1"] stringValue] floatValue];
    CGFloat y1 = [[[element attributeForName:@"y1"] stringValue] floatValue];
    CGFloat x2 = [[[element attributeForName:@"x2"] stringValue] floatValue];
    CGFloat y2 = [[[element attributeForName:@"y2"] stringValue] floatValue];
    
    // use sprintf as its quicker then stringWithFormat...
    char buffer[50];
    sprintf( buffer, "M%.2f %.2fL%.2f %.2f",x1,y1,x2,y2);
    NSString * command = [NSString stringWithCString:buffer
                                            encoding:NSUTF8StringEncoding];
    [self _parsePathCommandData:command
                       intoPath:path];
}

- (void)_parseCircle:(NSXMLElement *)element
            intoPath:(IJSVGPath *)path
{
    CGFloat cX = [[[element attributeForName:@"cx"] stringValue] floatValue];
    CGFloat cY = [[[element attributeForName:@"cy"] stringValue] floatValue];
    CGFloat r = [[[element attributeForName:@"r"] stringValue] floatValue];
    NSRect rect = NSMakeRect( cX - r, cY - r, r*2, r*2);
    [path overwritePath:[NSBezierPath bezierPathWithOvalInRect:rect]];
}

- (void)_parseEllipse:(NSXMLElement *)element
             intoPath:(IJSVGPath *)path
{
    CGFloat cX = [[[element attributeForName:@"cx"] stringValue] floatValue];
    CGFloat cY = [[[element attributeForName:@"cy"] stringValue] floatValue];
    CGFloat rX = [[[element attributeForName:@"rx"] stringValue] floatValue];
    CGFloat rY = [[[element attributeForName:@"ry"] stringValue] floatValue];
    NSRect rect = NSMakeRect( cX-rX, cY-rY, rX*2, rY*2);
    [path overwritePath:[NSBezierPath bezierPathWithOvalInRect:rect]];
}

- (void)_parsePolyline:(NSXMLElement *)element
              intoPath:(IJSVGPath *)path
{
    [self _parsePoly:element
            intoPath:path
           closePath:NO];
}

- (void)_parsePolygon:(NSXMLElement *)element
             intoPath:(IJSVGPath *)path
{
    [self _parsePoly:element
            intoPath:path
           closePath:YES];
}

- (void)_parsePoly:(NSXMLElement *)element
          intoPath:(IJSVGPath *)path
         closePath:(BOOL)closePath
{
    NSString * points = [[element attributeForName:@"points"] stringValue];
    NSInteger count = 0;
    CGFloat * params = [IJSVGUtils commandParameters:points
                                               count:&count];
    if( (count % 2) != 0 )
    {
        // error occured, free the params
        free(params);
        return;
    }
    
    // construct a command
    NSMutableString * str = [[[NSMutableString alloc] init] autorelease];
    [str appendFormat:@"M%f %f L",params[0],params[1]];
    for( NSInteger i = 2; i < count; i+=2 )
    {
        [str appendFormat:@"%f %f ",params[i],params[i+1]];
    }
    if( closePath )
        [str appendString:@"z"];
    [self _parsePathCommandData:str
                       intoPath:path];
    free(params);
    
}

- (void)_parseRect:(NSXMLElement *)element
          intoPath:(IJSVGPath *)path
{
    
    CGFloat aX = [[[element attributeForName:@"x"] stringValue] floatValue];
    CGFloat aY = [[[element attributeForName:@"y"] stringValue] floatValue];
    
    CGFloat aWidth = [IJSVGUtils floatValue:[[element attributeForName:@"width"] stringValue]
                         fallBackForPercent:self.viewBox.size.width];
    CGFloat aHeight = [IJSVGUtils floatValue:[[element attributeForName:@"height"] stringValue]
                          fallBackForPercent:self.viewBox.size.width];
    
    CGFloat rX = [[[element attributeForName:@"rx"] stringValue] floatValue];
    CGFloat rY = [[[element attributeForName:@"ry"] stringValue] floatValue];
    if( [element attributeForName:@"ry"] == nil )
        rY = rX;
    
    [element removeAttributeForName:@"x"];
    [element removeAttributeForName:@"y"];
    [element removeAttributeForName:@"width"];
    [element removeAttributeForName:@"height"];
    [path overwritePath:[NSBezierPath bezierPathWithRoundedRect:NSMakeRect( aX, aY, aWidth, aHeight)
                                                        xRadius:rX
                                                        yRadius:rY]];
}

@end