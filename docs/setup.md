## Setup Guide

### 1. Enable the Linux Terminal Environment

To enable the Linux Terminal application in the Android Virtualization Framework (AVF), refer to the official guide below.

> Reference: [Android Terminal Setup Guide](https://dpocompliance.co.uk/en/posts/android-terminal/android-terminal/#how-to-set-it-up)

### 1-1. Use Linux Terminal in Full Screen

Use the following command to adjust the terminal app screen size.

```console
adb shell settings put global policy_control immersive.full=com.android.virtualization.terminal
```

> If you want to restore the screen size later, use the following command.
>
> ```console
> adb shell settings put global policy_control immersive.full=com.android.virtualization.terminal
> ```

### 2. Update and Upgrade System Packages

> For system security and stability, it is recommended to keep all packages up to date before installation.

Run the command below to refresh the local package index and perform a system upgrade.

```console
sudo apt update && sudo apt upgrade -y
```

> [!NOTE]
> If a confirmation prompt appears during upgrade, enter `Y`.

> [!TIP]
> If the Debian configuration interface appears, select the top item with the arrow keys and press <kbd>Enter</kbd> to continue.

### 3. Install the KDE Plasma Desktop Environment

> Install [KDE Plasma Desktop](https://kde.org/plasma-desktop), which provides a graphical desktop environment.

Run the command below to install KDE Standard desktop.

```console
sudo apt install kde-standard -y
```

> [!NOTE]
> You can install kde plasma desktop with other options.
> See [this](https://wiki.debian.org/KDE#Installation) for more information

> [!NOTE]
> If prompts appear during installation, refer to the caution in step 3 above and respond appropriately.

### 4. Restart the App and Connect Display

> After installation is complete, fully close and restart the terminal app.
> Once the terminal prompt is active, click the display icon at the top-right corner to enter the GUI environment.

> [!CAUTION]
> Clicking the display button before system load completes may cause connection errors.

### 5. User Login

Default credentials for system access are as follows.

- Username: droid
- Password: droid

> [!TIP]
> If items such as `droid` or `default user ~` appear on the login screen, select that account and enter the password.

> [!WARNING]
> The `debian` username is an Android system account.
> **Using this account may cause issues on the Android device.**