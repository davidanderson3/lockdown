# Lockdown Ready

Lockdown Ready is a desktop app for forcing a real break from screen time.

The idea is simple: when you decide it is time to step away, Lockdown Ready can shut down the usual distractions, lock the machine, and make it inconvenient to drift back into browsing, messaging, or coding "for just a minute."

## Platforms

- macOS app in `NightLockdownProject/NightLockdownApp`
- Windows app in `NightLockdownProject/LockdownReady.Windows`

## What It Does

- locks your machine during scheduled break windows
- lets you start an immediate lockdown for 30 minutes
- quits and force-kills distracting apps
- turns off Wi-Fi during lockdown when the OS allows it
- keeps running after the main window closes

## Main Controls

- **Start Lockdown (30 Minutes)** starts an immediate break session
- the main window lets you edit the recurring schedule, blocked apps, and check interval
- **Open Raw Config File** opens the JSON config directly
- **Reload From Disk** reloads settings from disk

## How Lockdown Works

During an active lockdown window, the app can:

- turn off Wi-Fi
- quit apps like browsers, chat apps, mail, music, games, or anything else you add to the blocked list
- force-kill stubborn apps that do not quit cleanly
- lock the screen or workstation so you have to consciously come back later
- hide its main controls so you cannot simply reopen the app and change settings mid-lockdown

Closing the app window does not stop enforcement. The app continues running in the background.

## Build

### macOS

From the workspace root:

```bash
./NightLockdownProject/build-night-lockdown-app.sh
```

This produces:

```text
./LockdownReady.app
```

Optional install:

```bash
./NightLockdownProject/build-night-lockdown-app.sh --install
```

### Windows

On Windows with the .NET 8 SDK installed, run:

```powershell
.\NightLockdownProject\build-lockdown-ready-windows.ps1
```

This publishes:

```text
.\LockdownReady.Windows\
```

Optional single-file publish:

```powershell
.\NightLockdownProject\build-lockdown-ready-windows.ps1 -SelfContained
```

## First Run Permissions

### macOS

macOS may ask for permission for:

- Notifications
- Apple Events / Automation, so the app can quit other apps
- Accessibility or Full Disk Access, depending on how your system handles the lockdown actions

### Windows

Windows may require elevated privileges for:

- disabling or enabling Wi-Fi adapters
- terminating some apps owned by another user or running elevated
- opening firewall or system-managed network interfaces

The Windows app still works without admin rights for scheduling, config management, tray behavior, and workstation locking, but Wi-Fi enforcement may fail unless it is run as administrator.

## Settings

Both apps store their config as JSON and use the same top-level fields:

- `blockWindows`
- `distractingApps`
- `checkIntervalSeconds`

macOS config path:

```text
~/Library/Application Support/LockdownReady/config.json
```

Windows config path:

```text
%AppData%\LockdownReady\config.json
```

On Windows, the blocked app list should generally use process names such as `chrome`, `msedge`, `slack`, or `code`.
