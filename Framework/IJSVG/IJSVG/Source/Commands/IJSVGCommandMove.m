//
//  IJSVGCommandMove.m
//  IconJar
//
//  Created by Curtis Hard on 30/08/2014.
//  Copyright (c) 2014 Curtis Hard. All rights reserved.
//

#import "IJSVGCommandLineTo.h"
#import "IJSVGCommandMove.h"

@implementation IJSVGCommandMove

+ (NSInteger)requiredParameterCount
{
    return 2;
}

+ (void)runWithParams:(CGFloat*)params
           paramCount:(NSInteger)count
              command:(IJSVGCommand*)currentCommand
      previousCommand:(IJSVGCommand*)command
                 type:(IJSVGCommandType)type
                 path:(IJSVGPath*)path
{
    // move to's allow more then one move to, but if there are more then one,
    // we need to run the line to instead...who knew!
    if (command.class == self.class && currentCommand.isSubCommand == YES) {
        [IJSVGCommandLineTo runWithParams:params
                               paramCount:count
                                  command:currentCommand
                          previousCommand:command
                                     type:type
                                     path:path];
        return;
    }

    // actual move to command
    if (type == kIJSVGCommandTypeAbsolute) {
        [path.path moveToPoint:NSMakePoint(params[0], params[1])];
        return;
    }
    @try {
        [path.path relativeMoveToPoint:NSMakePoint(params[0], params[1])];
    }
    @catch (NSException* exception) {
        [path.path moveToPoint:NSMakePoint(params[0], params[1])];
    }
}

@end
