# Game library and Lost in Astral

Choose **Main game — Evil Islands** or **Expansion — Lost in Astral** on the setup screen or above the main-menu signpost. Install either game or keep both. New Game, Load Game and co-op use the selected campaign, with separate save directories. Existing Evil Islands installations and saves are kept.

Use **Options → Remake → Game files…** to manage the two installations. Select the correct game before importing an installed folder, a supported GOG installer or a private `.eipack`. The engine checks the game identity before changing an existing installation.

Installed folders for both games accept original, lowercase or mixed capitalization in game-data folder and file names. Your source folders and files are not renamed. Conflicting names such as `res` and `Res` are refused, even when one matches the expected lowercase spelling. The data-pack tool and browser imports use lowercase paths only in their own generated packs or stored data.

For the supported Lost in Astral CD edition, choose **Import Lost in Astral ISO images…** and select both discs together. Their order and filenames do not matter. The engine reads the ISO images and InstallShield 6 cabinets directly, checks the extracted files and removes its incomplete staging directory if import fails or is cancelled. It does not mount the images or run Windows software.

This importer accepts ISO 9660 images with 2048-byte sectors; raw BIN/CUE images and other installer revisions are unsupported. Native mobile setup uses its document picker, but physical mobile ISO import has not been verified. Browser imports accept folders, supported GOG installers and data packs; browser ISO selection is unavailable. Both browser libraries are retained separately.

To play the expansion together, select it and press **Co-op campaign** above the signpost. The host chooses **Host co-op campaign**, a new game or an expansion save, and starts hosting. Friends choose **Join co-op campaign**, enter the address and choose their hero. The host starts the game once everyone has joined. Every player needs the expansion and a compatible remake version.

The host leads the story and saves the shared world. Guests receive their progress in a separate expansion co-op save. Chapter changes synchronize the host's active roster and the waiting parties. The original multiplayer bases are available when the main game is selected.

The engine includes no original or expansion game data. Keep your installers, disc images and data packs private.
