using System.Globalization;

namespace DoZore.Api.Features;

public sealed record Week(string Id, DateTimeOffset StartsAt, DateTimeOffset EndsAt);

/// <summary>Leaderboard weeks: ISO weeks, Monday 00:00 to Monday 00:00 Europe/Belgrade time.</summary>
public static class WeekCalendar
{
    static readonly TimeZoneInfo Belgrade = LoadBelgrade();

    public static Week Containing(DateTimeOffset instant)
    {
        var local = TimeZoneInfo.ConvertTime(instant, Belgrade).DateTime;
        return Of(ISOWeek.GetYear(local), ISOWeek.GetWeekOfYear(local));
    }

    public static Week Previous(Week week) => Containing(week.StartsAt.AddDays(-1));

    public static Week Of(int year, int week)
    {
        var monday = ISOWeek.ToDateTime(year, week, DayOfWeek.Monday);
        return new Week($"{year:D4}-W{week:D2}", ToUtc(monday), ToUtc(monday.AddDays(7)));
    }

    static DateTimeOffset ToUtc(DateTime localMidnight) =>
        new(TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(localMidnight, DateTimeKind.Unspecified), Belgrade), TimeSpan.Zero);

    static TimeZoneInfo LoadBelgrade()
    {
        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById("Europe/Belgrade");
        }
        catch (TimeZoneNotFoundException)
        {
            // Containers without tzdata: CET/CEST with EU daylight-saving rules.
            var rule = TimeZoneInfo.AdjustmentRule.CreateAdjustmentRule(
                DateTime.MinValue.Date, DateTime.MaxValue.Date, TimeSpan.FromHours(1),
                TimeZoneInfo.TransitionTime.CreateFloatingDateRule(new DateTime(1, 1, 1, 2, 0, 0), 3, 5, DayOfWeek.Sunday),
                TimeZoneInfo.TransitionTime.CreateFloatingDateRule(new DateTime(1, 1, 1, 3, 0, 0), 10, 5, DayOfWeek.Sunday));
            return TimeZoneInfo.CreateCustomTimeZone("Europe/Belgrade", TimeSpan.FromHours(1), "Europe/Belgrade", "CET", "CEST", [rule]);
        }
    }
}
