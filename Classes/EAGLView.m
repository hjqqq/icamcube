#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>

#import "EAGLView.h"
#import "Surface.h"
#import "SurfaceAccelerator.h"
#import "glu.h"

#define USE_DEPTH_BUFFER 1

// A class extension to declare private methods
@interface EAGLView ()

@property (nonatomic, retain) EAGLContext *context;
@property (nonatomic, assign) NSTimer *animationTimer;

- (BOOL)createFramebuffer;
- (void)destroyFramebuffer;

- (void)initTexture;
- (void)setTexture;

- (void)drawRectSize:(float)size;
- (void)drawCubeSize:(float)size;
@end

//------------------------------------------------------------------------------

static FUNC_camera_callback original_camera_callback = NULL;

static uint8_t *frame = NULL;  // Taken from the camera, the pixel format is GBRA
static int frameWidth;
static int frameHeight;

static int __camera_callbackHook(CameraDeviceRef cameraDevice, int a, CoreSurfaceBufferRef coreSurfaceBuffer, int b) {
	if (coreSurfaceBuffer) {
		Surface *surface = [[Surface alloc]initWithCoreSurfaceBuffer:coreSurfaceBuffer];
		[surface lock];
		
		if (!frame) {
			frameWidth  = surface.width;
			frameHeight = surface.height;			
			frame = malloc(frameWidth*frameHeight*4);
		}
		memcpy(frame, surface.baseAddress, frameWidth*frameHeight*4);
		
		[surface unlock];
		[surface release];
	}
	return (*original_camera_callback)(cameraDevice, a, coreSurfaceBuffer, b);
}

//------------------------------------------------------------------------------

@implementation EAGLView

@synthesize context;
@synthesize animationTimer;
@synthesize animationInterval;

// You must implement this method
+ (Class)layerClass {
    return [CAEAGLLayer class];
}

//The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithCoder:(NSCoder*)coder {
    
    if ((self = [super initWithCoder:coder])) {
        // Get the layer
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        
        eaglLayer.opaque = YES;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
        
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
        
        if (!context || ![EAGLContext setCurrentContext:context]) {
            [self release];
            return nil;
        }
        
        animationInterval = 1.0 / 60.0;
    }
    return self;
}

- (void)installCameraCallbackHook {
	id cameraController = [objc_getClass("PLCameraController") sharedInstance];
	[cameraController startPreview];
	[Surface dynamicLoad];
	
	char *p = NULL;
	object_getInstanceVariable(cameraController, "_camera", (void**) &p);
	if (!p) return;
	
	if (!original_camera_callback) {
		FUNC_camera_callback *funcP = (FUNC_camera_callback*) p;
		original_camera_callback = *(funcP+37);
		(funcP + 37)[0] = __camera_callbackHook;
	}
}

//------------------------------------------------------------------------------

- (void)initTexture {
	glGenTextures(1, &texture);
	glBindTexture(GL_TEXTURE_2D, texture);
	
	textureWidth  = 512;
	textureHeight = 512;
	texturePixels = malloc(textureWidth*textureHeight*4);
	
	textureCoords[0] = 0;                                  textureCoords[1] = 0;
	textureCoords[2] = (GLfloat) frameWidth/textureWidth;  textureCoords[3] = 0;
	textureCoords[4] = 0;                                  textureCoords[5] = (GLfloat) frameHeight/textureHeight;
	textureCoords[6] = (GLfloat) frameWidth/textureWidth;  textureCoords[7] = (GLfloat) frameHeight/textureHeight;
}

- (void)setTexture {
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glEnable(GL_TEXTURE_2D);
	glDisable(GL_BLEND);
	glBindTexture(GL_TEXTURE_2D, texture);
	
	glTexCoordPointer(2, GL_FLOAT, 0, textureCoords);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	for (int j = 0; j < frameHeight; j++) {
		memcpy(texturePixels + j*textureWidth*4, frame + ((frameHeight - 1) - j)*frameWidth*4, frameWidth*4);
	}
	// The internal format must be GL_RGBA
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, textureWidth, textureHeight, 0, GL_BGRA, GL_UNSIGNED_BYTE, texturePixels);
}

- (void)drawRectSize:(float)size {
	// Front face is specified the counter-clockwise order of the first 3 vertices
	GLfloat vertices[] = {
		-size/2, -size/2,
		size/2, -size/2,
		-size/2, size/2,
		size/2, size/2
    };

	glVertexPointer(2, GL_FLOAT, 0, vertices);
    glEnableClientState(GL_VERTEX_ARRAY);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

- (void)drawCubeSize:(float)size {
	// Rotation:
	// * Let the vector's head point at your face
	// * The +direction is counter-clockwise
	
	// Front
	glPushMatrix();
	glColor4ub(255, 255, 255, 255);
	glTranslatef(0, 0, size/2);
	[self drawRectSize:size];
	glPopMatrix();

	// Back	
	glPushMatrix();
	glColor4ub(0, 255, 0, 127);
	glTranslatef(0, 0, -size/2);
	glRotatef(180, 0, 1, 0);
	[self drawRectSize:size];
	glPopMatrix();

	// Left
	glPushMatrix();
	glColor4ub(0, 0, 255, 127);
	glTranslatef(-size/2, 0, 0);
	glRotatef(-90, 0, 1, 0);
	[self drawRectSize:size];
	glPopMatrix();
	
	// Right
	glPushMatrix();
	glColor4ub(255, 255, 0, 127);
	glTranslatef(size/2, 0, 0);
	glRotatef(90, 0, 1, 0);
	[self drawRectSize:size];
	glPopMatrix();

	// Top
	glPushMatrix();
	glColor4ub(0, 255, 255, 127);
	glTranslatef(0, size/2, 0);
	glRotatef(-90, 1, 0, 0);
	[self drawRectSize:size];
	glPopMatrix();
	
	// Bottom
	glPushMatrix();
 	glColor4ub(255, 0, 255, 127);
	glTranslatef(0, -size/2, 0);
	glRotatef(90, 1, 0, 0);
	[self drawRectSize:size];
	glPopMatrix();
}

- (void)drawView {
	if (!frame) {
		return;
	}
	
	[EAGLContext setCurrentContext:context];
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
    glViewport(0, 0, backingWidth, backingHeight);
	glClearColor(255, 255, 255, 255);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

	glEnable(GL_CULL_FACE);
	
	static BOOL textureInitialized = NO;
	if (!textureInitialized) {
		[self initTexture];
		textureInitialized = YES;		
	}
	
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
	glOrthof(-1, 1, (float) -backingHeight/backingWidth, (float) backingHeight/backingWidth, -1, 1);
    //gluPerspective(60, (GLfloat) backingHeight/backingWidth, -10, 10);
	//gluLookAt(0, 0, -1, 0, 0, 0, 0, 1, 0);

    glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
	static float rx = 0, ry = 0, rz = 0;
	rx += 1; ry += 1; rz += 1;
    glRotatef(rx, 1, 0, 0);
	glRotatef(ry, 0, 1, 0);
	glRotatef(rz, 0, 0, 1);
    
	[self setTexture];
	[self drawCubeSize:1.2];

    glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
    [context presentRenderbuffer:GL_RENDERBUFFER_OES];
}

//------------------------------------------------------------------------------

- (void)layoutSubviews {
    [EAGLContext setCurrentContext:context];
    [self destroyFramebuffer];
    [self createFramebuffer];
    [self drawView];
}

- (BOOL)createFramebuffer {
    glGenFramebuffersOES(1, &viewFramebuffer);
    glGenRenderbuffersOES(1, &viewRenderbuffer);
    
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer*)self.layer];
    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);
    
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
    
    if (USE_DEPTH_BUFFER) {
        glGenRenderbuffersOES(1, &depthRenderbuffer);
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
        glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight);
        glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);
    }
    
    if(glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES) {
        NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
        return NO;
    }
    
    return YES;
}

- (void)destroyFramebuffer {
    glDeleteFramebuffersOES(1, &viewFramebuffer);
    viewFramebuffer = 0;
    glDeleteRenderbuffersOES(1, &viewRenderbuffer);
    viewRenderbuffer = 0;
    
    if(depthRenderbuffer) {
        glDeleteRenderbuffersOES(1, &depthRenderbuffer);
        depthRenderbuffer = 0;
    }
}

//------------------------------------------------------------------------------

- (void)startAnimation {
    self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:animationInterval target:self selector:@selector(drawView) userInfo:nil repeats:YES];
}

- (void)stopAnimation {
    self.animationTimer = nil;
}

- (void)setAnimationTimer:(NSTimer *)newTimer {
    [animationTimer invalidate];
    animationTimer = newTimer;
}

- (void)setAnimationInterval:(NSTimeInterval)interval {
    animationInterval = interval;
    if (animationTimer) {
        [self stopAnimation];
        [self startAnimation];
    }
}

//------------------------------------------------------------------------------

- (void)dealloc {
    [self stopAnimation];
	free(texturePixels);
    
    if ([EAGLContext currentContext] == context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    [context release];  
    [super dealloc];
}

@end
