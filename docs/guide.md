## Advanced Guides
> Optional Features & Configurations & Bug fixes

> [!NOTE]
> This guide is based on the completion of the previous phase.

---

### How to fix freezing/stopping issues during long-term use

#### Method 1) Try troubleshooting in the terminal environment

1. Create virtual memory settings with the following command.
```console
sudo dd if=/dev/zero of=/swapfile bs=1M count=8192 status=progress
```

2. Set the security policy.
```console
sudo chmod 600 /swapfile
```

3. Create the SWAP file (virtual memory).
```console
sudo mkswap /swapfile
```

4. Enable the SWAP file.
```console
sudo swapon /swapfile
```

5. The settings are applied after reboot.

#### Method 2) Troubleshooting in the Android environment

1. Use ADB and run one of the following commands.

**1) (Phantom) process settings**

> Changes limits on excessive background work for specific apps in Android.

* Increase max count to unlimited (`2147483647`)
```console
adb shell device_config put activity_manager max_phantom_processes 2147483647
```

or

* Disable max count restriction (behavior may vary by Android version, so using the command above is recommended)
```console
adb shell settings put global settings_enable_monitor_phantom_procs false
```

**2) Whitelist the terminal app in Android Doze mode**

> Add the app to exception list for Android battery restrictions.
```console
adb shell dumpsys deviceidle whitelist +com.android.virtualization.terminal
```

**3) Force app standby bucket to Active**

> Keeps the terminal app active.
```console
adb shell am set-standby-bucket com.android.virtualization.terminal active
```

2. Restart the terminal app.

> [!NOTE]
> **If the above steps do not apply, use the following as the final step:**
> 1. Open `/etc/environment` in a text editor.
> 2. Add the following lines. [renderer.sh](./snippets/environment/renderer.sh)
> 3. Save & close.

---

### How to fix screen color distortion

> If colors are inverted or displayed incorrectly (for example, red shown as blue), you can fix it via environment variables.

1. Open `/etc/environment` in a text editor.
2. Add the following line.
[color.sh](./snippets/environment/color.sh)
3. Save & close.

> [!TIP]
> Reboot is **recommended** to apply settings.

---

### How to enable/apply hardware acceleration (GPU)

> Recommended for faster AVF terminal performance.

> [!WARNING]
> This tutorial was written for general device specs and may not be suitable for all devices.

1. Use `adb` to run the following commands.
1-1. Enable GPU usage
```console
adb shell settings put global device_config:virtualizationservice:enable_gfxstream true
```

1-2. Improve GPU stability
```console
adb shell dumpsys deviceidle whitelist +com.android.virtualization.terminal
```

2. Open `/mnt/internal/linux/vm_config.json` in a text editor.
3. **Replace** **all the file content** with the following:
[vm_config.json](./snippets/vm_config.json)

5. **Add** the following content to `~/.config/weston.ini`:
[weston.toml](./snippets/weston.toml)

<!--

```console
sudo rmmod virtio_snd
echo "blacklist virtio_snd" | sudo tee /etc/modprobe.d/blacklist-virtio-snd.conf
pactl set-default-sink alsa_output.pci-0000_00_xx.0.analog-stereo
```

-->

5. Set permissions and verify graphics performance. Add the user to video/render groups to enable hardware acceleration.
```console
sudo usermod -aG video,render $USER
```

6. Reboot to apply settings. **Required**

> [!TIP]
> Settings are applied after reboot.

7. **After reboot**, run the following commands to verify permission application and hardware acceleration status.

```console
sudo apt install mesa-utils
glxinfo | grep -E "OpenGL vendor|OpenGL renderer"
```

---

### Download Chrome and configure policies

1. Download the Chrome installer.
```console
wget https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb
```

2. Run the Chrome installer.
```console
sudo apt install ./google-chrome-stable_current_arm64.deb
```

3. Optional: How to force-disable some unnecessary features (such as AI).
3-1. Open `/etc/opt/chrome/policies/managed/policy.json` in a text editor.
3-2. Add the following content to the file.

[policy.json](./snippets/chrome/policy.json)

3-3. Save & close.
3-4. Run the following command to set permission.
```console
sudo chmod 644 /etc/opt/chrome/policies/managed/policy.json
```

> [!TIP]
> Reboot is **recommended** to apply settings.

1. Done.

---

### Configure speaker connection

1. Run the `termux` app and enter the following command.
```console
pkg install pulseaudio termux-api jq 
```
2. Put **all** files from [termux](./snippets/speakers/termux) into the `~/.shortcuts/tasks` folder.
3. Save & close.
4. Run the AVF app.
5. Install required packages with the following command.
```console
sudo apt install pipewire pipewire-audio-client-libraries pipewire-pulse wireplumber
```
6. Use the following commands to create the folder and set permissions.
```console
mkdir -p ~/.local/bin/
sudo chmod -R 755 ~/.local/bin/
```
7. Put **all** files from [avf/bin](./snippets/speakers/avf/bin) into the `~/.local/bin` folder.
8. Use the following commands to set permissions for the service folder.
```console
mkdir -p ~/.config/systemd/user/
sudo chmod -R 755 ~/.config/systemd/user/
```
9. Put [audio_connect.service](./snippets/speakers/avf/audio_connect.service) into `~/.config/systemd/user/`.
10. Use the following commands to enable and start the audio service.
```console
systemctl --user --now enable pipewire pipewire-pulse wireplumber
systemctl --user daemon-reload
systemctl --user enable --now audio_connect.service
systemctl --user start audio_connect.service
systemctl --user status audio_connect.service
```
11. Add the following line to `~/.bashrc`.
```console
export PATH="$HOME/.local/bin:$PATH"
```

12. Done.

> [!NOTE]
> The settings are applied after reboot.

---

### Korean/English input method setup

1. Use the following command to install `fcitx5 input method`.
```console
sudo apt install fcitx5 fcitx5-config-qt fcitx5-hangul
```

2. Use the following command to set `fcitx5` as the default input method.
```console
im-config -n fcitx5
```

3. Add the following line to `~/.bashrc`.
```console
export XMODIFIERS=@im=fcitx
```

4. **Reboot.**
5. Use the following command to finalize additional settings.
```console
fcitx5-config-qt
```
