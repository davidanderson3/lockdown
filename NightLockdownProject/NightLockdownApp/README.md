# Lockdown Ready

Lockdown Ready is a macOS app for forcing yourself to take a break from screen time.

The core idea is simple: when you decide it is time to step away from your MacBook, Lockdown Ready can shut down the usual distractions and lock the machine so you stop drifting back into browsing, messaging, or coding "for just a minute."

## What It Does

- Locks your Mac during scheduled break windows
- Lets you start an immediate lockdown for 30 minutes
- Quits and force-kills distracting apps
- Turns off Wi-Fi during lockdown
- Gives you a full settings window when lockdown is not active

## Why You Might Use It

- You want a harder boundary around evening screen time
- You keep reopening the same distracting apps when you meant to take a break
- You want your MacBook to become inconvenient enough that you actually step away
- You want a lightweight, local tool instead of a big parental-control or device-management system

## Main Controls

- **Start Lockdown (30 Minutes)** starts an immediate break session
- the main window includes your recurring schedule, blocked apps, and check interval on the first screen
- **Open Raw Config File** is available if you want to edit the JSON directly
- **Reload Config** reloads settings from disk

## How Lockdown Works

During an active lockdown window, the app can:

- turn off Wi-Fi
- quit apps like browsers, chat apps, mail, music, games, or anything else you add to the blocked list
- force-kill stubborn apps that do not quit cleanly
- lock the screen so you have to consciously come back later
- hide its main controls so you cannot simply reopen the app and change settings mid-lockdown

Closing the app window does not stop enforcement. The app continues running until you quit it.
If you close the window, the app moves into the macOS menu bar. When lockdown is active, the menu bar item shows status only and does not expose settings or quit controls.

## Build

From the workspace root:

```bash
./NightLockdownProject/build-night-lockdown-app.sh
```

This produces:

```bash
./LockdownReady.app
```

Optional install:

```bash
./NightLockdownProject/build-night-lockdown-app.sh --install
```

## First Run Permissions

macOS may ask for permission for:

- Notifications
- Apple Events / Automation, so the app can quit other apps
- Accessibility or Full Disk Access, depending on how your system handles the lockdown actions

Grant them in System Settings if you want reliable enforcement.

## Settings

The main app window is the main way to manage the app. It lets you edit:

- the weekly lockdown schedule with day-of-week selection and AM/PM time pickers
- the blocked app list
- the enforcement check interval

The app also stores its config file at:

```text
~/Library/Application Support/LockdownReady/config.json
```

If you want to inspect or edit the raw JSON, use **Open Raw Config File**.
