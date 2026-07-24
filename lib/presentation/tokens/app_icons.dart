import 'package:hugeicons/hugeicons.dart';

/// The app's icon type. Hugeicons are SVG path-data (`List<List<dynamic>>`),
/// not font glyphs, so this is *not* [IconData] — render it with [AppIcon]
/// (see `components/app_icon.dart`), never Flutter's [Icon].
typedef AppIconData = List<List<dynamic>>;

/// The single source of truth for the app's iconography.
///
/// Every screen references icons through these semantic names, so the whole
/// product shares one icon language and swapping the underlying set (or an
/// individual glyph) is a one-file change. The player subtree keeps Material
/// [Icons] on purpose — it is out of scope for the revamp.
///
/// The set is Hugeicons *stroke-rounded*: an even, calm hairline that reads as
/// a deliberate, bespoke identity rather than stock Material. Emphasis (a
/// "heavier" selected state) comes from [AppIcon.strokeWidth], not a separate
/// filled weight — the free set is stroke-only.
///
/// **Prefer open glyphs over enclosed ones.** Hugeicons draws its `…Circle` /
/// `…Square` variants right out to the edge of the 24-unit box while an open
/// glyph sits well inside it, so an enclosed icon reads two sizes larger than
/// its neighbours on the same list. Reach for an enclosed variant only where
/// the enclosure carries the meaning ([checkCircle], [playCircle], [info]).
abstract final class AppIcons {
  static const AppIconData play = HugeIcons.strokeRoundedPlay;
  static const AppIconData pause = HugeIcons.strokeRoundedPause;
  static const AppIconData stop = HugeIcons.strokeRoundedStop;
  static const AppIconData playCircle = HugeIcons.strokeRoundedPlayCircle;
  static const AppIconData skipNext = HugeIcons.strokeRoundedNext;
  static const AppIconData skipPrevious = HugeIcons.strokeRoundedPrevious;
  static const AppIconData repeat = HugeIcons.strokeRoundedRepeat;
  static const AppIconData repeatOne = HugeIcons.strokeRoundedRepeatOne01;
  static const AppIconData shuffle = HugeIcons.strokeRoundedShuffle;
  static const AppIconData volumeUp = HugeIcons.strokeRoundedVolumeHigh;
  static const AppIconData volumeDown = HugeIcons.strokeRoundedVolumeLow;
  static const AppIconData volumeOff = HugeIcons.strokeRoundedVolumeOff;
  static const AppIconData queue = HugeIcons.strokeRoundedQueue02;
  static const AppIconData queuePlayNext = HugeIcons.strokeRoundedPlayListAdd;
  static const AppIconData playlist = HugeIcons.strokeRoundedPlayList;
  static const AppIconData playlistAdd = HugeIcons.strokeRoundedPlayListAdd;
  static const AppIconData playlistRemove =
      HugeIcons.strokeRoundedPlayListRemove;
  static const AppIconData musicNote = HugeIcons.strokeRoundedMusicNote01;
  // Used for "no songs found" empty states, so it wants to read as *absence* —
  // a plain note in a square (now [library]) said the opposite.
  static const AppIconData musicOff = HugeIcons.strokeRoundedFolderOff;
  static const AppIconData album = HugeIcons.strokeRoundedAlbum02;
  // A music note enclosed in a rounded square. This drives the Library nav tab,
  // the Library settings group, the library screen and the scan banner, so it
  // has to say "your music" at both tab and inline size — the book-shaped
  // glyphs it used before said "reading".
  //
  // One of the few enclosed glyphs kept on purpose (see the note above): the
  // enclosure is what distinguishes it from [musicNote], which is the bare
  // note.
  static const AppIconData library = HugeIcons.strokeRoundedMusicNoteSquare01;
  static const AppIconData libraryAdd = HugeIcons.strokeRoundedPlayListAdd;
  // Only used for the "Include Videos" filter, so it wants to read as video
  // rather than as a second library.
  static const AppIconData videoLibrary = HugeIcons.strokeRoundedVideo01;
  static const AppIconData movie = HugeIcons.strokeRoundedVideo01;
  static const AppIconData collectionsBookmark =
      HugeIcons.strokeRoundedBookmark02;
  static const AppIconData home = HugeIcons.strokeRoundedHome01;
  static const AppIconData person = HugeIcons.strokeRoundedUser;
  static const AppIconData personAdd = HugeIcons.strokeRoundedUserAdd01;
  static const AppIconData search = HugeIcons.strokeRoundedSearch01;
  static const AppIconData searchOff = HugeIcons.strokeRoundedSearchRemove;
  static const AppIconData manageSearch = HugeIcons.strokeRoundedSearchList01;
  static const AppIconData imageSearch = HugeIcons.strokeRoundedSearch01;
  static const AppIconData travelExplore = HugeIcons.strokeRoundedGlobalSearch;
  static const AppIconData explore = HugeIcons.strokeRoundedCompass;
  static const AppIconData settings = HugeIcons.strokeRoundedSettings01;
  static const AppIconData more = HugeIcons.strokeRoundedMoreHorizontal;
  static const AppIconData moreVert = HugeIcons.strokeRoundedMoreVertical;
  static const AppIconData close = HugeIcons.strokeRoundedCancel01;
  static const AppIconData tick = HugeIcons.strokeRoundedTick02;
  static const AppIconData checkCircle =
      HugeIcons.strokeRoundedCheckmarkCircle02;
  static const AppIconData circle = HugeIcons.strokeRoundedCircle;
  static const AppIconData add = HugeIcons.strokeRoundedAdd01;
  static const AppIconData arrowBack = HugeIcons.strokeRoundedArrowLeft01;
  static const AppIconData arrowForward = HugeIcons.strokeRoundedArrowRight01;
  static const AppIconData chevronRight = HugeIcons.strokeRoundedArrowRight01;
  static const AppIconData arrowDown = HugeIcons.strokeRoundedArrowDown01;
  static const AppIconData arrowUp = HugeIcons.strokeRoundedArrowUp01;
  static const AppIconData refresh = HugeIcons.strokeRoundedRefresh;
  static const AppIconData restore = HugeIcons.strokeRoundedArrowTurnBackward;
  // Bare heart, not FavouriteCircle: the enclosed variant filled its badge edge
  // to edge and was visibly the largest thing in the drawer.
  static const AppIconData favorite = HugeIcons.strokeRoundedFavourite;
  static const AppIconData heartBroken = HugeIcons.strokeRoundedHeartbreak;
  static const AppIconData thumbDown = HugeIcons.strokeRoundedThumbsDown;
  static const AppIconData star = HugeIcons.strokeRoundedStar;
  static const AppIconData pushPin = HugeIcons.strokeRoundedPin;
  static const AppIconData folder = HugeIcons.strokeRoundedFolder02;
  static const AppIconData folderOff = HugeIcons.strokeRoundedFolderBlock;
  static const AppIconData folderAdd = HugeIcons.strokeRoundedFolderAdd;
  static const AppIconData folderMove = HugeIcons.strokeRoundedFolderTransfer;
  static const AppIconData folderZip = HugeIcons.strokeRoundedFolderZip;
  static const AppIconData save = HugeIcons.strokeRoundedFloppyDisk;
  static const AppIconData download = HugeIcons.strokeRoundedDownload01;
  static const AppIconData upload = HugeIcons.strokeRoundedUpload01;
  static const AppIconData cloudUpload = HugeIcons.strokeRoundedCloudUpload;
  static const AppIconData softwareUpdate = HugeIcons.strokeRoundedCloudUpload;
  static const AppIconData storage = HugeIcons.strokeRoundedDatabase;
  static const AppIconData dataUsage = HugeIcons.strokeRoundedPieChart;
  static const AppIconData dataObject = HugeIcons.strokeRoundedSourceCode;
  static const AppIconData copy = HugeIcons.strokeRoundedCopy01;
  static const AppIconData linkOff = HugeIcons.strokeRoundedUnlink01;
  static const AppIconData merge = HugeIcons.strokeRoundedGitMerge;
  static const AppIconData swapHoriz =
      HugeIcons.strokeRoundedArrowDataTransferHorizontal;
  static const AppIconData swapVert =
      HugeIcons.strokeRoundedArrowDataTransferVertical;
  static const AppIconData syncAlt =
      HugeIcons.strokeRoundedArrowDataTransferHorizontal;
  static const AppIconData share = HugeIcons.strokeRoundedShare08;
  static const AppIconData openInNew = HugeIcons.strokeRoundedLinkSquare01;
  static const AppIconData clock = HugeIcons.strokeRoundedClock01;
  static const AppIconData timer = HugeIcons.strokeRoundedTimer01;
  static const AppIconData bedtime = HugeIcons.strokeRoundedMoon02;
  static const AppIconData hourglass = HugeIcons.strokeRoundedTimer01;
  static const AppIconData analytics = HugeIcons.strokeRoundedAnalytics01;
  static const AppIconData graphicEq = HugeIcons.strokeRoundedAudioWave01;
  static const AppIconData waves = HugeIcons.strokeRoundedAudioWave02;
  static const AppIconData blur = HugeIcons.strokeRoundedBlur;
  static const AppIconData tune = HugeIcons.strokeRoundedPreferenceHorizontal;
  static const AppIconData filterList = HugeIcons.strokeRoundedFilterHorizontal;
  static const AppIconData sort = HugeIcons.strokeRoundedSortByDown01;
  static const AppIconData viewList =
      HugeIcons.strokeRoundedLeftToRightListBullet;
  static const AppIconData gridView = HugeIcons.strokeRoundedGrid;
  static const AppIconData palette = HugeIcons.strokeRoundedColors;
  static const AppIconData autoAwesome = HugeIcons.strokeRoundedSparkles;
  static const AppIconData autoFix = HugeIcons.strokeRoundedMagicWand01;
  static const AppIconData textFields = HugeIcons.strokeRoundedTextFont;
  static const AppIconData edit = HugeIcons.strokeRoundedEdit02;
  static const AppIconData delete = HugeIcons.strokeRoundedDelete02;
  static const AppIconData deleteForever = HugeIcons.strokeRoundedDelete03;
  static const AppIconData deleteSweep = HugeIcons.strokeRoundedDeleteThrow;
  static const AppIconData removeCircle = HugeIcons.strokeRoundedRemoveCircle;
  static const AppIconData dragHandle = HugeIcons.strokeRoundedDragDropVertical;
  static const AppIconData info = HugeIcons.strokeRoundedInformationCircle;
  static const AppIconData help = HugeIcons.strokeRoundedHelpCircle;
  static const AppIconData error = HugeIcons.strokeRoundedAlertCircle;
  static const AppIconData warning = HugeIcons.strokeRoundedAlert02;
  static const AppIconData security = HugeIcons.strokeRoundedShield01;
  static const AppIconData verified = HugeIcons.strokeRoundedCheckmarkBadge01;
  static const AppIconData visibilityOff = HugeIcons.strokeRoundedViewOff;
  static const AppIconData screenLock = HugeIcons.strokeRoundedSquareLock01;
  static const AppIconData touchApp = HugeIcons.strokeRoundedTap01;
  static const AppIconData flashOn = HugeIcons.strokeRoundedFlash;
  static const AppIconData videocamOff = HugeIcons.strokeRoundedVideoOff;
  // Setting06 is a hexagon crossed by a slash — it reads as "prohibited", not
  // "miscellaneous".
  static const AppIconData misc = HugeIcons.strokeRoundedSetting07;
  static const AppIconData photoSize = HugeIcons.strokeRoundedImageCrop;
  static const AppIconData image = HugeIcons.strokeRoundedImage01;
  static const AppIconData lyrics = HugeIcons.strokeRoundedTextAlignLeft01;
  static const AppIconData mic = HugeIcons.strokeRoundedMic01;
  static const AppIconData disc = HugeIcons.strokeRoundedDisc;
}
