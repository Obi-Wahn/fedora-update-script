#!/bin/bash
# Strikte Fehlerbehandlung:
# -E: Vererbt ERR-Traps an Subshells und Funktionen
# -e: Bricht bei Fehlern ab
# -u: Bricht bei undefinierten Variablen ab
# -o pipefail: Bricht ab, wenn ein Befehl innerhalb einer Pipeline fehlschlägt
set -Eeuo pipefail

# =========================================================
# KONFIGURATION
# =========================================================
# Setze auf "true", wenn ungenutzte Abhängigkeiten automatisch 
# durch 'dnf autoremove' entfernt werden sollen. 
# (Tipp: Unter Fedora mit Vorsicht genießen, daher Standard = false)
RUN_AUTOREMOVE="false"

# Setze auf "true", wenn Snap-Pakete aktualisiert werden sollen.
RUN_SNAP_UPDATE="false"

# Farben für die Terminalausgabe definieren
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# Root-Check: Verhindert, dass das Skript als "sudo ./update-system.sh" gestartet wird
if [[ "${EUID:-}" -eq 0 ]]; then
    printf '%b❌ Bitte das Skript NICHT als Root (mit sudo) starten! Das Skript fordert die Rechte selbst an.%b\n' "$RED" "$RESET"
    exit 1
fi

# ERR-Trap: Wird aufgerufen, wenn ein Befehl fehlschlägt.
trap 'err_code=$?; printf "\n%b❌ Fehler in Zeile %s (Code %s): %s\nUpdate abgebrochen.%b\n" "$RED" "$LINENO" "$err_code" "$BASH_COMMAND" "$RESET"; exit $err_code' ERR

# EXIT-Trap: Beendet den Hintergrundprozess (Sudo-Keepalive) sauber.
cleanup() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------
# HAUPTSKRIPT
# ---------------------------------------------------------

printf '%b▶ Start: %s%b\n' "$BLUE" "$(date '+%d.%m.%Y %H:%M:%S')" "$RESET"
printf '%b▶ Fordere Administratorrechte an...%b\n' "$BLUE" "$RESET"
sudo -v

# Sudo-Ticket im Hintergrund alle 50s erneuern (-n für non-interactive)
( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null || true; sleep 50; done ) &
SUDO_KEEPALIVE_PID=$!

printf '\n%b▶ Starte System-Updates via DNF...%b\n' "$BLUE" "$RESET"
sudo dnf upgrade --refresh -y

# Räumt nicht mehr benötigte Abhängigkeiten auf (falls in Konfiguration aktiviert)
if [[ "$RUN_AUTOREMOVE" == "true" ]]; then
    printf '\n%b▶ Führe DNF Autoremove aus...%b\n' "$BLUE" "$RESET"
    sudo dnf autoremove -y
else
    printf '%bℹ "autoremove" ist in der Konfiguration deaktiviert. Übersprungen.%b\n' "$YELLOW" "$RESET"
fi

printf '\n%b▶ Starte Flatpak-Updates...%b\n' "$BLUE" "$RESET"
# Defensive Programmierung: Verhindert Abbruch durch ERR-Trap, falls Flatpak fehlt
if command -v flatpak &>/dev/null; then
    flatpak update -y
else
    printf '%b⚠ Flatpak nicht installiert, übersprungen.%b\n' "$YELLOW" "$RESET"
fi

# Snap-Updates (falls aktiviert)
if [[ "$RUN_SNAP_UPDATE" == "true" ]]; then
    printf '\n%b▶ Starte Snap-Updates...%b\n' "$BLUE" "$RESET"
    if command -v snap &>/dev/null; then
        # Prüfen, ob der Hintergrunddienst von Snap (snapd) tatsächlich läuft
        if systemctl is-active --quiet snapd.service || systemctl is-active --quiet snapd.socket; then
            sudo snap refresh
        else
            printf '%b⚠ Snap ist zwar installiert, aber der snapd-Dienst ist nicht aktiv. Übersprungen.%b\n' "$YELLOW" "$RESET"
        fi
    else
        printf '%bℹ Snap ist nicht installiert. Übersprungen.%b\n' "$YELLOW" "$RESET"
    fi
else
    printf '\n%bℹ Snap-Updates sind in der Konfiguration deaktiviert. Übersprungen.%b\n' "$YELLOW" "$RESET"
fi

printf '\n%b▶ Prüfe Systemstatus...%b\n' "$BLUE" "$RESET"
# Manuelle Kernel-Prüfung (Da DNF needs-restarting manchmal unzuverlässig ist)
CURRENT_KERNEL=$(uname -r)
# Holt den neuesten installierten Kernel, ignoriert Fehler durch "|| true", um set -e nicht auszulösen
LATEST_KERNEL=$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n 1 || true)

if [[ -n "$LATEST_KERNEL" && "$CURRENT_KERNEL" != "$LATEST_KERNEL" ]]; then
    REBOOT_MSG="System-Neustart empfohlen (Neuer Kernel installiert)."
    REBOOT_COLOR="$YELLOW"
    REBOOT_ICON="⚠"
elif ! sudo dnf needs-restarting -r > /dev/null 2>&1; then
    # dnf gibt Fehlercode 1 aus, wenn ein Neustart nötig ist (z. B. wegen glibc)
    REBOOT_MSG="System-Neustart empfohlen (Kern-Bibliotheken aktualisiert)."
    REBOOT_COLOR="$YELLOW"
    REBOOT_ICON="⚠"
else
    REBOOT_MSG="Kein Neustart erforderlich."
    REBOOT_COLOR="$GREEN"
    REBOOT_ICON="✔"
fi

# Finale Ausgabe im Terminal
printf '\n%b✔ Alle vorgesehenen Update-Schritte wurden ohne Fehler ausgeführt. (%s)%b\n' "$GREEN" "$(date '+%H:%M:%S')" "$RESET"
printf '%b%s %s%b\n' "$REBOOT_COLOR" "$REBOOT_ICON" "$REBOOT_MSG" "$RESET"

# KDE Plasma / GNOME Desktop-Benachrichtigung senden
if command -v notify-send &>/dev/null; then
    # Das "|| true" verhindert, dass ein Fehler hier das gesamte Skript als gescheitert markiert
    notify-send "System-Update abgeschlossen" "$(printf "Alle vorgesehenen Update-Schritte wurden ohne Fehler ausgeführt.\n%s" "$REBOOT_MSG")" -i system-software-update || true
fi
