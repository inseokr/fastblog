import Foundation

// MARK: - Typed analytics events (BLOGGO-355)
//
// Usage:
//   AppAnalytics.track(.blogSave(blogId: "abc123"))
//   AppAnalytics.track(.appOpen)

enum AnalyticsEventType {

    // ── Blog lifecycle ─────────────────────────────────────────────────────
    case blogScan
    case blogSave(blogId: String)
    case blogDelete(blogId: String)
    case blogSharePDF(blogId: String)
    case blogShareSocialMedia(blogId: String)
    case blogShareStitchReels(blogId: String)
    case blogShareNearby(blogId: String)
    case blogPlaySlideshow(blogId: String)
    case blogPickCoverPhoto(blogId: String)
    case blogChangeBlogTitle(blogId: String)
    case blogSplit(blogId: String)
    case blogMerge(blogId: String)

    // ── Place actions ──────────────────────────────────────────────────────
    case blogPlaceChangeName(blogId: String, placeId: String)
    case blogPlaceChangeNameClickPoi(blogId: String, placeId: String)
    case blogPlaceChangeNameCustom(blogId: String, placeId: String)
    case blogPlaceChangeNameAutoComplete(blogId: String, placeId: String)
    case blogPlaceManagePhoto(blogId: String, placeId: String)

    // ── Stories ────────────────────────────────────────────────────────────
    case blogPlaceStory(blogId: String, placeId: String)
    case blogPlacePhotoStory(blogId: String, placeId: String, photoId: String)
    case blogDayStory(blogId: String, dayIndex: Int)
    case blogStory(blogId: String)
    case blogStoryAIStory(blogId: String)
    case blogSentimentAdjustment(blogId: String)

    // ── MoreMemories ───────────────────────────────────────────────────────
    case blogMoreMemories(blogId: String)
    case blogMoreMemoriesCreateBlog(sourceBlogId: String)

    // ── App-level ──────────────────────────────────────────────────────────
    case appOpen
    case appInAppCameraOpen
    case appInAppCameraPhotoTaken
    case appInAppCameraVibePhotoTaken
    case appInAppCameraReelSaved(duration: Int, stopMode: String)
    case appInAppCameraReelTrimmed(originalDuration: Int, trimmedDuration: Int, trimmedFromStart: Int, trimmedFromEnd: Int)
    case appInAppCameraReelNoiseReduced(duration: Int)
    case appInAppCameraVibeON
    case appInAppCameraCaption
    case appInAppCameraPreviewSave
    case appInAppCameraPreviewDiscard
    case appInAppCameraVoiceMemoSave
    case appInAppCameraVoiceMemoPlay

    // -----------------------------------------------------------------------
    // MARK: Derived values consumed by AppAnalytics
    // -----------------------------------------------------------------------

    var eventName: String {
        switch self {
        case .blogScan:                         return "Blog-Scan"
        case .blogSave:                         return "Blog-Save"
        case .blogDelete:                       return "Blog-Delete"
        case .blogSharePDF:                     return "Blog-Share-PDF"
        case .blogShareSocialMedia:             return "Blog-Share-SocialMedia"
        case .blogShareStitchReels:             return "Blog-Share-StitchReels"
        case .blogShareNearby:                  return "Blog-Share-Nearby"
        case .blogPlaySlideshow:                return "Blog-Play-Slideshow"
        case .blogPickCoverPhoto:               return "Blog-Pick-CoverPhoto"
        case .blogChangeBlogTitle:              return "Blog-Change-BlogTitle"
        case .blogSplit:                        return "Blog-Split"
        case .blogMerge:                        return "Blog-Merge"
        case .blogPlaceChangeName:              return "Blog-Place-ChangeName"
        case .blogPlaceChangeNameClickPoi:      return "Blog-Place-ChangeName-ClickPoi"
        case .blogPlaceChangeNameCustom:        return "Blog-Place-ChangeName-Custom"
        case .blogPlaceChangeNameAutoComplete:  return "Blog-Place-ChangeName-AutoComplete"
        case .blogPlaceManagePhoto:             return "Blog-Place-Photo-ManagePhoto"
        case .blogPlaceStory:                   return "Blog-Place-Story"
        case .blogPlacePhotoStory:              return "Blog-Place-Photo-Story"
        case .blogDayStory:                     return "Blog-Day-Story"
        case .blogStory:                        return "Blog-Story"
        case .blogStoryAIStory:                 return "Blog-Story-AIStory"
        case .blogSentimentAdjustment:          return "Blog-Sentiment-Adjustment"
        case .blogMoreMemories:                 return "Blog-MoreMemories"
        case .blogMoreMemoriesCreateBlog:       return "Blog-MoreMemories-CreateBlog"
        case .appOpen:                          return "App-Open"
        case .appInAppCameraOpen:               return "App-InAppCamera-Open"
        case .appInAppCameraPhotoTaken:         return "App-InAppCamera-PhotoTaken"
        case .appInAppCameraVibePhotoTaken:     return "App-InAppCamera-VibePhoto-Taken"
        case .appInAppCameraReelSaved:          return "App-InAppCamera-Reel-Saved"
        case .appInAppCameraReelTrimmed:        return "App-InAppCamera-Reel-Trimmed"
        case .appInAppCameraReelNoiseReduced:   return "App-InAppCamera-Reel-NoiseReduced"
        case .appInAppCameraVibeON:             return "App-InAppCamera-VibeON"
        case .appInAppCameraCaption:            return "App-InAppCamera-Caption"
        case .appInAppCameraPreviewSave:        return "App-InAppCamera-Preview-Save"
        case .appInAppCameraPreviewDiscard:     return "App-InAppCamera-Preview-Discard"
        case .appInAppCameraVoiceMemoSave:      return "App-InAppCamera-VoiceMemo-Save"
        case .appInAppCameraVoiceMemoPlay:      return "App-InAppCamera-VoiceMemo-Play"
        }
    }

    var context: AnalyticsContext {
        switch self {
        case .blogScan, .appOpen, .appInAppCameraOpen,
             .appInAppCameraPhotoTaken, .appInAppCameraVibePhotoTaken, .appInAppCameraReelSaved,
             .appInAppCameraReelTrimmed,
             .appInAppCameraReelNoiseReduced,
             .appInAppCameraVibeON, .appInAppCameraCaption,
             .appInAppCameraPreviewSave, .appInAppCameraPreviewDiscard,
             .appInAppCameraVoiceMemoSave, .appInAppCameraVoiceMemoPlay:
            return .empty

        case .blogSave(let id),
             .blogDelete(let id),
             .blogSharePDF(let id),
             .blogShareSocialMedia(let id),
             .blogShareStitchReels(let id),
             .blogShareNearby(let id),
             .blogPlaySlideshow(let id),
             .blogPickCoverPhoto(let id),
             .blogChangeBlogTitle(let id),
             .blogSplit(let id),
             .blogMerge(let id),
             .blogStory(let id),
             .blogStoryAIStory(let id),
             .blogSentimentAdjustment(let id),
             .blogMoreMemories(let id),
             .blogMoreMemoriesCreateBlog(let id):
            return AnalyticsContext(blogId: id)

        case .blogPlaceChangeName(let blogId, let placeId),
             .blogPlaceChangeNameClickPoi(let blogId, let placeId),
             .blogPlaceChangeNameCustom(let blogId, let placeId),
             .blogPlaceChangeNameAutoComplete(let blogId, let placeId),
             .blogPlaceManagePhoto(let blogId, let placeId),
             .blogPlaceStory(let blogId, let placeId):
            return AnalyticsContext(blogId: blogId, placeId: placeId)

        case .blogPlacePhotoStory(let blogId, let placeId, let photoId):
            return AnalyticsContext(blogId: blogId, placeId: placeId, photoId: photoId)

        case .blogDayStory(let blogId, let dayIndex):
            return AnalyticsContext(blogId: blogId, dayIndex: dayIndex)
        }
    }

    /// Extra properties beyond context (most events need none).
    var properties: [String: String] {
        switch self {
        case .appInAppCameraReelSaved(let duration, let stopMode):
            return ["duration": "\(duration)", "stopMode": stopMode]
        case .appInAppCameraReelTrimmed(let originalDuration, let trimmedDuration, let trimmedFromStart, let trimmedFromEnd):
            return [
                "originalDuration": "\(originalDuration)",
                "trimmedDuration": "\(trimmedDuration)",
                "trimmedFromStart": "\(trimmedFromStart)",
                "trimmedFromEnd": "\(trimmedFromEnd)"
            ]
        case .appInAppCameraReelNoiseReduced(let duration):
            return ["duration": "\(duration)"]
        default:
            return [:]
        }
    }
}
