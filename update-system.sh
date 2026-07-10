#!/bin/bash
# Strikte Fehlerbehandlung: Bricht bei Fehlern (-e), undefinierten Variablen (-u)
# und Fehlern in Pipes (-o pipefail) sofort ab.
set -euo pipefail

# =========================================================
# KONFIGURATION
# =========================================================
# Setze auf "true", wenn ungenutzte Abhängigkeiten automatisch 
# durch 'dnf autoremove' entfernt werden sollen. 
# (Tipp: Unter Fedora mit Vorsicht genießen, daher Standard = false)
RUN_AUTOREMOVE="false"

# Farben für die Terminalausgabe definieren
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# Root-Check: Verhindert, dass das Skript als "sudo ./update-system.sh" gestartet wird
if [[ "${EUID:-}" -eq 0 ]]; then
    echo -e "${RED}❌ Bitte das Skript NICHT als Root (mit sudo) starten! Das Skript fordert die Rechte selbst an.${RESET}"
    exit 1
fi

# ERR-Trap: Wird aufgerufen, wenn ein Befehl fehlschlägt.
trap 'err_code=$?; echo -e "\n${RED}❌ Fehler in Zeile $LINENO (Code $err_code): $BASH_COMMAND\nUpdate abgebrochen.${RESET}"; exit $err_code' ERR

# EXIT-Trap: Beendet den Hintergrundprozess (Sudo-Keepalive) sauber.
cleanup() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------
# HAUPTSKRIPT
# ---------------------------------------------------------

echo -e "${BLUE}▶ Start: $(date '+%d.%m.%Y %H:%M:%S')${RESET}"
echo -e "${BLUE}▶ Fordere Administratorrechte an...${RESET}"
sudo -v

# Sudo-Ticket im Hintergrund alle 50s erneuern (-n für non-interactive)
( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null || true; sleep 50; done ) &
SUDO_KEEPALIVE_PID=$!

echo -e "\n${BLUE}▶ Starte System-Updates via DNF...${RESET}"
sudo dnf upgrade --refresh -y

# Räumt nicht mehr benötigte Abhängigkeiten auf (falls in Konfiguration aktiviert)
if [[ "$RUN_AUTOREMOVE" == "true" ]]; then
    echo -e "${BLUE}▶ Führe DNF Autoremove aus...${RESET}"
    sudo dnf autoremove -y
fi

echo -e "\n${BLUE}▶ Starte Flatpak-Updates...${RESET}"
# Defensive Programmierung: Verhindert Abbruch durch ERR-Trap, falls Flatpak fehlt
if command -v flatpak &>/dev/null; then
    flatpak update -y
else
    echo -e "${YELLOW}⚠ Flatpak nicht installiert, übersprungen.${RESET}"
fi

echo -e "\n${BLUE}▶ Starte Snap-Updates...${RESET}"
# Defensive Programmierung: Führt Updates nur aus, wenn Snap vorhanden ist
if command -v snap &>/dev/null; then
    sudo snap refresh
else
    echo -e "${YELLOW}⚠ Snap nicht installiert, übersprungen.${RESET}"
fi

echo -e "\n${BLUE}▶ Prüfe Systemstatus...${RESET}"
# Manuelle Kernel-Prüfung (Da DNF needs-restarting manchmal unzuverlässig ist)
CURRENT_KERNEL=$(uname -r)
# Holt den neuesten installierten Kernel, ignoriert Fehler durch "|| true", um set -e nicht auszulösen
LATEST_KERNEL=$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n 1 || true)

if [[ -n "$LATEST_KERNEL" && "$CURRENT_KERNEL" != "$LATEST_KERNEL" ]]; then
    REBOOT_MSG="System-Neustart empfohlen (Neuer Kernel installiert)."
    REBOOT_COLOR="${YELLOW}⚠"
elif ! sudo dnf needs-restarting -r > /dev/null 2>&1; then
    # dnf gibt Fehlercode 1 aus, wenn ein Neustart nötig ist (z. B. wegen glibc)
    REBOOT_MSG="System-Neustart empfohlen (Kern-Bibliotheken aktualisiert)."
    REBOOT_COLOR="${YELLOW}⚠"
else
    REBOOT_MSG="Kein Neustart erforderlich."
    REBOOT_COLOR="${GREEN}✔"
fi

# Finale Ausgabe im Terminal
echo -e "\n${GREEN}✔ Alle Updates erfolgreich abgeschlossen! ($(date '+%H:%M:%S'))${RESET}"
echo -e "${REBOOT_COLOR} ${REBOOT_MSG}${RESET}"

# KDE Plasma Desktop-Benachrichtigung senden
if command -v notify-send &>/dev/null; then
    # Das "|| true" verhindert, dass ein Fehler hier das gesamte Skript als gescheitert markiert
    notify-send "System-Update abgeschlossen" "$(printf "Alle Pakete sind aktuell.\n%s" "$REBOOT_MSG")" -i system-software-update || true
fi
