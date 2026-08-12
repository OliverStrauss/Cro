namespace CroApp.Api.Data;

public class BlobStorageOptions
{
    public string ConnectionString { get; set; } = string.Empty;
    public string ProfilePicturesContainerName { get; set; } = string.Empty;
    public string NestPicturesContainerName { get; set; } = string.Empty;
    public string BirdPicturesContainerName { get; set; } = string.Empty;
    public string BirdMediaContainerName { get; set; } = string.Empty;
}
