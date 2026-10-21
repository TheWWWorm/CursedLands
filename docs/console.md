# Developer console

Press the physical **grave/tilde key** (the key below Esc on a standard keyboard) to open or close the console. Click **Enable commands**, or enter `thingamabob`, once per game session. Help, output search and diagnostic exports work before unlocking. Campaign commands require a loaded campaign and the host; guests cannot change the campaign by sending console requests.

The console uses the current interface language: English, Russian or German. Commands retain their English spelling in every language. Opening the console releases the mouse and captures gameplay controls; it does not pause the shared simulation.

## Editing and discovery

- **Tab** inserts the selected suggestion. **Ctrl+Space** opens suggestions. **Up/Down** chooses suggestions; with the list closed it recalls previous commands and restores the unfinished draft.
- **Enter** executes the text. Clicking a suggestion only inserts it. Pasting multiple lines places them into the editor as one line; it does not run them.
- **Ctrl+R** searches the last 200 submitted commands using the text already in the editor. History survives restarts in this profile.
- **Ctrl+F** searches output. **Ctrl+L** clears output. **Ctrl+Shift+C** copies output; ordinary selection/copy works in the editor and output.
- **Esc** dismisses suggestions, then output search, then the console. **PageUp/PageDown** scroll output.
- **A−/A+** changes the console font size. Font size, console position and output capacity persist in this profile. Syntax colours and matching brackets help read original expressions; tooltips show full usage hints.

Use `help` to browse commands or `help teleport` to narrow the list and show examples. Completion includes commands, permitted script functions, variables and their current values, unit IDs with display names, installed destinations and console text files. A completion replaces the token at the caret and preserves the rest of the command.

## Common testing actions

| Command | Effect |
| --- | --- |
| `status` | Build, campaign, zone, clocks and party diagnostics. |
| `party` | Party names, IDs, health, energy and map coordinates. |
| `inspect selected` | Inspect the selected host-controlled units. Also accepts `hero`, `party`, a unit ID or an exact script name. Quote names with spaces. |
| `heal party` | Restore attached body parts and energy of living units. Does not resurrect dead units. |
| `god on` / `god off` | Enable/disable basic host-party damage immunity and running without stamina cost. Spell costs and body/load restrictions remain. Mode 2 is unsupported. |
| `teleport 100 100 hero` | Place one living target on nearby walkable ground in the current map and clear its orders. Coordinates outside the map are rejected. |
| `zones` / `zones "filter"` | Find installed maps by zone ID or localized title. |
| `travel gz1g 1` | Request a direct zone transition through entrance 1. This does not complete quest requirements or create an automatic save. |
| `time` / `time 12 freeze` / `time 19 run` | Read, freeze or resume scene time. Hours range from 0 up to, but not including, 24. |
| `give 0 money 1000` / `give 0 exp 1000` | Add money or distribute experience to the host party. |
| `getvar 0 name` / `setvar 0 name 1` | Read/change a campaign variable. |
| `listvar 0 vars.txt` / `loadvar 0 vars.txt` | Export/import campaign variables. Imports validate the whole batch before applying it. |
| `report bug.txt` | Save build/platform/renderer/FPS, host campaign diagnostics when available, and console output. |
| `log console.txt` / `copy` | Save/copy plain console output. |
| `exec commands.txt` | Run a text file containing one command per line. |
| `console t` / `console f` | Top/fullscreen placement; also `b` bottom, `c` centre, `l` left and `r` right. |
| `history 500` | Retain 500 output lines; accepted range 20–5000. This is separate from command recall. |

Console files stay under `console/` inside the game's user-data folder. `help` and successful exports show the full local path. Imports are limited to 64 KiB; script files have a shared limit of 256 commands and four nested levels. `history.json` and `settings.json` are reserved for console preferences. Exported reports are local files; attach one to a bug report yourself when needed.

Gameplay changes can be retained by a normal save. Load an earlier save to discard unwanted changes. Diagnostic exports do not include a save or the original game archives.

## Original script expressions

The original supported syntax remains available, with a typed allowlist and a bounded expression parser:

```text
@GiveMoney(0,100)
@GodMode(0,1)
@GSSetVar(0,"console_probe",42)
#Add(GSGetVar(0,"console_probe"),3)
#HP(GetObjectByName("hero"))
#GetLeverState(GetObject(4306))
$"text"
```

`@` runs an allowed action; `#` prints a number; `$` prints a string. Write functions cannot be nested inside queries. `help GodMode`, `help GetObject` and similar searches display supported signatures. The console does not execute arbitrary GDScript or operating-system commands.

## Краткое руководство

Откройте консоль клавишей под Esc и нажмите **Включить команды** либо введите `thingamabob`. `help` показывает справку, `help heal` — конкретную команду. Tab дополняет текст; Enter выполняет команду. ↑/↓ выбирают подсказки или команды из истории, Ctrl+R ищет в истории, Ctrl+F — в выводе. Подсказки сами команды не выполняют.

`party` показывает отряд; `inspect selected` осматривает выбранных персонажей; `heal party` лечит живой отряд; `god on` включает обычную неуязвимость, `god off` отключает её. `zones` ищет области, `travel gz1g 1` переносит туда без выполнения условий заданий. `report bug.txt` сохраняет локальный отчёт; путь появится в консоли. Изменять кампанию может только сервер. Команды пишутся по-английски при любом языке интерфейса.

## Kurzanleitung

Die Konsole mit der Taste unter Esc öffnen und **Befehle aktivieren** anklicken oder `thingamabob` eingeben. `help` zeigt die Hilfe; `help heal` grenzt sie ein. Tab ergänzt Text, Enter führt ihn aus. ↑/↓ wählt Vorschläge oder frühere Befehle, Strg+R durchsucht den Verlauf und Strg+F die Ausgabe. Vorschläge führen keine Befehle aus.

`party` zeigt die Gruppe, `inspect selected` untersucht die Auswahl, `heal party` heilt die lebende Gruppe. `god on` aktiviert grundlegende Unverwundbarkeit, `god off` schaltet sie aus. `zones` sucht Gebiete; `travel gz1g 1` reist dorthin, ohne Aufgabenbedingungen zu erfüllen. `report bug.txt` speichert einen lokalen Bericht und zeigt den Pfad an. Nur der Host darf die Kampagne ändern. Befehle behalten in jeder Sprache ihre englische Schreibweise.
