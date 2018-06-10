/****************************************************************************
 ** Copyright (C) 2004-2017 Mazatech S.r.l. All rights reserved.
 **
 ** This file is part of AmanithVG software, an OpenVG implementation.
 **
 ** Khronos and OpenVG are trademarks of The Khronos Group Inc.
 ** OpenGL is a registered trademark and OpenGL ES is a trademark of
 ** Silicon Graphics, Inc.
 **
 ** This file is provided AS IS with NO WARRANTY OF ANY KIND, INCLUDING THE
 ** WARRANTY OF DESIGN, MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
 **
 ** For any information, please contact info@mazatech.com
 **
 ****************************************************************************/
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CVDisplayLink.h>
#import <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <time.h>
#include <sys/time.h>

#include <VG/openvg.h>
#include <VG/vgu.h>
#include <VG/vgext.h>

#include "input.h"

// WeeKit handler functions
typedef void (*WKSizeHandler)(int, int);
typedef void (*WKDrawHandler)(int, int);
typedef void (*WKEventHandler)(short, short, int);
typedef void (*WKTickHandler)();

// Handler pointers
WKSizeHandler wkSizeHandler;
WKDrawHandler wkDrawHandler;
WKEventHandler wkEventHandler;
WKTickHandler wkTickHandler;

// default window dimensions
#define INITIAL_WINDOW_WIDTH 800
#define INITIAL_WINDOW_HEIGHT 480

/*****************************************************************
 View (interface)
 *****************************************************************/
@interface WKView : NSOpenGLView <NSWindowDelegate> {
  void *vgContext; 			// OpenVG context
  void *vgWindowSurface; 		// OpenVG surface
  CVDisplayLinkRef displayLink; 	// a Core Video display link
}
@end

/*****************************************************************
 View (implementation)
 *****************************************************************/
@implementation WKView

#define KEYCODE_MAX 256
static int k[KEYCODE_MAX];

+ (void) initialize {
  for (int i = 0; i < KEYCODE_MAX; i++) {
    k[i] = -1;
  }
  k[0] = KEY_A;
  k[49] = KEY_SPACE;
  k[123] = KEY_LEFT;
  k[124] = KEY_RIGHT;
  k[125] = KEY_DOWN;
  k[126] = KEY_UP;
}

/*****************************************************************
 OpenVG
 *****************************************************************/
- (VGboolean) openvgInit :(const VGuint)width :(const VGuint)height {

  // create an OpenVG context
  vgContext = vgPrivContextCreateMZT(NULL);
  if (!vgContext) {
    return VG_FALSE;
  }

  // create a window surface (sRGBA premultiplied color space)
  vgWindowSurface = vgPrivSurfaceCreateMZT(width, height, VG_FALSE, VG_TRUE, VG_TRUE);
  if (!vgWindowSurface) {
    vgPrivContextDestroyMZT(vgContext);
    return VG_FALSE;
  }

  // bind context and surface
  if (vgPrivMakeCurrentMZT(vgContext, vgWindowSurface) == VG_FALSE) {
    vgPrivSurfaceDestroyMZT(vgWindowSurface);
    vgPrivContextDestroyMZT(vgContext);
    return VG_FALSE;
  }

  return VG_TRUE;
}

- (void) openvgDestroy {
  // unbind context and surface
  vgPrivMakeCurrentMZT(NULL, NULL);
  // destroy OpenVG surface
  vgPrivSurfaceDestroyMZT(vgWindowSurface);
  // destroy OpenVG context
  vgPrivContextDestroyMZT(vgContext);
}

// get the width of OpenVG drawing surface, in pixels
- (VGint) openvgSurfaceWidthGet {
  return vgPrivGetSurfaceWidthMZT(vgWindowSurface);
}

// get the height of OpenVG drawing surface, in pixels
- (VGint) openvgSurfaceHeightGet {
  return vgPrivGetSurfaceHeightMZT(vgWindowSurface);
}

// get the maximum surface dimension supported by the OpenVG backend
- (VGint) openvgSurfaceMaxDimensionGet {
  return vgPrivSurfaceMaxDimensionGetMZT();
}

// utility functions
- (VGuint) getTimeMS {

  struct timeval tp;
  struct timezone tzp;
  gettimeofday(&tp, &tzp);
  return (VGuint)((tp.tv_sec * 1000) + (tp.tv_usec / 1000));
}

// Core Video display link
- (CVReturn)getFrameForTime :(const CVTimeStamp *)outputTime {

  // deltaTime is unused in this application, but here's how to calculate it using display link info
  // double deltaTime = 1.0 / (outputTime->rateScalar * (double)outputTime->videoTimeScale / (double)outputTime->videoRefreshPeriod);
  (void)outputTime;

  // there is no autorelease pool when this method is called because it will be called from a background thread
  // it's important to create one or app can leak objects
  @autoreleasepool {
    [self drawRect:[self bounds]];
  }

  return kCVReturnSuccess;
}

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                    const CVTimeStamp* now,
                                    const CVTimeStamp* outputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags* flagsOut,
                                    void* displayLinkContext) {
  CVReturn result = [(__bridge WKView*)displayLinkContext getFrameForTime:outputTime];
  return result;
}

// implementation of NSOpenGLView methods
- (id) initWithFrame :(NSRect)frameRect {

  NSOpenGLPixelFormatAttribute attributes[] = {
    NSOpenGLPFAAccelerated,
    NSOpenGLPFANoRecovery,
    NSOpenGLPFADoubleBuffer,
    NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersionLegacy,
    NSOpenGLPFAColorSize, 32,
    // AmanithVG GLE
    NSOpenGLPFASupersample,
    NSOpenGLPFADepthSize, 24,
    NSOpenGLPFAStencilSize, 8,
    NSOpenGLPFASampleBuffers, 1,
    NSOpenGLPFASamples, 8,
    (NSOpenGLPixelFormatAttribute)0
  };
  NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];

  if (!format) {
    NSLog(@"Unable to create pixel format.");
    exit(EXIT_FAILURE);
  }

  self = [super initWithFrame: frameRect pixelFormat: format];
  [format release];

  // initialize private members
  vgContext = NULL;
  vgWindowSurface = NULL;
  return self;
}

- (void) prepareOpenGL {

  [super prepareOpenGL];

  // the reshape function may have changed the thread to which our OpenGL
  // context is attached before prepareOpenGL and initGL are called.  So call
  // makeCurrentContext to ensure that our OpenGL context current to this
  // thread (i.e. makeCurrentContext directs all OpenGL calls on this thread
  // to [self openGLContext])
  [[self openGLContext] makeCurrentContext];

  // do not synchronize buffer swaps with vertical refresh rate
  GLint swapInt = 0;
  [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];

  // get frame dimensions
  NSSize bound = [self frame].size;
  VGint width = (VGint)bound.width;
  VGint height = (VGint)bound.height;

  // init OpenVG
  if ([self openvgInit :width :height]) {
  }
  else {
    NSLog(@"Unable to initialize AmanithVG.");
    exit(EXIT_FAILURE);
  }

  // create a display link capable of being used with all active displays
  CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);

  // set the renderer output callback function
  CVDisplayLinkSetOutputCallback(displayLink, &displayLinkCallback, (__bridge void*)self);

  // set the display link for the current renderer
  CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
  CGLPixelFormatObj cglPixelFormat = [[self pixelFormat] CGLPixelFormatObj];
  CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink, cglContext, cglPixelFormat);

  // activate the display link
  CVDisplayLinkStart(displayLink);
}

- (void) drawRect :(NSRect)dirtyRect {

  if ([self lockFocusIfCanDraw]) {
    
    [[self openGLContext] makeCurrentContext];

    // we draw on a secondary thread through the display link when resizing the view, -reshape is called automatically on the main thread
    // add a mutex around to avoid the threads accessing the context simultaneously when resizing
    CGLLockContext([[self openGLContext] CGLContextObj]);

    // draw OpenVG content
    wkDrawHandler([self openvgSurfaceWidthGet], [self openvgSurfaceHeightGet]);

    // copy a double-buffered context’s back buffer to its front buffer
    CGLFlushDrawable([[self openGLContext] CGLContextObj]);

    // acknowledge AmanithVG that we have performed a swapbuffers
    vgPostSwapBuffersMZT();

    // unlock the context
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
    [self unlockFocus];
  }
}

// this method is called whenever the window/control is reshaped, it is also called when the control is first opened
- (void) reshape {

  [super reshape];

  if ([self lockFocusIfCanDraw]) {

    [[self openGLContext] makeCurrentContext];

    // we draw on a secondary thread through the display link, however, when resizing the view, -drawRect is called on the main thread
    // add a mutex around to avoid the threads accessing the context simultaneously when resizing
    CGLLockContext([[self openGLContext] CGLContextObj]);

    // get new dimensions
    NSSize bound = [self frame].size;

    // resize AmanithVG drawing surface
    vgPrivSurfaceResizeMZT(vgWindowSurface, (VGint)bound.width, (VGint)bound.height);
    VGint surfaceWidth = [self openvgSurfaceWidthGet];
    VGint surfaceHeight = [self openvgSurfaceHeightGet];
	
    // resize drawing surface
    wkSizeHandler([self openvgSurfaceWidthGet], [self openvgSurfaceHeightGet]);

    // unlock the context
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
    [self unlockFocus];
  }
}

- (void) dealloc {

  // stop the display link BEFORE releasing anything in the view
  // otherwise the display link thread may call into the view and crash
  // when it encounters something that has been release
  CVDisplayLinkStop(displayLink);

  // release the display link
  CVDisplayLinkRelease(displayLink);

  // destroy OpenVG context and surface
  [self openvgDestroy];

  [super dealloc];
}

// mouse and keyboard events
- (void) mouseDown: (NSEvent *)theEvent {

  NSPoint p;

  // convert window location into view location
  p = [theEvent locationInWindow];
  p = [self convertPoint: p fromView: nil];
  p.y = self.frame.size.height - p.y;

  int x = (int) p.x;
  int y = (int) p.y;

  wkEventHandler(EV_ABS, ABS_MT_SLOT, 0);
  wkEventHandler(EV_ABS, ABS_MT_TRACKING_ID, 1);
  wkEventHandler(EV_ABS, ABS_MT_POSITION_X, x);
  wkEventHandler(EV_ABS, ABS_MT_POSITION_Y, y);
  wkEventHandler(EV_KEY, 330, 1);
  wkEventHandler(EV_ABS, ABS_X, x);
  wkEventHandler(EV_ABS, ABS_Y, y);
  wkEventHandler(EV_SYN, SYN_REPORT, 0);
}

- (void) mouseUp: (NSEvent *)theEvent {
  wkEventHandler(EV_ABS, ABS_MT_TRACKING_ID, -1);
  wkEventHandler(EV_KEY, 330, 0);
  wkEventHandler(EV_SYN, SYN_REPORT, 0);
}

- (void) mouseDragged:(NSEvent *)theEvent {

  NSPoint p;

  // convert window location into view location
  p = [theEvent locationInWindow];
  p = [self convertPoint: p fromView: nil];
  p.y = self.frame.size.height - p.y;

  int x = (int) p.x;
  int y = (int) p.y;

  wkEventHandler(EV_ABS, ABS_MT_POSITION_X, x);
  wkEventHandler(EV_ABS, ABS_MT_POSITION_Y, y);
  wkEventHandler(EV_ABS, ABS_X, x);
  wkEventHandler(EV_ABS, ABS_Y, y);
  wkEventHandler(EV_SYN, SYN_REPORT, 0);
}

- (void) keyDown:(NSEvent *)theEvent {
  //NSLog(@"keyDown: %@", theEvent);
  [self handleKey:(NSEvent *) theEvent down:true];
}

- (void) handleKey:(NSEvent *) theEvent down:(bool) down {
  char *chars = (char *)[[theEvent characters] cStringUsingEncoding: NSMacOSRomanStringEncoding];

  int c = theEvent.keyCode;
  if (c < KEYCODE_MAX) {
    unsigned key = k[c];
    if (key != -1) {
      wkEventHandler(EV_KEY, key, down * (1 + theEvent.isARepeat));
	  return;
    }
  }
  NSLog(@"unhandled %d", theEvent.keyCode);
}

- (void) keyUp:(NSEvent *)theEvent {
  // NSLog(@"keyUp: %@", theEvent);
  [self handleKey:(NSEvent *) theEvent down:false];
}

- (void) flagsChanged:(NSEvent *)theEvent {
  // NSLog(@"flagsChanged: %@", theEvent);
}


- (BOOL) acceptsFirstResponder {

  // as first responder, the receiver is the first object in the responder chain to be sent key events and action messages
  return YES;
}

- (BOOL) becomeFirstResponder {

  return YES;
}

- (BOOL) resignFirstResponder {

  return YES;
}

- (BOOL) isFlipped {

  return NO;
}

// menu handlers
- (void) applicationTerminate :(id)sender {
  [[NSApplication sharedApplication] stop:sender];
}

// from NSWindowDelegate
- (void)windowWillClose:(NSNotification *)note {

  (void)note;

  // Stop the display link when the window is closing because default
  // OpenGL render buffers will be destroyed. If display link continues to
  // fire without renderbuffers, OpenGL draw calls will set errors.
  CVDisplayLinkStop(displayLink);
}

@end

/*****************************************************************
 Main
 *****************************************************************/
void applicationMenuPopulate(NSMenu* subMenu) {
  // quit application
  NSMenuItem* menuItem = [subMenu addItemWithTitle:[NSString stringWithFormat:@"%@", NSLocalizedString(@"Quit", nil)] action:@selector(stop:) keyEquivalent:@"q"];
  [menuItem setTarget:[NSApplication sharedApplication]];
}

void mainMenuPopulate(WKView* view) {

  NSMenuItem* menuItem;
  NSMenu* subMenu;
  // create main menu = menu bar
  NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

  // the titles of the menu items are for identification purposes only and shouldn't be localized; the strings in the menu bar come
  // from the submenu titles, except for the application menu, whose title is ignored at runtime
  menuItem = [mainMenu addItemWithTitle:@"Apple" action:NULL keyEquivalent:@""];
  subMenu = [[NSMenu alloc] initWithTitle:@"Apple"];
  [NSApp performSelector:@selector(setAppleMenu:) withObject:subMenu];
  applicationMenuPopulate(subMenu);
  [mainMenu setSubmenu:subMenu forItem:menuItem];
  [NSApp setMainMenu:mainMenu];
}

void applicationMenuCreate(WKView* view) {
  mainMenuPopulate(view);
}

int WKMain(WKSizeHandler sizeHandler,
	   WKDrawHandler drawHandler, 
           WKEventHandler eventHandler,
           WKTickHandler tickHandler) {
  wkSizeHandler = sizeHandler;
  wkDrawHandler = drawHandler;
  wkEventHandler = eventHandler;
  wkTickHandler = tickHandler;

  @autoreleasepool {

    NSRect frame = NSMakeRect(0, 0, INITIAL_WINDOW_WIDTH, INITIAL_WINDOW_HEIGHT);

    // get application
    NSApplication* app = [NSApplication sharedApplication];
    [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];

    NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];

    // create the window
    NSWindow* window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer: TRUE];
    [window setAcceptsMouseMovedEvents:YES];
    [window setTitle: appName];

    // create the OpenGL view
    WKView* view = [[WKView alloc] initWithFrame: frame];

    // link the view to the window
    [window setDelegate: view];
    [window setContentView: view];
    [window makeFirstResponder: view];
    [window setMaxSize: NSMakeSize([view openvgSurfaceMaxDimensionGet], [view openvgSurfaceMaxDimensionGet])];
    [view release];

    // center the window
    [window center];
    [window makeKeyAndOrderFront: nil];

    // create and populate the menu
    applicationMenuCreate(view);
    [app finishLaunching];

    // start the timer
    [NSTimer scheduledTimerWithTimeInterval:1.0/20.0 repeats:YES block:^(NSTimer *timer) {
      tickHandler();
    }];

    // run the app
    [app run];

  } // @autoreleasepool

  return EXIT_SUCCESS;
}
