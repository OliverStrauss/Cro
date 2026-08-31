namespace CroApp.Api.Data;

public class CosmosDbOptions
{
    public string ConnectionString { get; set; } = string.Empty;
    public string DatabaseName { get; set; } = string.Empty;
    public string UsersContainerName { get; set; } = string.Empty;
    public string WaypointsContainerName { get; set; } = string.Empty;
    public string BirdsContainerName { get; set; } = string.Empty;
    public string HubsContainerName { get; set; } = string.Empty;
    public string HubPictureSuggestionsContainerName { get; set; } = string.Empty;
    public string ReactionsContainerName { get; set; } = string.Empty;
    public string HubMessagesContainerName { get; set; } = string.Empty;
    public string HubReadStatesContainerName { get; set; } = string.Empty;
    public string BirdReadStatesContainerName { get; set; } = string.Empty;
    public string EventsContainerName { get; set; } = string.Empty;
    public bool UseEmulator { get; set; }
    // Dev-only, off by default (only appsettings.Development.json turns it on - the test
    // project's own in-memory config never sets this key, so WebApplicationFactory-driven
    // test runs never trigger it). When true, every `dotnet run` wipes Users and reseeds the
    // fixed Admin/Test1/Test2/Oliver/Annie dev dataset via DevDataSeeder, in place of the
    // smaller idempotent "Oliver 1"/"Admin 1" seed.
    public bool SeedFixedDevUsersOnStartup { get; set; }
}
