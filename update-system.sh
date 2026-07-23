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
# (Snap ist unter Fedora standardmäßig nicht installiert)
RUN_SNAP_UPDATE="false"

# =========================================================
# FUNKTIONEN & INITIALISIERUNG
# =========================================================

# Farben und NO_COLOR Unterstützung
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    GREEN=$'\033[1;32m'
    BLUE=$'\033[1;34m'
    YELLOW=$'\033[1;33m'
    RED=$'\033[1;31m'
    RESET=$'\033[0m'
else
    GREEN=""
    BLUE=""
    YELLOW=""
    RED=""
    RESET=""
fi

# Ausgabefunktionen für sauberen Code
info()    { printf '%b▶ %s%b\n' "$BLUE" "$*" "$RESET"; }
success() { printf '%b✔ %s%b\n' "$GREEN" "$*" "$RESET"; }
warning() { printf '%b⚠ %s%b\n' "$YELLOW" "$*" "$RESET"; }
error()   { printf '%b❌ %s%b\n' "$RED" "$*" "$RESET" >&2; }

# Validierung der Konfigurationsvariablen
validate_boolean() {
    local name=$1
    local value=$2
    case "$value" in
        true|false) ;;
        *) 
            error "Ungültiger Wert für $name: $value – erlaubt sind true oder false."
            exit 2 
            ;;
    esac
}
validate_boolean "RUN_AUTOREMOVE" "$RUN_AUTOREMOVE"
validate_boolean "RUN_SNAP_UPDATE" "$RUN_SNAP_UPDATE"

# Betriebssystem-Prüfung
if [[ ! -r /etc/fedora-release ]]; then
    error "Dieses Skript ist ausschließlich für Fedora vorgesehen."
    exit 1
fi

# Abhängigkeiten prüfen
required_commands=(sudo dnf rpm uname sort date)
for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        error "Erforderlicher Befehl fehlt: $cmd"
        exit 127
    fi
done

# Root-Check
if [[ "${EUID:-}" -eq 0 ]]; then
    error "Bitte das Skript NICHT als Root (mit sudo) starten! Das Skript fordert die Rechte selbst an."
    exit 1
fi

# Traps für Fehler und sauberes Beenden
trap 'err_code=$?; error "Fehler in Zeile $LINENO (Code $err_code): $BASH_COMMAND\nUpdate abgebrochen."; exit $err_code' ERR

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

UPDATE_WARNINGS=()

info "Start: $(date '+%d.%m.%Y %H:%M:%S')"
info "Fordere Administratorrechte an..."
sudo -v

# Sudo-Ticket im Hintergrund alle 50s erneuern
( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null || true; sleep 50; done ) &
SUDO_KEEPALIVE_PID=$!

printf '\n'
info "Starte System-Updates via DNF..."
sudo dnf upgrade --refresh -y

if [[ "$RUN_AUTOREMOVE" == "true" ]]; then
    printf '\n'
    info "Führe DNF Autoremove aus..."
    sudo dnf autoremove -y
else
    info "DNF 'autoremove' ist in der Konfiguration deaktiviert. Übersprungen."
fi

printf '\n'
info "Starte Flatpak-Updates..."
if command -v flatpak &>/dev/null; then
    # Das '||' verhindert, dass set -e das Skript bei temporären Flatpak-Fehlern beendet
    flatpak update -y || {
        warning "Flatpak-Update meldete einen Fehler (z.B. Repo unerreichbar)."
        UPDATE_WARNINGS+=("Flatpak")
    }
else
    warning "Flatpak nicht installiert, übersprungen."
fi

printf '\n'
if [[ "$RUN_SNAP_UPDATE" == "true" ]]; then
    info "Starte Snap-Updates..."
    if command -v snap &>/dev/null; then
        if systemctl is-active --quiet snapd.service || systemctl is-active --quiet snapd.socket; then
            sudo snap refresh || {
                warning "Snap-Update meldete einen Fehler."
                UPDATE_WARNINGS+=("Snap")
            }
        else
            warning "Snap ist zwar installiert, aber der snapd-Dienst ist nicht aktiv. Übersprungen."
        fi
    else
        info "Snap ist nicht installiert. Übersprungen."
    fi
else
    info "Snap-Updates sind in der Konfiguration deaktiviert. Übersprungen."
fi

printf '\n'
info "Prüfe Systemstatus..."

# Sichere Kernel-Prüfung
CURRENT_KERNEL=$(uname -r)
LATEST_KERNEL=""
if rpm -q kernel-core &>/dev/null; then
    LATEST_KERNEL=$(LC_ALL=C rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n 1 || true)
fi

# Neustart-Logik mit exakter Return-Code-Auswertung
if [[ -n "$LATEST_KERNEL" && "$CURRENT_KERNEL" != "$LATEST_KERNEL" ]]; then
    REBOOT_MSG="System-Neustart empfohlen (Neuer Kernel installiert)."
    REBOOT_COLOR="$YELLOW"
    REBOOT_ICON="⚠"
elif NEEDS_RESTART_OUTPUT=$(sudo dnf needs-restarting -r 2>&1); then
    REBOOT_MSG="Kein Neustart erforderlich."
    REBOOT_COLOR="$GREEN"
    REBOOT_ICON="✔"
else
    NEEDS_RESTART_RC=$?
    if (( NEEDS_RESTART_RC == 1 )); then
        REBOOT_MSG="System-Neustart empfohlen (Systemkomponenten aktualisiert)."
        REBOOT_COLOR="$YELLOW"
        REBOOT_ICON="⚠"
    else
        REBOOT_MSG="Neustartstatus konnte nicht zuverlässig ermittelt werden."
        REBOOT_COLOR="$RED"
        REBOOT_ICON="❓"
        warning "DNF-Prüfung fehlgeschlagen (Code $NEEDS_RESTART_RC): $NEEDS_RESTART_OUTPUT"
    fi
fi

# Finale Ausgabe im Terminal
printf '\n'
if [[ ${#UPDATE_WARNINGS[@]} -eq 0 ]]; then
    success "Alle vorgesehenen Update-Schritte wurden ohne Fehler ausgeführt. ($(date '+%H:%M:%S'))"
    NOTIFY_MSG="Alle vorgesehenen Update-Schritte wurden ohne Fehler ausgeführt."
else
    # Zeigt Warnungen im Abschluss an, falls optionale Paketmanager zickten
    warning "Update mit Teilfehlern abgeschlossen (${UPDATE_WARNINGS[*]}). Bitte Terminalausgabe prüfen. ($(date '+%H:%M:%S'))"
    NOTIFY_MSG="Update abgeschlossen, aber mit Warnungen bei: ${UPDATE_WARNINGS[*]}. Bitte Terminal prüfen."
fi

printf '%b%s %s%b\n' "$REBOOT_COLOR" "$REBOOT_ICON" "$REBOOT_MSG" "$RESET"

# Desktop-Benachrichtigung senden
if command -v notify-send &>/dev/null; then
    notify-send "System-Update abgeschlossen" "$(printf "%s\n%s" "$NOTIFY_MSG" "$REBOOT_MSG")" -i system-software-update || true
fi
