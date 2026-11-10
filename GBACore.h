#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Bit values match GBA keypad register order.
typedef NS_OPTIONS(uint32_t, GBAKey) {
    GBAKeyA = 1<<0, GBAKeyB = 1<<1, GBAKeySelect = 1<<2, GBAKeyStart = 1<<3,
    GBAKeyRight = 1<<4, GBAKeyLeft = 1<<5, GBAKeyUp = 1<<6, GBAKeyDown = 1<<7,
    GBAKeyR = 1<<8, GBAKeyL = 1<<9,
};

@interface GBACore : NSObject
- (BOOL)loadROMAtPath:(NSString *)path error:(NSError **)error;
- (void)runFrame;
- (CGImageRef)copyFrameImage CF_RETURNS_RETAINED;
- (void)setKeys:(GBAKey)keys;
/// Copies the 240x160 RGBA8 frame (153,600 bytes) into dst.
- (void)copyVideoTo:(uint32_t *)dst;
/// Fills interleaved stereo Int16 at 48 kHz; returns frames written.
- (NSInteger)readAudio:(int16_t *)buffer frames:(NSInteger)frames;
/// In-memory snapshot used by rewind.
- (NSData *)captureState;
- (BOOL)restoreState:(NSData *)data;
/// Each string is one cheat: GameShark / Action Replay lines separated by newlines.
- (void)applyCheats:(NSArray<NSString *> *)blocks;
- (void)saveStateToSlot:(int)slot;
- (void)loadStateFromSlot:(int)slot;
- (void)shutdown;
@end
