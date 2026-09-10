namespace CroApp.Api.Services;

// Validates that a bird's requested payload shape matches what its Type can carry: Cro is
// text-only (fastest), Parrot is audio-only, Pigeon is image-only (slowest), Raven carries
// both text and image. Operates on presence (hasMedia) rather than an actual URL, since this
// runs before any media upload happens - failing fast on an obviously wrong request shape
// shouldn't cost a blob upload.
public static class BirdPayloadValidator
{
    // Used by ComposeAndSendAsync: a freshly spawned bird must have its full payload up
    // front, since nothing about it exists yet to fall back on.
    public static void Validate(string type, string? content, bool hasMedia)
    {
        ValidateAllowed(type, content, hasMedia);
        var hasContent = !string.IsNullOrWhiteSpace(content);
        switch (type)
        {
            case BirdTypeCatalog.Cro:
                if (!hasContent) throw new ServiceException(400, "A Cro needs text content.");
                break;
            case BirdTypeCatalog.Parrot:
                if (!hasMedia) throw new ServiceException(400, "A Parrot needs an audio clip.");
                break;
            case BirdTypeCatalog.Pigeon:
                if (!hasMedia) throw new ServiceException(400, "A Pigeon needs an image.");
                break;
            case BirdTypeCatalog.Raven:
                if (!hasContent) throw new ServiceException(400, "A Raven needs text content.");
                if (!hasMedia) throw new ServiceException(400, "A Raven needs an image.");
                break;
        }
    }

    // Used by SendAsync: resending an already-existing bird onward doesn't have to carry a
    // fresh payload every leg (sending it home with nothing to say is fine), but it still can
    // never carry a payload shape its Type doesn't support - a Parrot is never texted, a Cro
    // never gets a file.
    public static void ValidateAllowed(string type, string? content, bool hasMedia)
    {
        var hasContent = !string.IsNullOrWhiteSpace(content);
        switch (type)
        {
            case BirdTypeCatalog.Cro:
                if (hasMedia) throw new ServiceException(400, "A Cro can't carry a file.");
                break;
            case BirdTypeCatalog.Parrot:
                if (hasContent) throw new ServiceException(400, "A Parrot can't carry text content.");
                break;
            case BirdTypeCatalog.Pigeon:
                if (hasContent) throw new ServiceException(400, "A Pigeon can't carry text content.");
                break;
            case BirdTypeCatalog.Raven:
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
