using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace LockdownReady.Windows;

internal sealed class MainForm : Form
{
    private const int ManualLockMinutes = 30;
    private static readonly string[] TimeFormats =
    {
        "H:mm",
        "HH:mm",
        "h:mm tt",
        "hh:mm tt",
        "h tt",
        "htt"
    };

    private readonly ConfigStore _configStore = new();
    private readonly System.Windows.Forms.Timer _timer = new();
    private readonly NotifyIcon _notifyIcon = new();
    private readonly Label _stateLabel = new();
    private readonly Label _detailLabel = new();
    private readonly Label _scheduleSummaryLabel = new();
    private readonly DataGridView _scheduleGrid = new();
    private readonly SchedulePreviewPanel _schedulePreview = new();
    private readonly Button _startButton = new();
    private readonly Button _saveButton = new();
    private readonly Button _quitButton = new();

    private LockdownConfig _config;
    private DateTimeOffset? _manualLockUntil;
    private bool _hasLockedInCurrentWindow;
    private bool _allowExit;
    private bool _hideNoticeShown;

    public MainForm()
    {
        _config = _configStore.LoadOrCreate();

        InitializeComponent();
        LoadConfigIntoEditor();
        StartScheduler();
        RunEnforcementCycle("startup");
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        if (IsLockdownActive())
        {
            HideToTray(showNotice: false);
        }
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        if (WindowState == FormWindowState.Minimized)
        {
            HideToTray(showNotice: false);
        }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        var systemClose = e.CloseReason == CloseReason.WindowsShutDown
            || e.CloseReason == CloseReason.TaskManagerClosing;

        if (!_allowExit && !systemClose)
        {
            e.Cancel = true;
            HideToTray(showNotice: false);
            return;
        }

        _notifyIcon.Visible = false;
        EnableWiFi();
        base.OnFormClosing(e);
    }

    private void InitializeComponent()
    {
        Text = "Lockdown Ready";
        MinimumSize = new Size(900, 720);
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(1060, 780);

        _timer.Tick += (_, _) => RunEnforcementCycle("timer");

        _notifyIcon.Icon = SystemIcons.Information;
        _notifyIcon.Text = "Lockdown Ready";
        _notifyIcon.DoubleClick += (_, _) => ShowWindowFromTray();

        _stateLabel.AutoSize = true;
        _stateLabel.Font = new Font(Font, FontStyle.Bold);
        _stateLabel.Font = new Font(_stateLabel.Font.FontFamily, 20, FontStyle.Bold);

        _detailLabel.AutoSize = true;
        _detailLabel.MaximumSize = new Size(980, 0);
        _detailLabel.ForeColor = Color.DimGray;

        _scheduleSummaryLabel.AutoSize = true;
        _scheduleSummaryLabel.ForeColor = Color.DimGray;
        _scheduleSummaryLabel.MaximumSize = new Size(980, 0);

        _scheduleGrid.Dock = DockStyle.Fill;
        _scheduleGrid.AllowUserToResizeRows = false;
        _scheduleGrid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        _scheduleGrid.ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.AutoSize;
        _scheduleGrid.RowHeadersVisible = false;
        _scheduleGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Days", Name = "Days" });
        _scheduleGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Start", Name = "Start" });
        _scheduleGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "End", Name = "End" });
        _scheduleGrid.CellEndEdit += (_, _) => UpdateSchedulePreviewFromEditor();
        _scheduleGrid.RowsAdded += (_, _) => UpdateSchedulePreviewFromEditor();
        _scheduleGrid.RowsRemoved += (_, _) => UpdateSchedulePreviewFromEditor();
        _scheduleGrid.UserDeletedRow += (_, _) => UpdateSchedulePreviewFromEditor();

        _schedulePreview.Dock = DockStyle.Fill;
        _schedulePreview.Margin = new Padding(0, 8, 0, 0);
        _schedulePreview.MinimumSize = new Size(0, 220);
        _schedulePreview.Height = 220;

        _startButton.Text = "Start Lockdown (30 Minutes)";
        _startButton.AutoSize = true;
        _startButton.Click += (_, _) => StartManualLockdown();

        _saveButton.Text = "Save Settings";
        _saveButton.AutoSize = true;
        _saveButton.Click += (_, _) => SaveSettings();

        _quitButton.Text = "Quit";
        _quitButton.AutoSize = true;
        _quitButton.Click += (_, _) => QuitApplication();

        var introLabel = new Label
        {
            AutoSize = true,
            ForeColor = Color.DimGray,
            Text = "Lock your Windows machine when you need a real break. Use the tray icon to keep the app running after this window closes."
        };

        var scheduleLabel = new Label
        {
            AutoSize = true,
            Font = new Font(Font, FontStyle.Bold),
            Text = "Recurring Lockdown Windows"
        };

        var scheduleHelp = new Label
        {
            AutoSize = true,
            ForeColor = Color.DimGray,
            Text = "Enter one row per window. Days can be Every day, Weekdays, Weekends, or a comma-separated list like Mon, Tue, Thu. Times can be 21:00 or 9:00 PM."
        };

        var schedulePreviewLabel = new Label
        {
            AutoSize = true,
            Font = new Font(Font, FontStyle.Bold),
            Text = "Blocked Time Preview"
        };

        var buttonPanel = new FlowLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true
        };
        buttonPanel.Controls.AddRange(new Control[]
        {
            _startButton,
            _saveButton,
            _quitButton
        });

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true,
            ColumnCount = 1,
            Padding = new Padding(18)
        };
        root.RowStyles.Clear();
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 50));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        root.Controls.Add(_stateLabel, 0, 0);
        root.Controls.Add(_detailLabel, 0, 1);
        root.Controls.Add(introLabel, 0, 2);

        var schedulePanel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 5,
            AutoSize = true
        };
        schedulePanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        schedulePanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        schedulePanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        schedulePanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        schedulePanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        schedulePanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 220));
        schedulePanel.Controls.Add(scheduleLabel, 0, 0);
        schedulePanel.Controls.Add(scheduleHelp, 0, 1);
        schedulePanel.Controls.Add(_scheduleGrid, 0, 2);
        schedulePanel.Controls.Add(_scheduleSummaryLabel, 0, 3);
        schedulePanel.Controls.Add(schedulePreviewLabel, 0, 4);
        schedulePanel.Controls.Add(_schedulePreview, 0, 5);
        root.Controls.Add(schedulePanel, 0, 3);

        root.Controls.Add(buttonPanel, 0, 4);

        Controls.Add(root);
    }

    private void LoadConfigIntoEditor()
    {
        _scheduleGrid.Rows.Clear();
        foreach (var window in _config.BlockWindows)
        {
            _scheduleGrid.Rows.Add(
                window.DaysEditorText(),
                TimeWindow.FormatMinutes(window.StartMinutes),
                TimeWindow.FormatMinutes(window.EndMinutes));
        }

        UpdateSchedulePreviewFromEditor();
        RefreshUi();
    }

    private void SaveSettings()
    {
        if (!TryBuildConfigFromEditor(out var newConfig, out var error))
        {
            MessageBox.Show(this, error, "Invalid settings", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        _config = newConfig;
        _configStore.Save(_config);
        StartScheduler();
        RunEnforcementCycle("config-update");
        ShowBalloonTip("Lockdown Ready", "Lockdown settings updated.");
    }

    private void ReloadConfig()
    {
        _config = _configStore.LoadOrCreate();
        LoadConfigIntoEditor();
        StartScheduler();
        RunEnforcementCycle("reload");
        ShowBalloonTip("Lockdown Ready", "Configuration reloaded.");
    }

    private void OpenConfigFile()
    {
        Directory.CreateDirectory(_configStore.ConfigDirectory);
        if (!File.Exists(_configStore.ConfigPath))
        {
            _configStore.Save(_config);
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = _configStore.ConfigPath,
            UseShellExecute = true
        });
    }

    private void QuitApplication()
    {
        if (IsLockdownActive())
        {
            return;
        }

        _allowExit = true;
        Close();
    }

    private void StartManualLockdown()
    {
        var result = MessageBox.Show(
            this,
            "This will start lockdown immediately for 30 minutes, turn off Wi-Fi, and lock the machine. Continue?",
            "Start Lockdown",
            MessageBoxButtons.OKCancel,
            MessageBoxIcon.Warning);

        if (result != DialogResult.OK)
        {
            return;
        }

        _manualLockUntil = DateTimeOffset.Now.AddMinutes(ManualLockMinutes);
        RunEnforcementCycle("manual-start");
    }

    private void StartScheduler()
    {
        var intervalMs = (int)Math.Clamp(_config.CheckIntervalSeconds * 1000, 15_000, 3_600_000);
        _timer.Interval = intervalMs;
        _timer.Start();
    }

    private void RunEnforcementCycle(string trigger)
    {
        var now = DateTimeOffset.Now;
        var scheduledLock = InBlockWindow(now);
        var manualLock = IsManualLockActive(now);

        if (!scheduledLock && !manualLock)
        {
            _hasLockedInCurrentWindow = false;
            EnableWiFi();
            RefreshUi();
            return;
        }

        DisableWiFi();
        QuitApps();
        HideToTray(showNotice: trigger == "startup" || trigger == "manual-start");

        if (!_hasLockedInCurrentWindow || string.Equals(trigger, "manual-start", StringComparison.Ordinal))
        {
            LockWorkStation();
            _hasLockedInCurrentWindow = true;

            var body = manualLock && !scheduledLock
                ? "Manual lockdown started for 30 minutes."
                : "Lockdown enforced.";
            ShowBalloonTip("Lockdown Ready", body);
        }

        RefreshUi();
    }

    private void RefreshUi()
    {
        var now = DateTimeOffset.Now;
        var active = IsLockdownActive(now);
        var stateText = BuildStateText(now, out var detailText, out var stateColor);

        _stateLabel.Text = stateText;
        _stateLabel.ForeColor = stateColor;
        _detailLabel.Text = detailText;

        _notifyIcon.Icon = active ? SystemIcons.Shield : SystemIcons.Information;
        _notifyIcon.Text = active ? "Lockdown Ready: Active" : "Lockdown Ready";
        _startButton.Enabled = !active;
        _saveButton.Enabled = !active;
        _quitButton.Enabled = !active;
        UpdateTrayMenu(now);
    }

    private string BuildStateText(DateTimeOffset now, out string detailText, out Color color)
    {
        if (_manualLockUntil.HasValue && now < _manualLockUntil.Value)
        {
            color = Color.Firebrick;
            detailText = $"Manual lockdown ends {FormatRelative(_manualLockUntil.Value, now)}.";
            return "LOCKED NOW";
        }

        if (InBlockWindow(now))
        {
            color = Color.Firebrick;
            detailText = "The current schedule is active.";
            return "LOCKDOWN ACTIVE";
        }

        color = Color.RoyalBlue;
        detailText = "Closing this window does not stop enforcement.";
        return "LOCKDOWN READY";
    }

    private void UpdateTrayMenu(DateTimeOffset now)
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem(StateLine(now)) { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());

        if (IsLockdownActive(now))
        {
            menu.Items.Add(new ToolStripMenuItem("Lockdown active. Controls unavailable.") { Enabled = false });
        }
        else
        {
            menu.Items.Add("Show Window", null, (_, _) => ShowWindowFromTray());
            menu.Items.Add("Start Lockdown (30 Minutes)", null, (_, _) => StartManualLockdown());
            menu.Items.Add("Reload From Disk", null, (_, _) => ReloadConfig());
            menu.Items.Add("Quit", null, (_, _) => QuitApplication());
        }

        var oldMenu = _notifyIcon.ContextMenuStrip;
        _notifyIcon.ContextMenuStrip = menu;
        oldMenu?.Dispose();
        _notifyIcon.Visible = !Visible || IsLockdownActive(now);
    }

    private void ShowWindowFromTray()
    {
        if (IsLockdownActive())
        {
            ShowBalloonTip("Lockdown Ready", "Lockdown is active. Controls are unavailable until the window ends.");
            return;
        }

        ShowInTaskbar = true;
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
        _notifyIcon.Visible = false;
        _hideNoticeShown = false;
    }

    private void HideToTray(bool showNotice)
    {
        ShowInTaskbar = false;
        Hide();
        _notifyIcon.Visible = true;
        UpdateTrayMenu(DateTimeOffset.Now);

        if (showNotice && !_hideNoticeShown)
        {
            ShowBalloonTip("Lockdown Ready", "Window hidden. Lockdown Ready is still running in the tray.");
            _hideNoticeShown = true;
        }
    }

    private bool TryBuildConfigFromEditor(out LockdownConfig config, out string error)
    {
        var windows = new List<TimeWindow>();
        for (var rowIndex = 0; rowIndex < _scheduleGrid.Rows.Count; rowIndex++)
        {
            var row = _scheduleGrid.Rows[rowIndex];
            if (row.IsNewRow)
            {
                continue;
            }

            var daysText = Convert.ToString(row.Cells[0].Value)?.Trim() ?? string.Empty;
            var startText = Convert.ToString(row.Cells[1].Value)?.Trim() ?? string.Empty;
            var endText = Convert.ToString(row.Cells[2].Value)?.Trim() ?? string.Empty;

            if (string.IsNullOrWhiteSpace(daysText) && string.IsNullOrWhiteSpace(startText) && string.IsNullOrWhiteSpace(endText))
            {
                continue;
            }

            if (!TryParseDays(daysText, out var weekdays))
            {
                config = LockdownConfig.Default;
                error = $"Schedule row {rowIndex + 1} has an invalid day list.";
                return false;
            }

            if (!TryParseTimeMinutes(startText, out var startMinutes))
            {
                config = LockdownConfig.Default;
                error = $"Schedule row {rowIndex + 1} has an invalid start time.";
                return false;
            }

            if (!TryParseTimeMinutes(endText, out var endMinutes))
            {
                config = LockdownConfig.Default;
                error = $"Schedule row {rowIndex + 1} has an invalid end time.";
                return false;
            }

            windows.Add(new TimeWindow
            {
                Weekdays = weekdays,
                StartMinutes = startMinutes,
                EndMinutes = endMinutes
            });
        }

        if (windows.Count == 0)
        {
            config = LockdownConfig.Default;
            error = "Add at least one lockdown window.";
            return false;
        }

        config = new LockdownConfig
        {
            BlockWindows = windows,
            DistractingApps = new List<string>(_config.DistractingApps),
            CheckIntervalSeconds = _config.CheckIntervalSeconds
        };
        error = string.Empty;
        return true;
    }

    private void UpdateSchedulePreviewFromEditor()
    {
        var windows = new List<TimeWindow>();
        for (var rowIndex = 0; rowIndex < _scheduleGrid.Rows.Count; rowIndex++)
        {
            var row = _scheduleGrid.Rows[rowIndex];
            if (row.IsNewRow)
            {
                continue;
            }

            var daysText = Convert.ToString(row.Cells[0].Value)?.Trim() ?? string.Empty;
            var startText = Convert.ToString(row.Cells[1].Value)?.Trim() ?? string.Empty;
            var endText = Convert.ToString(row.Cells[2].Value)?.Trim() ?? string.Empty;

            if (string.IsNullOrWhiteSpace(daysText) && string.IsNullOrWhiteSpace(startText) && string.IsNullOrWhiteSpace(endText))
            {
                continue;
            }

            if (!TryParseDays(daysText, out var weekdays))
            {
                continue;
            }

            if (!TryParseTimeMinutes(startText, out var startMinutes))
            {
                continue;
            }

            if (!TryParseTimeMinutes(endText, out var endMinutes))
            {
                continue;
            }

            if (startMinutes == endMinutes)
            {
                continue;
            }

            windows.Add(new TimeWindow
            {
                Weekdays = weekdays,
                StartMinutes = startMinutes,
                EndMinutes = endMinutes
            });
        }

        _scheduleSummaryLabel.Text = windows.Count == 0
            ? "Schedule: None"
            : "Schedule: " + string.Join(", ", windows.Select(window => window.ToDisplayString()));
        _schedulePreview.SetWindows(windows);
    }

    private bool TryParseDays(string text, out List<int> weekdays)
    {
        weekdays = new List<int>();
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        if (string.Equals(text, "Every day", StringComparison.OrdinalIgnoreCase))
        {
            weekdays = new List<int>(TimeWindow.AllWeekdays);
            return true;
        }

        if (string.Equals(text, "Weekdays", StringComparison.OrdinalIgnoreCase))
        {
            weekdays = new List<int> { 2, 3, 4, 5, 6 };
            return true;
        }

        if (string.Equals(text, "Weekends", StringComparison.OrdinalIgnoreCase))
        {
            weekdays = new List<int> { 1, 7 };
            return true;
        }

        var dayMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            ["sun"] = 1,
            ["sunday"] = 1,
            ["mon"] = 2,
            ["monday"] = 2,
            ["tue"] = 3,
            ["tues"] = 3,
            ["tuesday"] = 3,
            ["wed"] = 4,
            ["wednesday"] = 4,
            ["thu"] = 5,
            ["thur"] = 5,
            ["thurs"] = 5,
            ["thursday"] = 5,
            ["fri"] = 6,
            ["friday"] = 6,
            ["sat"] = 7,
            ["saturday"] = 7
        };

        foreach (var token in text.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!dayMap.TryGetValue(token, out var day))
            {
                return false;
            }

            weekdays.Add(day);
        }

        weekdays = TimeWindow.SanitizeWeekdays(weekdays);
        return weekdays.Count > 0;
    }

    private bool TryParseTimeMinutes(string text, out int minutes)
    {
        minutes = 0;
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        if (TimeSpan.TryParse(text, CultureInfo.InvariantCulture, out var span))
        {
            minutes = Math.Clamp((int)span.TotalMinutes, 0, 23 * 60 + 59);
            return true;
        }

        if (DateTime.TryParseExact(text, TimeFormats, CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out var dateTime))
        {
            minutes = dateTime.Hour * 60 + dateTime.Minute;
            return true;
        }

        return false;
    }

    private bool InBlockWindow(DateTimeOffset now)
    {
        var weekday = ((int)now.DayOfWeek + 1);
        var minuteOfDay = now.Hour * 60 + now.Minute;
        return _config.BlockWindows.Any(window => window.Contains(minuteOfDay, weekday));
    }

    private bool IsManualLockActive(DateTimeOffset now)
    {
        if (!_manualLockUntil.HasValue)
        {
            return false;
        }

        if (now < _manualLockUntil.Value)
        {
            return true;
        }

        _manualLockUntil = null;
        return false;
    }

    private bool IsLockdownActive()
    {
        return IsLockdownActive(DateTimeOffset.Now);
    }

    private bool IsLockdownActive(DateTimeOffset now)
    {
        return InBlockWindow(now) || IsManualLockActive(now);
    }

    private string ScheduleSummary()
    {
        return "Schedule: " + string.Join(", ", _config.BlockWindows.Select(window => window.ToDisplayString()));
    }

    private string StateLine(DateTimeOffset now)
    {
        var state = "Idle";
        if (_manualLockUntil.HasValue && now < _manualLockUntil.Value)
        {
            state = $"ACTIVE (manual, ends {FormatRelative(_manualLockUntil.Value, now)})";
        }
        else if (InBlockWindow(now))
        {
            state = "ACTIVE";
        }

        return $"{state} - {string.Join(", ", _config.BlockWindows.Select(window => window.ToDisplayString()))}";
    }

    private static string FormatRelative(DateTimeOffset future, DateTimeOffset now)
    {
        var remaining = future - now;
        if (remaining.TotalMinutes < 1)
        {
            return "in under a minute";
        }

        if (remaining.TotalHours < 1)
        {
            return $"in {Math.Ceiling(remaining.TotalMinutes)} minutes";
        }

        return $"in {Math.Ceiling(remaining.TotalHours)} hours";
    }

    private void DisableWiFi()
    {
        foreach (var interfaceName in GetWifiInterfaceNames())
        {
            RunBestEffort("netsh", $"interface set interface name=\"{interfaceName}\" admin=DISABLED");
        }
    }

    private void EnableWiFi()
    {
        foreach (var interfaceName in GetWifiInterfaceNames())
        {
            RunBestEffort("netsh", $"interface set interface name=\"{interfaceName}\" admin=ENABLED");
        }
    }

    private static IEnumerable<string> GetWifiInterfaceNames()
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        var wlanOutput = RunProcess("netsh", "wlan show interfaces");
        foreach (var line in SplitLines(wlanOutput))
        {
            var trimmed = line.Trim();
            if (!trimmed.StartsWith("Name", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var parts = trimmed.Split(':', 2);
            if (parts.Length == 2)
            {
                var name = parts[1].Trim();
                if (!string.IsNullOrWhiteSpace(name))
                {
                    names.Add(name);
                }
            }
        }

        var interfaceOutput = RunProcess("netsh", "interface show interface");
        foreach (var line in SplitLines(interfaceOutput))
        {
            var trimmed = line.Trim();
            if (string.IsNullOrWhiteSpace(trimmed)
                || trimmed.StartsWith("Admin State", StringComparison.OrdinalIgnoreCase)
                || trimmed.StartsWith("---", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var columns = Regex.Split(trimmed, "\\s{2,}");
            if (columns.Length < 4)
            {
                continue;
            }

            var name = columns[^1].Trim();
            if (LooksLikeWifiInterface(name))
            {
                names.Add(name);
            }
        }

        if (names.Count == 0)
        {
            foreach (var fallback in new[] { "Wi-Fi", "WiFi", "WLAN", "Wireless Network Connection" })
            {
                names.Add(fallback);
            }
        }

        return names;
    }

    private void QuitApps()
    {
        foreach (var process in Process.GetProcesses())
        {
            try
            {
                if (!MatchesBlockedApp(process))
                {
                    continue;
                }

                if (!process.CloseMainWindow())
                {
                    continue;
                }
            }
            catch
            {
            }
        }
    }

    private bool MatchesBlockedApp(Process process)
    {
        foreach (var appName in _config.DistractingApps)
        {
            foreach (var candidate in ExpandAliases(appName))
            {
                if (string.IsNullOrWhiteSpace(candidate))
                {
                    continue;
                }

                var normalizedProcessName = NormalizeToken(process.ProcessName);
                if (string.Equals(normalizedProcessName, candidate, StringComparison.Ordinal))
                {
                    return true;
                }

                var windowTitle = NormalizeToken(process.MainWindowTitle);
                if (!string.IsNullOrWhiteSpace(windowTitle) && windowTitle.Contains(candidate, StringComparison.Ordinal))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static IEnumerable<string> ExpandAliases(string appName)
    {
        var normalized = NormalizeToken(appName);
        if (string.IsNullOrWhiteSpace(normalized))
        {
            yield break;
        }

        yield return normalized;

        switch (normalized)
        {
            case "googlechrome":
                yield return "chrome";
                break;
            case "microsoftedge":
            case "edge":
                yield return "msedge";
                break;
            case "visualstudiocode":
                yield return "code";
                break;
            case "mail":
            case "outlook":
                yield return "outlook";
                break;
        }
    }

    private static string NormalizeToken(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var normalized = Regex.Replace(value, "[^a-z0-9]", string.Empty, RegexOptions.IgnoreCase).ToLowerInvariant();
        return normalized.EndsWith("exe", StringComparison.Ordinal) ? normalized[..^3] : normalized;
    }

    private static bool LooksLikeWifiInterface(string name)
    {
        var normalized = name.ToLowerInvariant();
        return normalized.Contains("wi-fi")
            || normalized.Contains("wifi")
            || normalized.Contains("wireless")
            || normalized.Contains("wlan");
    }

    private void ShowBalloonTip(string title, string text)
    {
        _notifyIcon.Visible = true;
        _notifyIcon.ShowBalloonTip(4000, title, text, ToolTipIcon.Info);
    }

    private static IEnumerable<string> SplitLines(string text)
    {
        return text.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
    }

    private static string RunProcess(string fileName, string arguments)
    {
        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = fileName,
                    Arguments = arguments,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };

            process.Start();
            var output = process.StandardOutput.ReadToEnd();
            _ = process.StandardError.ReadToEnd();
            process.WaitForExit(5000);
            return output;
        }
        catch
        {
            return string.Empty;
        }
    }

    private static void RunBestEffort(string fileName, string arguments)
    {
        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = fileName,
                    Arguments = arguments,
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };

            process.Start();
            process.WaitForExit(5000);
        }
        catch
        {
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool LockWorkStation();
}

internal sealed class SchedulePreviewPanel : Control
{
    private IReadOnlyList<TimeWindow> _windows = Array.Empty<TimeWindow>();

    public SchedulePreviewPanel()
    {
        DoubleBuffered = true;
        ResizeRedraw = true;
        BackColor = Color.White;
        ForeColor = Color.Black;
    }

    public void SetWindows(IReadOnlyList<TimeWindow> windows)
    {
        _windows = windows;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        var g = e.Graphics;
        g.Clear(Color.White);

        var bounds = ClientRectangle;
        if (bounds.Width < 220 || bounds.Height < 140)
        {
            return;
        }

        const float leftLabelWidth = 42f;
        const float topInset = 12f;
        const float rightInset = 12f;
        const float bottomInset = 28f;
        var chartRect = new RectangleF(
            leftLabelWidth,
            topInset,
            bounds.Width - leftLabelWidth - rightInset,
            bounds.Height - topInset - bottomInset);

        if (chartRect.Width <= 0 || chartRect.Height <= 0)
        {
            return;
        }

        var rowHeight = chartRect.Height / 7f;
        var columnWidth = chartRect.Width / 24f;
        using var labelBrush = new SolidBrush(Color.Black);
        using var blockedBrush = new SolidBrush(Color.FromArgb(190, 68, 122, 224));
        using var openBrush = new SolidBrush(Color.FromArgb(245, 245, 245));
        using var borderPen = new Pen(Color.FromArgb(205, 205, 205));
        using var outerPen = new Pen(Color.FromArgb(160, 160, 160));
        using var font = new Font(Font.FontFamily, 9f, FontStyle.Regular);
        var labelFormat = new StringFormat
        {
            Alignment = StringAlignment.Near,
            LineAlignment = StringAlignment.Center
        };

        for (var weekday = 1; weekday <= 7; weekday++)
        {
            var y = chartRect.Top + (weekday - 1) * rowHeight;
            var labelRect = new RectangleF(4f, y, leftLabelWidth - 8f, rowHeight);
            g.DrawString(TimeWindow.ShortWeekdayName(weekday), font, labelBrush, labelRect, labelFormat);

            for (var hour = 0; hour < 24; hour++)
            {
                var cellRect = new RectangleF(
                    chartRect.Left + hour * columnWidth,
                    y,
                    columnWidth,
                    rowHeight);
                var blocked = _windows.Any(window => HourIntersects(window, weekday, hour));
                g.FillRectangle(blocked ? blockedBrush : openBrush, cellRect);
                g.DrawRectangle(borderPen, cellRect.X, cellRect.Y, cellRect.Width, cellRect.Height);
            }
        }

        g.DrawRectangle(outerPen, chartRect.X, chartRect.Y, chartRect.Width, chartRect.Height);

        var hourLabels = new (int Hour, string Label)[]
        {
            (0, "12a"),
            (6, "6a"),
            (12, "12p"),
            (18, "6p"),
            (24, "12a")
        };

        foreach (var (hour, label) in hourLabels)
        {
            var x = chartRect.Left + hour * columnWidth;
            var size = g.MeasureString(label, font);
            var drawX = Math.Min(Math.Max(chartRect.Left, x - size.Width / 2f), chartRect.Right - size.Width);
            g.DrawString(label, font, labelBrush, drawX, chartRect.Bottom + 4f);
        }
    }

    private static bool HourIntersects(TimeWindow window, int weekday, int hour)
    {
        var startMinute = hour * 60;
        return window.Contains(startMinute, weekday)
            || window.Contains(startMinute + 15, weekday)
            || window.Contains(startMinute + 30, weekday)
            || window.Contains(startMinute + 45, weekday);
    }
}
