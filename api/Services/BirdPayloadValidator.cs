namespace CroApp.Api.Services;

// Validates that a composed bird's requested payload shape matches what its Type requires,
// before any media upload happens: Cro is text-only (fastest), Parrot is audio-only, Pigeon
// is image-only (slowest), Raven requires both text and image. Operates on presence
// (hasMedia) rather than an actual URL, since this runs before ComposeAndSendAsync uploads
// anything - failing fast on an obviously wrong request shape shouldn't cost a blob upload.
public static class BirdPayloadValidator
{
    public static void Validate(string type, string? content, bool hasMedia)
    {
        var hasContent = !string.IsNullOrWhiteSpace(content);
        switch (type)
        {
            case BirdTypeCatalog.Cro:
                if (!hasContent) throw new ServiceException(400, "A Cro needs text content.");
                if (hasMedia) throw new ServiceException(400, "A Cro can't carry a file.");
                break;
            case BirdTypeCatalog.Parrot:
                if (!hasMedia) throw new ServiceException(400, "A Parrot needs an audio clip.");
                if (hasContent) throw new ServiceException(400, "A Parrot can't carry text content.");
                break;
            case BirdTypeCatalog.Pigeon:
                if (!hasMedia) throw new ServiceException(400, "A Pigeon needs an image.");
                if (hasContent) throw new ServiceException(400, "A Pigeon can't carry text content.");
                break;
            case BirdTypeCatalog.Raven:
                if (!hasContent) throw new ServiceException(400, "A Raven needs text content.");
                if (!hasMedia) throw new ServiceException(400, "A Raven needs an image.");
                break;
            default:
                throw new ServiceException(400, $"Unknown bird type '{type}'.");
        }
    }

    // Only meaningful for types BirdPayloadValidator.Validate already confirmed require
    // media - Cro never reaches this.
    public static BirdMediaKind MediaKindForType(string type) => type switch
    {
        BirdTypeCatalog.Parrot => BirdMediaKind.Audio,
        BirdTypeCatalog.Pigeon => BirdMediaKind.Image,
        BirdTypeCatalog.Raven => BirdMediaKind.Image,
        _ => throw new InvalidOperationException($"Bird type '{type}' has no media payload."),
    };
}
