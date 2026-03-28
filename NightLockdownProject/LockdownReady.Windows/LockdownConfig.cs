using System.Text.Json.Serialization;

namespace LockdownReady.Windows;

internal sealed class LockdownConfig
{
    [JsonPropertyName("blockWindows")]
    public List<TimeWindow> BlockWindows { get; set; } = new();

    [JsonPropertyName("distractingApps")]
    public List<string> DistractingApps { get; set; } = new();

    [JsonPropertyName("checkIntervalSeconds")]
    public double CheckIntervalSeconds { get; set; } = 60;

    public static LockdownConfig Default => new()
    {
        BlockWindows = new List<TimeWindow>
        {
            TimeWindow.FromHours(21, 8)
        },
        DistractingApps = new List<string>
        {
            "chrome",
            "firefox",
            "msedge",
            "brave",
            "arc",
            "slack",
            "discord",
            "outlook",
            "teams",
            "spotify",
            "steam",
            "code"
        },
        CheckIntervalSeconds = 60
    };
}
