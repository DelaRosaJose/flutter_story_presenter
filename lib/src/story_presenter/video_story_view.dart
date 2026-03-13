import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_story_presenter/flutter_story_presenter.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../utils/video_utils.dart';

/// A widget that displays a video story view, supporting different video sources
/// (network, file, asset) and optional thumbnail and error widgets.
///

typedef OnVisibilityChanged = void Function(
    VideoPlayerController? videoPlayer, bool isVisible, bool isInitial);

class VideoStoryView extends StatefulWidget {
  /// Creates a [VideoStoryView] widget.
  const VideoStoryView({
    super.key,
    required this.storyItem,
    this.looping,
    this.onEnd,
    this.onVisibilityChanged,
  });

  /// The story item containing video data and configuration.
  final StoryItem storyItem;

  /// In case of single video story
  final bool? looping;
  final OnVisibilityChanged? onVisibilityChanged;
  final VoidCallback? onEnd;

  @override
  State<VideoStoryView> createState() => _VideoStoryViewState();
}

class _VideoStoryViewState extends State<VideoStoryView> {
  VideoPlayerController? controller;
  VideoStatus videoStatus = VideoStatus.loading;
  bool _isDisposed = false;
  bool _hasNotifiedInitialVisibility = false;
// 1. AÑADIMOS ESTA VARIABLE PARA RASTREAR LA VISIBILIDAD REAL
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _initialiseVideoPlayer().then((_) {
      if (!_isDisposed && videoStatus.isLive) {
        controller?.addListener(videoListener);
      }
    });
  }

  /// Initializes the video player controller based on the source of the video.
  Future<void> _initialiseVideoPlayer() async {
    try {
      final storyItem = widget.storyItem;
      if (storyItem.storyItemSource.isNetwork) {
        // Initialize video controller for network source.
        controller = await VideoUtils.instance.videoControllerFromUrl(
          url: storyItem.url!,
          cacheFile: storyItem.videoConfig?.cacheVideo,
          videoPlayerOptions: storyItem.videoConfig?.videoPlayerOptions,
        );
      } else if (storyItem.storyItemSource.isFile) {
        // Initialize video controller for file source.
        controller = VideoUtils.instance.videoControllerFromFile(
          file: File(storyItem.url!),
          videoPlayerOptions: storyItem.videoConfig?.videoPlayerOptions,
        );
      } else {
        // Initialize video controller for asset source.
        controller = VideoUtils.instance.videoControllerFromAsset(
          assetPath: storyItem.url!,
          videoPlayerOptions: storyItem.videoConfig?.videoPlayerOptions,
        );
      }
      if (_isDisposed) {
        controller?.dispose();
        controller = null;
        return;
      }
      await controller?.initialize();
      if (_isDisposed) {
        controller?.dispose();
        controller = null;
        return;
      }
      videoStatus = VideoStatus.live;

      if (controller != null) {
        _notifyVisibilityChanged(controller, _isVisible);
      }

      await controller?.setLooping(widget.looping ?? false);
      await controller?.setVolume(storyItem.isMuteByDefault ? 0 : 1);
    } catch (e) {
      videoStatus = VideoStatus.error;
      debugPrint('$e');
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _notifyVisibilityChanged(VideoPlayerController? controller, bool isVisible) {
    final isInitial = !_hasNotifiedInitialVisibility;
    _hasNotifiedInitialVisibility = true;
    widget.onVisibilityChanged?.call(controller, isVisible, isInitial);
  }

  void videoListener() async {
    final pos = controller?.value.position ?? Duration.zero;
    final dur = controller?.value.duration ?? Duration.zero;
    if (pos >= dur) {
      widget.onEnd?.call();
    }
  }

  BoxFit get fit => config.fit ?? BoxFit.cover;

  StoryViewVideoConfig get config => widget.storyItem.videoConfig ?? const StoryViewVideoConfig();

  @override
  void dispose() {
    _isDisposed = true;
    controller?.removeListener(videoListener);
    controller?.dispose();
    controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey(widget.storyItem.url ?? widget.storyItem.hashCode.toString()),
      onVisibilityChanged: (info) {
        if (_isDisposed) return;
        _isVisible = info.visibleFraction == 1;
        if (controller?.value.isInitialized == true) {
          _notifyVisibilityChanged(controller, _isVisible);
        }
      },
      child: Stack(
        alignment: (fit == BoxFit.cover) ? Alignment.topCenter : Alignment.center,
        fit: (fit == BoxFit.cover) ? StackFit.expand : StackFit.loose,
        children: [
          if (config.loadingWidget != null) ...{
            config.loadingWidget!,
          },
          if (widget.storyItem.errorWidget != null && videoStatus.hasError) ...{
            // Display the error widget if an error occurred.
            widget.storyItem.errorWidget!,
          },
          if (videoStatus.isLive && controller != null) ...{
            if (config.useVideoAspectRatio) ...{
              // Display the video with aspect ratio if specified.
              AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: VideoPlayer(controller!),
              )
            } else ...{
              // Display the video fitted to the screen.
              FittedBox(
                fit: config.fit ?? BoxFit.cover,
                alignment: Alignment.center,
                child: SizedBox(
                    width: config.width ?? controller?.value.size.width,
                    height: config.height ?? controller?.value.size.height,
                    child: VideoPlayer(controller!)),
              )
            },
          }
        ],
      ),
    );
  }
}
