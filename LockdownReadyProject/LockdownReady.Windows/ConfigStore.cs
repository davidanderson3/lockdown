using System.Text.Json;

namespace LockdownReady.Windows;

internal sealed class ConfigStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    public ConfigStore()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        ConfigDirectory = Path.Combine(appData, "LockdownReady");
        ConfigPath = Path.Combine(ConfigDirectory, "config.json");
    }

    public string ConfigDirectory { get; }
    public string ConfigPath { get; }

    public LockdownConfig LoadOrCreate()
    {
        Directory.CreateDirectory(ConfigDirectory);

        if (!File.Exists(ConfigPath))
        {
            var defaults = LockdownConfig.Default;
            Save(defaults);
            return defaults;
        }

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(ConfigPath));
            return Parse(document.RootElement);
        }
        catch
        {
            var defaults = LockdownConfig.Default;
            Save(defaults);
            return defaults;
        }
    }

    public void Save(LockdownConfig config)
    {
        Directory.CreateDirectory(ConfigDirectory);
        File.WriteAllText(ConfigPath, JsonSerializer.Serialize(config, JsonOptions));
    }

    private static LockdownConfig Parse(JsonElement root)
    {
        var config = LockdownConfig.Default;

        var windows = ParseWindows(root);
        if (windows.Count > 0)
        {
            config.BlockWindows = windows;
        }

        if (root.TryGetProperty("checkIntervalSeconds", out var intervalElement)
            && intervalElement.ValueKind == JsonValueKind.Number
            && intervalElement.TryGetDouble(out var intervalSeconds))
        {
            config.CheckIntervalSeconds = intervalSeconds;
        }

        return config;
    }

    private static List<TimeWindow> ParseWindows(JsonElement root)
    {
        var windows = new List<TimeWindow>();
        if (root.TryGetProperty("blockWindows", out var blockWindowsElement) && blockWindowsElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var windowElement in blockWindowsElement.EnumerateArray())
            {
                if (windowElement.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }

                var weekdays = new List<int>();
                if (windowElement.TryGetProperty("weekdays", out var weekdaysElement) && weekdaysElement.ValueKind == JsonValueKind.Array)
                {
                    foreach (var item in weekdaysElement.EnumerateArray())
                    {
                        if (item.ValueKind == JsonValueKind.Number && item.TryGetInt32(out var day))
                        {
                            weekdays.Add(day);
                        }
                    }
                }

                if (!windowElement.TryGetProperty("startMinutes", out var startElement)
                    || !windowElement.TryGetProperty("endMinutes", out var endElement)
                    || !startElement.TryGetInt32(out var startMinutes)
                    || !endElement.TryGetInt32(out var endMinutes))
                {
                    continue;
                }

                windows.Add(new TimeWindow
                {
                    Weekdays = TimeWindow.SanitizeWeekdays(weekdays),
                    StartMinutes = startMinutes,
                    EndMinutes = endMinutes
                });
            }
        }

        if (windows.Count > 0)
        {
            return windows;
        }

        var startHour = 21;
        var endHour = 8;

        if (root.TryGetProperty("blockStartHour", out var startHourElement)
            && startHourElement.ValueKind == JsonValueKind.Number
            && startHourElement.TryGetInt32(out var parsedStartHour))
        {
            startHour = parsedStartHour;
        }

        if (root.TryGetProperty("blockEndHour", out var endHourElement)
            && endHourElement.ValueKind == JsonValueKind.Number
            && endHourElement.TryGetInt32(out var parsedEndHour))
        {
            endHour = parsedEndHour;
        }

        return new List<TimeWindow> { TimeWindow.FromHours(startHour, endHour) };
    }
}
