# contained_droid

> **Status:** tested on Linux (Podman, KVM): Android boots, and both REAPER and
> the `record` command capture the emulator's audio. Not yet confirmed on
> Windows 11 / Docker Desktop.

An Android emulator and a recorder (REAPER) sealed in one container. The only
audio device inside the container is a virtual PulseAudio sink that the emulator
plays into, so a recording can only ever contain the emulator's audio — never
sounds from the host desktop.

```
┌──────────────────────────── container ────────────────────────────┐
│  Android emulator ──► PulseAudio null sink "droid"                │
│                              │ droid.monitor                      │
│                              ├──► REAPER      ──┐                 │
│                              └──► record (FLAC) ┴─► /recordings ──┼─► .\recordings
│  Xvfb desktop ──► noVNC ──────────────────────────────────────────┼─► http://localhost:6080
└───────────────────────────────────────────────────────────────────┘
```

## How it works

1. The container runs its own PulseAudio server with exactly one device: a
   virtual "null sink" called `droid` that is not connected to any hardware.
2. The Android emulator plays into that sink, because it is the only output
   that exists.
3. Every sink has a "monitor" source carrying whatever is played into it.
   `droid.monitor` is the default input, so REAPER and the `record` command
   capture from it.
4. Recordings are written to `/recordings`, which is the `recordings` folder on
   the host.

Only two things cross the container boundary: that folder, and the browser
desktop on port 6080 (picture, mouse and keyboard only — no audio).

- The container is never given a host sound device, so system sounds, calls or
  browser audio on the host have no path into a recording.
- The reverse also holds: the emulator's audio never reaches the host's
  speakers. You can mute the PC or play something else while recording.
- You therefore cannot listen live. Watch the meters in REAPER and check the
  recorded file afterwards.

The emulator and REAPER share one container on purpose. Splitting them would
need a shared audio socket between two containers without making the isolation
any stronger; the boundary that matters is container versus host.

## Running on Windows 11 with Docker Desktop

### 1. Prerequisites

- Windows 11 on an x86-64 (Intel/AMD) machine with virtualization enabled in
  the BIOS/UEFI. Windows on ARM is not supported.
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) using the
  **WSL 2** backend (Settings → General → "Use the WSL 2 based engine").
- [Git for Windows](https://git-scm.com/download/win).
- About 15 GB of free disk space and 8 GB of RAM available to WSL.

### 2. Make sure KVM is available to Docker

The emulator needs `/dev/kvm`, which WSL 2 provides through nested
virtualization. Recent WSL kernels (6.x) ship the KVM driver as a module that
is not loaded automatically and is forgotten on every restart of WSL, Docker
Desktop or Windows. The project therefore loads it for you: `docker compose up`
first runs a small helper container (`kvm`) that does so.

You can normally go straight to step 3. Come back here if `docker compose up`
ends with `service "kvm" didn't complete successfully` or with `error gathering
device information while adding custom device "/dev/kvm"`.

First try loading the driver by hand:

```powershell
wsl -d docker-desktop sh -c "modprobe kvm_amd; ls -l /dev/kvm"
```

Use `kvm_intel` instead of `kvm_amd` on an Intel CPU. If this prints a line
starting with `crw`, run `docker compose up -d` again.

If `modprobe` fails, nested virtualization is not enabled yet:

1. Open the WSL settings file:

   ```powershell
   notepad $env:USERPROFILE\.wslconfig
   ```

   and make it contain (answer "Yes" if Notepad asks to create the file):

   ```ini
   [wsl2]
   nestedVirtualization=true
   ```

2. Update and restart WSL. Run these as two separate commands:

   ```powershell
   wsl --update
   ```

   ```powershell
   wsl --shutdown
   ```

3. Quit Docker Desktop completely (tray icon → Quit Docker Desktop), start it
   again, and run `docker compose up -d` once more.

Still failing? See [Troubleshooting](#troubleshooting).

### 3. Get the project and start it

```powershell
git clone https://github.com/Muksiz/contained_droid.git
cd contained_droid
docker compose up -d --build
```

The first build downloads the Android system image and takes a while; the
resulting image is several GB. Later starts take seconds.

**Shortcut:** instead of typing commands, double-click `contained_droid.bat`
in the project folder. It offers Start (starts Docker Desktop if needed, runs
`docker compose up -d` and opens the desktop in your browser), Stop (`docker
compose down`) and a status view. For a desktop icon, right-click the file →
Show more options → Send to → Desktop (create shortcut). Use it after the
first build described above has succeeded once.

### 4. Open the desktop

Browse to <http://localhost:6080>. You get a desktop with two windows: the
Android emulator and REAPER. The very first Android boot takes a few minutes;
later boots take about a minute.

### 5. Set up Android

1. Open the Play Store in the emulator and sign in with a Google account.
2. Install your audiobook app, sign in, and download the book so playback does
   not depend on streaming.

3. Turn Android's media volume all the way up (the speaker buttons beside the
   emulator, while something is playing). It starts at about a third, which
   makes recordings needlessly quiet.

Everything on the Android device is kept in a Docker volume and survives
restarts and image rebuilds.

To type or paste text into Android, click the emulator window and use your
keyboard. To install an APK directly:

```powershell
docker cp .\some-app.apk contained-droid:/tmp/app.apk
docker exec contained-droid adb install /tmp/app.apk
```

### 6. Record

**With REAPER** (in the browser desktop)

REAPER starts already set to PulseAudio at 44.1 kHz with the emulator as its
input, and `/recordings` as its recording folder.

1. Dismiss the evaluation notice ("Still Evaluating").
2. Insert a track: Track → Insert new track (`Ctrl+T`).
3. Click the track's input selector (it says "Input 1") and choose
   Input: Stereo → Input 1 / Input 2. The default records the left channel only.
4. Click the track's red arm button. The meter moves whenever Android plays
   something.
5. Press record (`Ctrl+R`), then start playback in the Android app.
6. Press `Space` to stop and choose "Save All".

Save the project under `/recordings` too, or it stays inside the container.

**Without REAPER** — a one-line recorder that writes FLAC:

```powershell
docker exec -it contained-droid record my-audiobook
```

Start it, press play in the Android app, and press `Ctrl+C` when the book is
finished. Leave the name out to get a timestamped file.

Either way the files appear in the `recordings` folder next to this README.

### 7. Stop and start

```powershell
docker compose stop      # shut down, keep everything
docker compose start     # start again
docker compose down      # remove the container, keep the Android device and settings
docker compose down -v   # also delete the Android device and REAPER settings
```

Close REAPER projects (or stop the recorder) before stopping the container.

## Settings

Create a file named `.env` next to `compose.yaml` with the values you want to
change, one `NAME=value` per line, then run `docker compose up -d`. For example:

```ini
EMULATOR_CORES=6
SCREEN=2560x1080x24
```

`.env` is ignored by git, so your settings survive `git pull`.

| Variable             | Default       | Meaning                                              |
| -------------------- | ------------- | ---------------------------------------------------- |
| `SCREEN`             | `1920x1080x24` | Size of the browser desktop (width x height x depth) |
| `EMULATOR_RAM_MB`    | `4096`        | RAM given to Android                                 |
| `EMULATOR_CORES`     | `4`           | CPU cores given to Android                           |
| `EMULATOR_AUDIO_BUFFER_MS` | `1000`  | Audio buffer between Android and the recorder        |
| `EMULATOR_DATA_SIZE` | `16G`         | Android storage; only applied when the device is first created |

The Android version is a build argument (`ANDROID_API`, default 34) in the
`Dockerfile`.

## Troubleshooting

**`/dev/kvm` is still missing after step 2**
Run these one at a time and compare:

```powershell
wsl --version
```

The WSL version should be 2.x and the kernel 5.15 or newer. If the command is
not recognised or reports an old version, install the current WSL from the
Microsoft Store or with `wsl --update`.

```powershell
wsl -l -v
```

`docker-desktop` must be listed with VERSION 2. If it is missing, Docker
Desktop is using Hyper-V instead: enable Settings → General → "Use the WSL 2
based engine".

```powershell
wsl -d docker-desktop ls -l /dev/kvm
```

If this prints `No such file or directory`, the WSL virtual machine itself has
no KVM. Find out why with:

```powershell
wsl -d docker-desktop sh -c "uname -r; grep -cE 'vmx|svm' /proc/cpuinfo; dmesg | grep -i kvm"
```

```powershell
Get-Content $env:USERPROFILE\.wslconfig
```

```powershell
(Get-CimInstance Win32_Processor).Name
```

The first command prints the kernel version and then a count. A count of `0`
means nested virtualization is not reaching WSL: `.wslconfig` is not being
picked up, or the CPU, firmware or Windows setup does not offer it. A count
above 0 without `/dev/kvm` points at an outdated WSL kernel (`wsl --update`).

Then check that:

- virtualization (Intel VT-x / AMD-V, sometimes "SVM") is enabled in the
  BIOS/UEFI — Task Manager → Performance → CPU shows "Virtualization: Enabled";
- the "Virtual Machine Platform" Windows feature is on (`optionalfeatures.exe`);
- `.wslconfig` is saved as `%UserProfile%\.wslconfig`, not `.wslconfig.txt`;
- Windows is not itself running inside a virtual machine (nested
  virtualization is then usually unavailable);
- on AMD CPUs, Windows 11 is required (it is) and the CPU is a Ryzen/EPYC.

**The emulator is slow or the recording has dropouts**
Android is rendered in software, so it needs CPU headroom. Raise
`EMULATOR_AUDIO_BUFFER_MS` (for example to 2000) and `EMULATOR_CORES`, and give WSL more resources in `%UserProfile%\.wslconfig`
(`memory=12GB`, `processors=8` under `[wsl2]`), followed by `wsl --shutdown`.
Avoid heavy work on the PC while recording.

**Seeing what is going on**

```powershell
docker compose logs -f
docker exec contained-droid adb devices
docker exec contained-droid pactl list short sink-inputs   # the emulator should be listed
```

**Shell scripts fail with `\r` or "no such file or directory"**
The scripts must keep Unix line endings. `.gitattributes` enforces this; if you
copied the files some other way, re-clone with Git.

## Notes

- The desktop is published on `127.0.0.1` only and has no password. Do not
  expose port 6080 to a network.
- REAPER is commercial software with a free 60-day evaluation; see
  <https://www.reaper.fm/purchase.php>.
- Linux hosts with Docker or Podman work too (`podman-compose up -d --build`),
  as long as `/dev/kvm` exists.
- Only record material you have the right to copy.
