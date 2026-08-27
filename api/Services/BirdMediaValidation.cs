namespace CroApp.Api.Services;

public enum BirdMediaKind
{
    Audio,
    Image,
}

// Content-type/size rules for a composed bird's payload media (Parrot's audio clip,
// Pigeon/Raven's image) - kept separate from ImageUploadValidation's profile/nest-picture
// rules since audio is a new media category with its own allowlist and a larger size cap
// (voice clips routinely exceed a 5MB image cap even at a few seconds, low bitrate).
internal static class BirdMediaValidation
{
    public static readonly HashSet<string> AllowedImageContentTypes =
    [
        "image/png", "image/jpeg", "image/gif", "image/webp"
    ];

    public static readonly HashSet<string> AllowedAudioContentTypes =
    [
        "audio/mpeg", "audio/wav", "audio/webm", "audio/aac", "audio/mp4", "audio/x-m4a", "audio/ogg"
    ];

    public const long MaxImageSizeBytes = 5 * 1024 * 1024;
    public const long MaxAudioSizeBytes = 10 * 1024 * 1024;

    public static HashSet<string> AllowedContentTypes(BirdMediaKind kind) =>
        kind == BirdMediaKind.Audio ? AllowedAudioContentTypes : AllowedImageContentTypes;

    public static long MaxSizeBytes(BirdMediaKind kind) =>
        kind == BirdMediaKind.Audio ? MaxAudioSizeBytes : MaxImageSizeBytes;
}
