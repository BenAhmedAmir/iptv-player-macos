#import <Foundation/Foundation.h>

@class VLCMediaPlayer;

NS_ASSUME_NONNULL_BEGIN

/// Sets libVLC's relative subtitle size on a live player.
///
/// The value is a divisor of the video height (text height ≈ video height ÷
/// value), so a SMALLER number yields LARGER text. libVLC's own scale runs from
/// 20 (smaller) to 6 (larger). Pass 0 to restore automatic sizing.
///
/// VLCKit exposes no public API for this. libVLC does — via
/// `libvlc_video_set_textrenderer_int` — but it needs the raw
/// `libvlc_media_player_t *`, which only the private `playerInstance` property
/// hands out. Both are reached here rather than leaking the detail into Swift.
void IPTVSetSubtitleFontSize(VLCMediaPlayer *player, int relativeSize);

/// NO if the private hook is unavailable, so callers can degrade gracefully
/// rather than silently doing nothing.
BOOL IPTVSubtitleFontSizeSupported(VLCMediaPlayer *player);

NS_ASSUME_NONNULL_END
