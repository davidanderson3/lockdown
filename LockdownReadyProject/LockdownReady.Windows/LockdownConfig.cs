namespace LockdownReady.Windows;

internal sealed class LockdownConfig
{
    public List<TimeWindow> BlockWindows { get; set; } = new();
    public double CheckIntervalSeconds { get; set; } = 60;

    public static LockdownConfig Default => new()
    {
        BlockWindows = new List<TimeWindow>
        {
            TimeWindow.FromHours(21, 8)
        },
        CheckIntervalSeconds = 60
    };
}
