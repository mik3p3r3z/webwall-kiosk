# webwall-kiosk
An automated Linux Mint kiosk solution for deploying and managing a four-monitor portrait web display. Webwall installs and configures the operating system, kiosk environment, display layout, and automated website capture to create a reliable digital signage or monitoring system.

## Features

* Automated Linux Mint kiosk setup
* Chromium-based kiosk mode
* Four-monitor portrait display configuration using `xrandr`
* Automatic installation and configuration of required applications
* Website screenshot capture and validation
* Prevents failed or incomplete page loads from replacing active images
* Automatic startup configuration
* Easily customizable websites and display settings

---

# Scope

Webwall is designed to automate the deployment of a multi-monitor web display system that requires minimal maintenance after installation. It is ideal for:

* Digital signage
* Operations dashboards
* Network monitoring
* News displays
* Security monitoring
* Status boards
* Information kiosks

The project automates:

* Linux Mint kiosk configuration
* Display layout
* Required software installation
* Browser configuration
* Website image capture
* Image validation
* Automatic display updates

The project does **not** include:

* Remote management
* Centralized administration
* User authentication
* Dashboard creation
* Web hosting
* Support for arbitrary monitor layouts without modifying the configuration scripts

---

# Installation

## Requirements

* Linux Mint XFCE 22.3
* Four DisplayPort monitors (recommended)
* Internet connection during installation

## Installation Steps

1. Install **Linux Mint (linuxmint-22.3-xfce-64bit.iso)** using the supplied ISO or an official download.
2. Enable **Automatic Login** during installation.
3. Copy the **webwall** folder to the Desktop.
4. Fix ownership:

```bash
sudo chown -R $USER:$USER ~/Desktop/webwall
```

5. Make the scripts executable:

```bash
chmod +x ~/Desktop/webwall/*.sh
```

6. Run the installation script:

```bash
sudo ~/Desktop/webwall/webwall_setup.sh
```

The setup script will:

* Install required packages
* Configure kiosk mode
* Apply application settings
* Configure startup services

7. Reboot.

8. When prompted to create a keyring, leave the password **blank**.

9. Configure the display layout. Jump to [Display Configuration](https://github.com/mik3p3r3z/webwall-kiosk/edit/main/README.md#display-configuration).

10. Configure the websites. Jump to [Website Configuration](https://github.com/mik3p3r3z/webwall-kiosk/edit/main/README.md#website-configuration).

```
webwall_cron.sh
```

---

# Display Configuration

Display configuration runs automatically during startup using:

```
webwall_autostart.sh
```

Monitor orientation is controlled using **xrandr**.

The default configuration rotates each monitor **90° counterclockwise (Portrait Left)**.

```
┌──────────┐┌──────────┐┌──────────┐┌──────────┐
│          ││          ││          ││          │
│   DP-1   ││   DP-2   ││   DP-3   ││   DP-4   │
│          ││          ││          ││          │
│ Portrait ││ Portrait ││ Portrait ││ Portrait │
│          ││          ││          ││          │
└──────────┘└──────────┘└──────────┘└──────────┘
    x=0        x=1080      x=2160      x=3240
```

### Virtual Desktop

Resolution:

```
4320 × 1920
```

Coordinate Layout

```
(0,0)

+----------+----------+----------+----------+
|   DP-1   |   DP-2   |   DP-3   |   DP-4   |
|1080×1920 |1080×1920 |1080×1920 |1080×1920 |
+----------+----------+----------+----------+

                                   (4320,1920)
```

### Monitor Positions

| Output | Rotation | Position | Screen Area   |
| ------ | -------- | -------- | ------------- |
| DP-1   | Left     | (0,0)    | x = 0–1079    |
| DP-2   | Left     | (1080,0) | x = 1080–2159 |
| DP-3   | Left     | (2160,0) | x = 2160–3239 |
| DP-4   | Left     | (3240,0) | x = 3240–4319 |

The result is a seamless four-monitor portrait wall with no gaps or overlaps.

---

# Website Configuration

Website capture is managed by:

```
webwall_cron.sh
```

For each configured website the script:

1. Opens the webpage.
2. Captures a screenshot.
3. Saves it as a temporary image.
4. Validates the captured image.
5. Replaces the displayed image only if the new capture is valid.
6. Discards invalid or incomplete captures.

This prevents broken pages, loading screens, and network errors from appearing on the display wall.

## Configurable Parameters

Only modify the following values:

### URL

Replace only the URL.

Example:

```bash
"https://2news.com"
```

### Output Filename

Replace only the output filename.

Example:

```bash
ktvn.png
```

The image will be stored in:

```bash
$IMAGE_DIR/ktvn.png
```

### Browser Size

Capture webpages using a **16:9 portrait ratio**.

Example:

```
1350 × 2400
```

Height can be calculated as:

```
Height = Width × 1.7778
```

The captured image is automatically scaled to the display resolution of:

```
1080 × 1920
```

---

# Customization

To customize Webwall:

* Change monitor orientation in `webwall_autostart.sh`
* Modify display positions using `xrandr`
* Update website URLs in `webwall_cron.sh`
* Adjust browser capture dimensions as needed
* Add or remove websites by editing the screenshot list

---

# License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See the [LICENSE](LICENSE) file for details.
