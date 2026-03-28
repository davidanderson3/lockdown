using System.Globalization;

namespace LockdownReady.Windows;

internal sealed class TimeWindow
{
    public static readonly IReadOnlyList<int> AllWeekdays = new[] { 1, 2, 3, 4, 5, 6, 7 };

    public List<int> Weekdays { get; set; } = new(AllWeekdays);
    public int StartMinutes { get; set; }
    public int EndMinutes { get; set; }

    public static TimeWindow FromHours(int startHour, int endHour)
    {
        return new TimeWindow
        {
            StartMinutes = startHour * 60,
            EndMinutes = endHour * 60,
            Weekdays = SanitizeWeekdays(AllWeekdays)
        };
    }

    public bool Contains(int minuteOfDay, int weekday)
    {
        var normalizedDays = SanitizeWeekdays(Weekdays);
        if (StartMinutes < EndMinutes)
        {
            return normalizedDays.Contains(weekday)
                && minuteOfDay >= StartMinutes
                && minuteOfDay < EndMinutes;
        }

        if (StartMinutes > EndMinutes)
        {
            var previousWeekday = weekday == 1 ? 7 : weekday - 1;
            return (normalizedDays.Contains(weekday) && minuteOfDay >= StartMinutes)
                || (normalizedDays.Contains(previousWeekday) && minuteOfDay < EndMinutes);
        }

        return false;
    }

    public string ToDisplayString()
    {
        return $"{DaySummary()} {FormatMinutes(StartMinutes)}-{FormatMinutes(EndMinutes)}";
    }

    public string DaysEditorText()
    {
        var days = SanitizeWeekdays(Weekdays);
        if (days.SequenceEqual(AllWeekdays))
        {
            return "Every day";
        }

        if (days.SequenceEqual(new[] { 2, 3, 4, 5, 6 }))
        {
            return "Weekdays";
        }

        if (days.SequenceEqual(new[] { 1, 7 }))
        {
            return "Weekends";
        }

        return string.Join(", ", days.Select(ShortWeekdayName));
    }

    public static string ShortWeekdayName(int weekday)
    {
        return weekday switch
        {
            1 => "Sun",
            2 => "Mon",
            3 => "Tue",
            4 => "Wed",
            5 => "Thu",
            6 => "Fri",
            7 => "Sat",
            _ => "?"
        };
    }

    public static string FormatMinutes(int minutes)
    {
        var clamped = Math.Clamp(minutes, 0, 23 * 60 + 59);
        var date = DateTime.Today.AddMinutes(clamped);
        return date.ToString("h:mm tt", CultureInfo.InvariantCulture);
    }

    public static List<int> SanitizeWeekdays(IEnumerable<int> weekdays)
    {
        var normalized = weekdays
            .Where(day => day is >= 1 and <= 7)
            .Distinct()
            .OrderBy(day => day)
            .ToList();

        return normalized.Count == 0 ? new List<int>(AllWeekdays) : normalized;
    }

    private string DaySummary()
    {
        var days = SanitizeWeekdays(Weekdays);
        if (days.SequenceEqual(AllWeekdays))
        {
            return "Every day";
        }

        if (days.SequenceEqual(new[] { 2, 3, 4, 5, 6 }))
        {
            return "Weekdays";
        }

        if (days.SequenceEqual(new[] { 1, 7 }))
        {
            return "Weekends";
        }

        return string.Join(", ", days.Select(ShortWeekdayName));
    }
}
