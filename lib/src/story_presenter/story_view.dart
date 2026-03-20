import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_story_presenter/src/story_presenter/story_custom_view_wrapper.dart';
import '../story_presenter/story_view_indicator.dart';
import '../models/story_item.dart';
import '../models/story_view_indicator_config.dart';
import '../controller/flutter_story_controller.dart';
import '../story_presenter/image_story_view.dart';
import '../story_presenter/video_story_view.dart';
import '../story_presenter/text_story_view.dart';
import '../utils/story_utils.dart';
import 'package:video_player/video_player.dart';

//! //! ***** NOTE ***** //! //!
/// currently visibility detector is used to do major operations like
/// playing, pausing, starting animation,resetting animation.
/// but this is not reliable because visibility detector is taking some time
/// to check if the widget is visible or not, for this sole reason, we've to
/// write a lot of boilerplate code and extra logic to handle the delay.
///
/// one alternative solution is write logic by utilizing [page] property
/// inside [pageController]. i believe this can solve this issue, it can be time
/// consuming for researching the possibility. so if someone else gets time,
/// please work on this alternative or find some other alternatives.
///
/// Thank You!

typedef OnStoryChanged = void Function(int);
typedef OnCompleted = Future<void> Function();
typedef OnLeftTap = Future<bool> Function();
typedef OnRightTap = Future<bool> Function();
typedef OnDrag = void Function();
typedef OnItemBuild = Widget? Function(int, Widget);
typedef OnVideoLoad = void Function(VideoPlayerController);
typedef CustomViewBuilder = Widget Function();
typedef OnSlideDown = void Function();
typedef OnPause = Future<bool> Function();
typedef OnResume = Future<bool> Function();
typedef IndicatorWrapper = Widget Function(Widget child);
typedef CommonBuilder = Widget Function(BuildContext context, int index);
typedef StoryBuilder = StoryItem Function(BuildContext context, int index);

class StoryPresenter extends StatefulWidget {
  const StoryPresenter({
    this.storyController,
    required this.itemBuilder,
    required this.itemCount,
    this.onStoryChanged,
    this.onLeftTap,
    this.onRightTap,
    this.onCompleted,
    this.onPreviousCompleted,
    this.storyViewIndicatorConfig,
    this.onVideoLoad,
    this.headerBuilder,
    this.footerBuilder,
    this.onSlideDown,
    this.onPause,
    this.onResume,
    this.indicatorWrapper,
    this.onLongPress,
    this.onLongPressRelease,
    this.isVisible = true,
    super.key,
  });

  /// List of StoryItem objects to display in the story view.
  final int itemCount;

  /// item builder
  final StoryBuilder itemBuilder;

  /// Controller for managing the current playing media.
  final StoryController? storyController;

  /// Callback function triggered whenever the story changes or the user navigates to the previous/next story.
  final OnStoryChanged? onStoryChanged;

  /// Callback function triggered when all items in the list have been played.
  final OnCompleted? onCompleted;

  /// Callback function triggered when all items in the list have been played.
  final OnCompleted? onPreviousCompleted;

  /// Callback function triggered when the user taps on the left half of the screen.
  ///
  /// It must return a boolean future with true if this child will handle the request;
  /// otherwise, return a boolean future with false.
  final OnLeftTap? onLeftTap;

  /// Callback function triggered when the user taps on the right half of the screen.
  ///
  /// It must return a boolean future with true if this child will handle the request;
  /// otherwise, return a boolean future with false.
  final OnRightTap? onRightTap;

  /// Callback function triggered when user drag downs the storyview.
  final OnSlideDown? onSlideDown;

  /// Configuration and styling options for the story view indicator.
  final StoryViewIndicatorConfig? storyViewIndicatorConfig;

  /// Callback function to retrieve the VideoPlayerController when it is initialized and ready to play.
  final OnVideoLoad? onVideoLoad;

  /// Widget to display user profile or other details at the top of the screen.
  final CommonBuilder? headerBuilder;

  /// Widget to display text field or other content at the bottom of the screen.
  final CommonBuilder? footerBuilder;

  /// called when status is paused by user, typically when user tap and holds
  /// on the screen.
  ///
  /// It must return a boolean future with true if this child will handle the request;
  /// otherwise, return a boolean future with false.
  final OnPause? onPause;

  /// called when status is resumed after user paused the view, typically when
  /// user releases the tap from a long press.
  ///
  /// It must return a boolean future with true if this child will handle the request;
  /// otherwise, return a boolean future with false.
  final OnResume? onResume;

  final IndicatorWrapper? indicatorWrapper;

  final VoidCallback? onLongPress;

  final VoidCallback? onLongPressRelease;

  final bool isVisible;

  @override
  State<StoryPresenter> createState() => _StoryPresenterState();
}

class _StoryPresenterState extends State<StoryPresenter>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  VideoPlayerController? _currentVideoPlayer;

  late final StoryController _storyController;
  late final PageController pageController;

  bool _hasStartedCountdown = false;
  bool _isAnimationStatusListenerAdded = false;
  late final ValueNotifier<Duration> _durationNotifier = ValueNotifier(const Duration(seconds: 5));

  @override
  void initState() {
    super.initState();

    _initStoryController();

    if (!widget.isVisible) {
      _storyController.pause();
    }

    _animationController = AnimationController(
      vsync: this,
    );

    _animationController.addListener(() {
      _storyController.sinkPlaybackProgress(_animationController.value);
    });

    pageController = PageController(
      initialPage: _storyController.page,
      keepPage: false,
    );

    widget.onStoryChanged?.call(_storyController.page);

    WidgetsBinding.instance.addObserver(this);
  }

  void _initStoryController() {
    _storyController = widget.storyController ?? StoryController();
    _storyController.addListener(_storyControllerListener);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log("STATE ==> $state");
    switch (state) {
      case AppLifecycleState.resumed:
        _storyController.play();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _storyController.pause();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    pageController.dispose();

    _disposeStoryController();
    _animationController.dispose();

    WidgetsBinding.instance.removeObserver(this);
    _durationNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StoryPresenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _storyController.play();
      } else {
        _storyController.pause();
      }
    }
  }

  void _disposeStoryController() {
    _storyController.removeListener(_storyControllerListener);
    if (widget.storyController == null) {
      _storyController.dispose();
    }
  }

  /// Returns the configuration for the story view indicator.
  StoryViewIndicatorConfig get storyViewIndicatorConfig =>
      widget.storyViewIndicatorConfig ?? const StoryViewIndicatorConfig();

  void _forwardAnimation({double? from}) {
    if (_animationController.duration != null) {
      _animationController.forward(from: from);
    }
  }

  /// Listener for the story controller to handle various story actions.
  void _storyControllerListener() {
    /// Resumes the media playback.
    void resumeMedia() {
      if (!widget.isVisible) return;
      _currentVideoPlayer?.play();
      _forwardAnimation(from: _animationController.value);
    }

    /// Pauses the media playback.
    void pauseMedia() {
      _currentVideoPlayer?.pause();
      _animationController.stop(canceled: false);
    }

    /// Plays the next story item.
    void playNext() async {
      if (_storyController.page == widget.itemCount - 1) {
        await widget.onCompleted?.call();
      } else {
        _storyController.page += 1;
        pageController.jumpToPage(_storyController.page);
        Future.microtask(() => _storyController.play());
      }
    }

    /// Plays the previous story item.
    void playPrevious() {
      if (_storyController.page == 0) {
        widget.onPreviousCompleted?.call();
      } else {
        _storyController.page -= 1;
        pageController.jumpToPage(_storyController.page);
        Future.microtask(() => _storyController.play());
      }
    }

    /// Mutes or unMutes the media explicitly.
    void setMuteMedia(bool mute) {
      if (_currentVideoPlayer != null) {
        _currentVideoPlayer!.setVolume(mute ? 0 : 1);
      }
    }

    final storyStatus = _storyController.storyStatus;

    switch (storyStatus) {
      case StoryAction.play:
        resumeMedia();
        break;

      case StoryAction.pause:
        pauseMedia();
        break;

      case StoryAction.next:
        playNext();
        break;

      case StoryAction.previous:
        playPrevious();
        break;

      case StoryAction.mute:
        setMuteMedia(true);
        break;
      case StoryAction.unMute:
        setMuteMedia(false);
        break;
    }
  }

  /// Resets the animation controller and its listeners.
  void _resetAnimation() {
    _animationController.reset();
    if (_isAnimationStatusListenerAdded) {
      _animationController.removeStatusListener(animationStatusListener);
      _isAnimationStatusListenerAdded = false;
    }
  }

  /// Starts/resumes the countdown for the story item duration.
  ///
  /// If [reset] is false, this will not reset the animation controller and will
  /// instead continue from its current value.
  void _startStoryCountdown(Duration duration, {bool reset = true}) {
    _durationNotifier.value = duration;
    _animationController.duration = duration;

    if (!_isAnimationStatusListenerAdded) {
      _animationController.addStatusListener(animationStatusListener);
      _isAnimationStatusListenerAdded = true;
    }

    if (reset) {
      _animationController.reset();
      _forwardAnimation();
    } else {
      _forwardAnimation(from: _animationController.value);
    }
  }

  /// Listener for the animation status.
  void animationStatusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _storyController.next();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: pageController,
      allowImplicitScrolling: true,
      scrollDirection: Axis.vertical,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: (index) {
        _hasStartedCountdown = false;
        _resetAnimation();
        
        // PAUSE and RESET previous player before losing reference
        try {
          _currentVideoPlayer?.pause();
          _currentVideoPlayer?.seekTo(Duration.zero);
        } catch (_) {
          // Ignore errors if controller is already disposed
        }
        _currentVideoPlayer = null;

        widget.onStoryChanged?.call(index);
      },
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        final item = widget.itemBuilder(context, index);

        return Stack(
          fit: StackFit.expand,
          children: [
            _buildGestureAndContents(context, index, item),
            _buildProgressBar(context, index, item),
            if (widget.headerBuilder != null) ...{
              Align(
                alignment: Alignment.topCenter,
                child: SafeArea(
                  bottom: storyViewIndicatorConfig.enableBottomSafeArea,
                  top: storyViewIndicatorConfig.enableTopSafeArea,
                  child: widget.headerBuilder!(context, index),
                ),
              ),
            },
            if (widget.footerBuilder != null) ...{
              Align(
                alignment: Alignment.bottomCenter,
                child: widget.footerBuilder!(context, index),
              ),
            },
          ],
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, int index, StoryItem item) {
    switch (item.storyItemType) {
      case StoryItemType.image:
        return ImageStoryView(
          key: ValueKey('${item.hashCode}_${item.url}_$index'),
          storyItem: item,
          onVisibilityChanged: (isVisible, isLoaded, isInitial) {
            if (isVisible && isLoaded && _storyController.storyStatus != StoryAction.pause) {
              if (!_hasStartedCountdown) {
                _startStoryCountdown(item.duration, reset: true);
                _hasStartedCountdown = true;
              } else {
                _startStoryCountdown(item.duration, reset: false);
              }
            }
          },
        );

      case StoryItemType.video:
        return VideoStoryView(
          storyItem: item,
          key: ValueKey('${item.hashCode}_${item.url}_$index'),
          looping: false,
          onVisibilityChanged: (videoPlayer, isvisible, isInitial) async {
            if (videoPlayer?.value.isInitialized == true) {
              if (isvisible) {
                _currentVideoPlayer = videoPlayer;
                if (_storyController.storyStatus != StoryAction.pause) {
                  await videoPlayer!.seekTo(Duration.zero).catchError((_) {});
                  // Apply current mute state from controller immediately
                  await videoPlayer.setVolume(_storyController.isMuted ? 0 : 1);
                  await videoPlayer.play();
                  if (!_hasStartedCountdown) {
                    _startStoryCountdown(videoPlayer.value.duration, reset: true);
                    _hasStartedCountdown = true;
                  } else {
                    _startStoryCountdown(videoPlayer.value.duration, reset: false);
                  }
                }
              } else {
                _currentVideoPlayer = null;
                // Use .catchError to handle async exceptions from
                // already-disposed controllers (seekTo is async).
                if (_storyController.storyStatus != StoryAction.play) {
                  videoPlayer?.pause().catchError((_) {});
                  videoPlayer?.seekTo(Duration.zero).catchError((_) {});
                }
              }
            } else {
              _currentVideoPlayer = null;
            }
          },
        );

      case StoryItemType.text:
        return TextStoryView(
          storyItem: item,
          key: ValueKey('${item.hashCode}_${item.url}_$index'),
          onVisibilityChanged: (isLoaded, isVisible, isInitial) {
            debugPrint('StoryPresenter[Text_$index]: isLoaded=$isLoaded, isVisible=$isVisible, status=${_storyController.storyStatus}, hasStarted=$_hasStartedCountdown');
            if (isLoaded && isVisible && _storyController.storyStatus != StoryAction.pause) {
              if (!_hasStartedCountdown) {
                debugPrint('StoryPresenter[Text_$index]: Starting countdown (reset: true), duration: ${item.duration}');
                _startStoryCountdown(item.duration, reset: true);
                _hasStartedCountdown = true;
              } else {
                debugPrint('StoryPresenter[Text_$index]: Starting countdown (reset: false)');
                _startStoryCountdown(item.duration, reset: false);
              }
            }
          },
        );

      // case StoryItemType.web:
      //   return WebStoryView(
      //     storyItem: item,
      //     key: UniqueKey(),
      //     onWebViewLoaded: (controller, loaded) {
      //       if (loaded) {
      //         _startStoryCountdown(item.duration);
      //       }
      //       item.webConfig?.onWebViewLoaded?.call(
      //         controller,
      //         loaded,
      //       );
      //     },
      //   );

      case StoryItemType.custom:
        return StoryCustomWidgetWrapper(
          isAutoStart: true,
          key: ValueKey('${item.hashCode}_${item.url}_$index'),
          builder: () {
            return item.customWidget!(widget.storyController) ?? const SizedBox.shrink();
          },
          storyItem: item,
          onVisibilityChanged: (isVisible) {
            if (isVisible && _storyController.storyStatus != StoryAction.pause) {
              if (!_hasStartedCountdown) {
                _startStoryCountdown(item.duration, reset: true);
                _hasStartedCountdown = true;
              } else {
                _startStoryCountdown(item.duration, reset: false);
              }
            }
          },
        );
    }
  }

  Widget _buildProgressBar(BuildContext context, int index, StoryItem item) {
    final child = ValueListenableBuilder(
        valueListenable: _durationNotifier,
        builder: (context, duration, child) {
          return Align(
            alignment: storyViewIndicatorConfig.alignment,
            child: Padding(
              padding: storyViewIndicatorConfig.margin,
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return StoryViewIndicator(
                    currentIndex: index,
                    currentItemAnimatedValue: _animationController.value,
                    totalItems: widget.itemCount,
                    storyViewIndicatorConfig: storyViewIndicatorConfig,
                  );
                },
              ),
            ),
          );
        });

    return widget.indicatorWrapper?.call(child) ?? child;
  }

  Widget _buildGestureAndContents(BuildContext context, int index, StoryItem item) {
    final width = MediaQuery.sizeOf(context).width;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) async {
        final isNext = details.globalPosition.dx > (width * 0.2);

        if (isNext) {
          final willUserHandle = await widget.onRightTap?.call() ?? false;
          if (!willUserHandle) _storyController.next();
        } else {
          final willUserHandle = await widget.onLeftTap?.call() ?? false;
          if (!willUserHandle) _storyController.previous();
        }
      },
      onLongPress: widget.onLongPress,
      onLongPressMoveUpdate: (_) => widget.onLongPressRelease?.call(),
      onLongPressDown: (details) async {
        final willUserHandle = await widget.onPause?.call() ?? false;
        if (!willUserHandle) _storyController.pause();
      },
      onLongPressUp: () async {
        widget.onLongPressRelease?.call();
        final willUserHandle = await widget.onResume?.call() ?? false;
        if (!willUserHandle) _storyController.play();
      },

      /*
      onVerticalDragStart: (details) {
        dragStartY = details.globalPosition.dy;
      },
      onVerticalDragUpdate: (details) {
        final dragDistance = details.globalPosition.dy - dragStartY;
        if (dragDistance > dragThreshold) {
          widget.onSlideDown?.call();
        }
      },
      */

      //! content goes here
      child: _buildContent(context, index, item),
    );
  }
}
