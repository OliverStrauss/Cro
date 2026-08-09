namespace CroApp.Api.Data;

public class CosmosDbOptions
{
    public string ConnectionString { get; set; } = string.Empty;
    public string DatabaseName { get; set; } = string.Empty;
    public string UsersContainerName { get; set; } = string.Empty;
    public string WaypointsContainerName { get; set; } = string.Empty;
    public string BirdsContainerName { get; set; } = string.Empty;
    public bool UseEmulator { get; set; }
}
