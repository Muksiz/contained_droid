# contained_droid

> **Status: work in progress.** The container builds and starts, but the
> emulator is not yet confirmed to boot Android reliably. See the commit log.

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
virtualization. It is on by default in Windows 11. In PowerShell:

```powershell
wsl --update
docker run --rm --device /dev/kvm alpine ls -l /dev/kvm
```

If the second command prints a line starting with `crw`, you are set. If it
fails, see [Troubleshooting](#troubleshooting).

### 3. Get the project and start it

```powershell
git clone https://github.com/Muksiz/contained_droid.git
cd contained_droid
docker compose up -d --build
```

The first build downloads the Android system image and takes a while; the
resulting image is several GB. Later starts take seconds.

### 4. Open the desktop

Browse to <http://localhost:6080>. You get a desktop with two windows: the
Android emulator and REAPER. The very first Android boot takes a few minutes;
later boots take about a minute.

### 5. Set up Android

1. Open the Play Store in the emulator and sign in with a Google account.
2. Install your audiobook app, sign in, and download the book so playback does
   not depend on streaming.

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

1. Dismiss the evaluation notice ("Still Evaluating").
2. Open Options → Preferences → Audio → Device, choose **PulseAudio** as the
   audio system and apply. The input is the emulator (`droid.monitor`).
3. Insert a track (Ctrl+T), arm it for recording, and check that the meter
   moves when Android plays something.
4. Press record (Ctrl+R), then start playback in the Android app.

Media is saved to `/recordings` by default. Save the project there as well.

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

Edit `environment:` in `compose.yaml`, then run `docker compose up -d`.

| Variable             | Default       | Meaning                                              |
| -------------------- | ------------- | ---------------------------------------------------- |
| `SCREEN`             | `1600x900x24` | Size of the browser desktop                          |
| `EMULATOR_RAM_MB`    | `4096`        | RAM given to Android                                 |
| `EMULATOR_CORES`     | `4`           | CPU cores given to Android                           |
| `EMULATOR_DATA_SIZE` | `16G`         | Android storage; only applied when the device is first created |

The Android version is a build argument (`ANDROID_API`, default 34) in the
`Dockerfile`.

## Troubleshooting

**`/dev/kvm` is missing / "error gathering device information"**
Create or edit `%UserProfile%\.wslconfig`:

```ini
[wsl2]
nestedVirtualization=true
```

then run `wsl --shutdown` and restart Docker Desktop. Also check that
virtualization (Intel VT-x / AMD-V) is enabled in the BIOS/UEFI and that the
"Virtual Machine Platform" Windows feature is on.

**The emulator is slow or the recording has dropouts**
Android is rendered in software, so it needs CPU headroom. Raise
`EMULATOR_CORES`, and give WSL more resources in `%UserProfile%\.wslconfig`
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
