#!/bin/bash
# Strikte Fehlerbehandlung: Bricht bei Fehlern (-e), undefinierten Variablen (-u)
# und Fehlern in Pipes (-o pipefail) sofort ab.
set -euo pipefail

# Farben für die Terminalausgabe definieren
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# ERR-Trap: Wird aufgerufen, wenn ein Befehl fehlschlägt.
# Gibt eine rote Fehlermeldung mit der exakten Zeilennummer ($LINENO) aus.
trap 'echo -e "\n${RED}❌ Fehler in Zeile $LINENO! Update abgebrochen.${RESET}"; exit 1' ERR

# EXIT-Trap: Wird immer am Ende ausgeführt, egal ob Erfolg oder Abbruch.
# Beendet den Hintergrundprozess (Sudo-Keepalive) sauber.
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

# Sudo-Ticket im Hintergrund alle 50s erneuern
( while kill -0 $$ 2>/dev/null; do sudo -v; sleep 50; done ) &
SUDO_KEEPALIVE_PID=$!

echo -e "\n${BLUE}▶ Starte System-Updates via DNF...${RESET}"
# 'upgrade' ist der technisch modernere Begriff als 'update' bei DNF
sudo dnf upgrade --refresh -y

echo -e "\n${BLUE}▶ Starte Flatpak-Updates...${RESET}"
# Defensive Programmierung: Verhindert Abbruch durch ERR-Trap, falls Flatpak fehlt
if command -v flatpak &>/dev/null; then
    flatpak update -y
else
    echo -e "${YELLOW}⚠ Flatpak nicht installiert, übersprungen.${RESET}"
fi

echo -e "\n${BLUE}▶ Prüfe Systemstatus...${RESET}"
# Neustart prüfen (mit sudo für korrekte Ausführung!)
if sudo dnf needs-restarting -r > /dev/null 2>&1; then
    REBOOT_MSG="Kein Neustart erforderlich."
    REBOOT_COLOR="${GREEN}✔"
else
    REBOOT_MSG="System-Neustart empfohlen (z. B. wegen neuem Kernel)."
    REBOOT_COLOR="${YELLOW}⚠"
fi

# Finale Ausgabe im Terminal
echo -e "\n${GREEN}✔ Alle Updates erfolgreich abgeschlossen! ($(date '+%H:%M:%S'))${RESET}"
echo -e "${REBOOT_COLOR} ${REBOOT_MSG}${RESET}"

# KDE Plasma Desktop-Benachrichtigung senden (sicherer Check & Zeilenumbruch-Fix)
if command -v notify-send &>/dev/null; then
    notify-send "System-Update abgeschlossen" "$(printf "Alle Pakete sind aktuell.\n%s" "$REBOOT_MSG")" -i system-software-update
fi