namespace CroApp.Api.Services;

// Shared between ProfilePictureService and NestPictureService - both are plain
// image-blob uploads with identical constraints, just keyed by a different id.
internal static class ImageUploadValidation
{
    public static readonly HashSet<string> AllowedContentTypes =
    [
        "image/png", "image/jpeg", "image/gif", "image/webp"
    ];

    public const long MaxSizeBytes = 5 * 1024 * 1024;
}
