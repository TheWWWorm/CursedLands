ENGLISH

Use these launchers only with the diagnostic candidate configured for
the custom profile "Cursed Lands PT Diagnostics". Keep both CMD files
and Prepare-PT-Diagnostics.ps1 beside CursedLands.exe.

Run Run-PT-Diagnostics.cmd, then reproduce the problem. The separate
Run-PT-GPU-Validation.cmd additionally requests GPU validation, which
can substantially slow the game and change timing.

Only on first initialization, settings.cfg, keyboard.ini, mod_settings.json,
and the saves and mods folders (when present) are copied from
%APPDATA%\Godot\app_userdata\Cursed Lands to
%APPDATA%\Cursed Lands PT Diagnostics. Existing diagnostic files are
retained without overwriting; the normal profile is never changed.
Later launches do not copy newly added saves, settings or mods.
Imported game-data folders are reused through absolute paths in the copied
settings; the large imported data itself is not copied. Existing diagnostic
settings are not reinterpreted.
The initial PT setting is two bounces with Low RT lighting quality.
Other graphics settings and resolution are preserved. Later launches
keep your diagnostic PT choices. Every launch frees the cursor, shows
FPS, mutes audio and disables autosave. Manual saves remain isolated.

Each run writes logs under diagnostics\<timestamp> beside the game,
including godot.log, GPU names/driver versions when available, and the
native exit code. A detected GPU synchronization failure stops the game
after recording diagnostics; this does not provide device recovery.
No installation, administrator rights or permanent execution-policy
change is required.

РУССКИЙ

Используйте эти средства запуска только с диагностической сборкой,
настроенной на отдельный профиль "Cursed Lands PT Diagnostics".
Оба файла CMD и Prepare-PT-Diagnostics.ps1 должны находиться рядом
с CursedLands.exe.

Запустите Run-PT-Diagnostics.cmd и воспроизведите проблему. Отдельный
Run-PT-GPU-Validation.cmd дополнительно включает проверку GPU, которая
может значительно замедлить игру и изменить время выполнения.

Только при первой подготовке копируются имеющиеся settings.cfg,
keyboard.ini, mod_settings.json и папки saves и mods из
%APPDATA%\Godot\app_userdata\Cursed Lands в
%APPDATA%\Cursed Lands PT Diagnostics. Имеющиеся диагностические файлы
сохраняются без перезаписи; обычный профиль не изменяется. При последующих
запусках новые сохранения, настройки и моды не копируются.
Папки импортированных данных игры используются по абсолютным путям
в копии настроек; сами большие файлы данных не копируются. Пути в уже
существующих диагностических настройках не переопределяются.
Начальная настройка трассировки путей — два отражения
и низкое качество RT-освещения. Остальные настройки графики и разрешение
сохраняются. Последующие запуски сохраняют выбранные настройки PT.
При каждом запуске курсор остаётся свободным, отображается FPS,
звук и автосохранение отключаются. Ручные сохранения остаются отдельными.

Журналы каждого запуска находятся рядом с игрой в diagnostics\<дата>:
godot.log, названия GPU и версии драйверов, если доступны, и код завершения.
При обнаружении ошибки синхронизации GPU игра завершается после записи
диагностики; восстановление устройства не выполняется. Установка,
права администратора и постоянное изменение политики выполнения не нужны.

DEUTSCH

Verwende diese Starter nur mit dem Diagnose-Build, der für das separate
Profil "Cursed Lands PT Diagnostics" konfiguriert ist. Beide CMD-Dateien
und Prepare-PT-Diagnostics.ps1 gehören neben CursedLands.exe.

Starte Run-PT-Diagnostics.cmd und reproduziere das Problem. Der separate
Starter Run-PT-GPU-Validation.cmd fordert zusätzlich die GPU-Validierung
an. Sie kann das Spiel erheblich verlangsamen und das Zeitverhalten ändern.

Nur bei der ersten Einrichtung werden vorhandene settings.cfg, keyboard.ini,
mod_settings.json sowie die Ordner saves und mods von
%APPDATA%\Godot\app_userdata\Cursed Lands nach
%APPDATA%\Cursed Lands PT Diagnostics kopiert. Vorhandene Diagnosedateien
bleiben ohne Überschreiben erhalten; das normale Profil wird nie verändert.
Spätere Starts kopieren keine neuen Spielstände, Einstellungen oder Mods.
Importierte Spieldaten werden über absolute Pfade in den kopierten
Einstellungen weiterverwendet; die großen Datendateien werden nicht kopiert.
Vorhandene Diagnoseeinstellungen werden nicht neu interpretiert.
Anfangs nutzt PT zwei Reflexionen und niedrige
RT-Beleuchtungsqualität. Andere Grafikeinstellungen und die Auflösung
bleiben erhalten. Spätere Starts behalten deine PT-Einstellungen bei.
Bei jedem Start bleibt der Mauszeiger frei, die FPS-Anzeige ist aktiv,
Ton und automatisches Speichern sind aus. Manuelle Spielstände bleiben
im separaten Profil.

Jeder Start speichert Protokolle unter diagnostics\<Zeitstempel> neben
dem Spiel: godot.log, verfügbare GPU-Namen und Treiberversionen sowie den
nativen Beendigungscode. Ein erkannter GPU-Synchronisierungsfehler beendet
das Spiel nach der Diagnoseaufzeichnung; das Gerät wird nicht wiederhergestellt.
Installation, Administratorrechte oder eine dauerhafte Änderung der
Ausführungsrichtlinie sind nicht erforderlich.
