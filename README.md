# ps2-install

Install PS2 games from Linux straight onto the PS2's **internal HDD** over the network. It uses Open PS2 Loader's **NBD Server**, so you don't have to pull the drive out of the console.

Pick some ISOs and type your password once. Each game then gets its own progress bar, and cover art is synced to OPL at the end.

```
ISO ──▶ hdl_dump ──▶ /dev/nbd0 ══ NBD over LAN ══▶ OPL NBD Server ──▶ PS2 HDD
                                                                    └─ +OPL/ART (covers via pfsshell)
```

## Branches

| Branch | Desktop | UI |
|---|---|---|
| `main` | KDE Plasma | kdialog progress bars, "Send to PS2 HDD" in Dolphin's right-click menu, `pkexec` password prompt |
| `omarchy` | [Omarchy](https://omarchy.org) / Hyprland | runs in a floating terminal with `gum`, `sudo` prompt, Nautilus script, desktop notification when done |

The transfer logic is the same on both branches. Only the dialogs and launcher integration differ.

## What it does

1. Asks for ISOs, either as arguments, from the right-click menu, or through a file picker.
2. Checks that OPL's NBD Server is reachable and exports `hdd0`. OPL also exports the memory cards, RAM and BIOS, and the script never touches those.
3. A small root helper attaches the HDD as `/dev/nbd0` and paces uploads with `tc fq maxrate`. It disconnects when the script exits, whether the script finished, was cancelled or crashed.
4. Reads each game's ID from `SYSTEM.CNF`, skips games already on the HDD, and installs the rest with `hdl_dump inject_dvd`/`inject_cd`. Images under 900 MB are treated as CDs.
5. Fetches missing cover art (`ps2-art`) for every game on the HDD and copies it into the `+OPL` partition's `ART/` folder with `pfsshell`.
6. Shows a summary of installed, skipped and failed games, plus what's on the HDD now.

Sleep is blocked with `systemd-inhibit` while it runs, because suspend in the middle of a batch makes every remaining game fail.

## Requirements

- **PS2:** network adapter with an HDD, and OPL with the NBD Server (OPL ≥ 1.2 builds replaced "HDL Server" with it).
- **OPL settings:** *Enable Write Operations* = On. Otherwise the HDD is exported read-only and every write fails with `Operation not permitted`. *HDD device start mode* must be on so that `hdd0` is exported.
- **Packages (Arch):** `nbd` (nbd-client), `imagemagick`, `python`, plus the frontend's packages: `kdialog qt6-tools` on `main`, `gum` on `omarchy`.
- **hdl_dump:** from [ps2homebrew/hdl-dump](https://github.com/ps2homebrew/hdl-dump). Use the patched build below, because the stock one manages about 0.45 MB/s over NBD.
- **pfsshell:** from [ps2homebrew/pfsshell](https://github.com/ps2homebrew/pfsshell). Optional, and only needed for cover art.

## Install

```bash
git clone https://github.com/lidoliver/ps2-install.git
cd ps2-install
./install.sh --hdl-dump      # drop --hdl-dump if you already have hdl_dump
```

This puts `ps2-install` and `ps2-art` in `~/.local/bin`, which needs to be on your `PATH`, and adds the launcher entries.

## Settings

Set them as environment variables or in `~/.config/ps2-install.conf`:

```bash
PS2_IP=10.0.0.50          # the PS2's address (OPL shows it under Network Settings)
PS2_RATE=40mbit           # upload pacing while connected
PS2_GAMES=~/Documents/ps2game   # contains DVD/, CD/ and ART/
```

## The hdl_dump patch

`patches/hdl-dump-no-odsync.patch` targets hdl-dump `32c296c`.

Stock hdl_dump opens the device with `O_DSYNC`. Over NBD that makes every 512 KB write wait for a round trip to the PS2, which gives about 0.45 MB/s. The patch:

- drops `O_DSYNC`
- makes `hio->flush()` call `fsync()` on Unix (it was an empty stub there)
- flushes before the game's main header is written, and before and after every partition-table commit

hdl_dump already writes the partition-table entry last. With the patch, the data is guaranteed to be on disk before the header that points at it, and the header before the table that lists it. An install cut off half-way therefore still leaves no broken partition. The game just isn't there, and you install it again.

`ps2-install` also caps unsent data on `nbd0` at 32 MB (`bdi/strict_limit`), so the progress bar shows what has actually reached the PS2.

## Known issues

- **"NBD Server unloading…" freezes OPL.** This is OPL bug [#1012](https://github.com/ps2homebrew/Open-PS2-Loader/issues/1012). Reset the PS2 after the transfer finishes. That's safe once the PC has disconnected.
- **The NBD Server serves one client.** If a client vanishes, the server hangs at `Negotiation:`, and you need to reset the PS2.
- **The PS2 dies mid-install.** `nbd-client -t 60` turns a dead connection into an I/O error after 60 s. Without that timeout, `hdl_dump` would hang in D state and block shutdown.
- **Slow or unreliable transfers.** A cheap switch or mesh node between a 1 Gbit PC and the 100 Mbit PS2 can drop bursts even when pings show 0% loss. Lower `PS2_RATE`.
- **The game is already on the HDD.** It's skipped. Delete it first (`pfsshell` → `rmpart`) if you want to reinstall.

## Cover art (`ps2-art`)

```bash
ps2-art SLUS_200.62 SCUS_971.98   # specific games
ps2-art --all                     # every ISO in $PS2_GAMES/{DVD,CD}
```

The script downloads only the files it needs from the [OPL Manager art backup on archive.org](https://archive.org/details/OPLM_ART_2023_11): COV, COV2, ICO, LAB, LGO, BG, SCR and SCR2. It converts them to OPL's PNG8 sizes, and falls back to [xlenore/ps2-covers](https://github.com/xlenore/ps2-covers) for front covers. It never overwrites existing files.

## License

MIT for the scripts. The hdl-dump patch is a derivative of hdl-dump and is under its GPL-2.0.
