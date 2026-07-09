# **Fedora System Update Script**

Ein robustes und automatisiertes Bash-Skript, um Fedora Linux effizient auf dem neuesten Stand zu halten. Das Skript aktualisiert sowohl die regulären Systempakete (via DNF) als auch isolierte Anwendungen (via Flatpak und Snap) in einem einzigen, abgesicherten Durchlauf.

## **🚀 Funktionen**

* **Umfassendes Update:** Aktualisiert DNF-Pakete, Flatpak- und Snap-Anwendungen nacheinander.  
* **Strikte Fehlerbehandlung:** Nutzt set \-euo pipefail und einen ERR-Trap, um bei Problemen sofort und mit genauer Fehlerzeile abzubrechen.  
* **Sudo-Keepalive:** Verhindert das Ablaufen des Sudo-Tickets bei großen Updates (z. B. umfangreichen Flatpak-Runtimes), sodass keine zweite Passworteingabe während des Vorgangs nötig ist.  
* **Defensive Programmierung:** Prüft automatisch auf das Vorhandensein optionaler Komponenten (Flatpak, Snap, libnotify) und überspringt diese bei Bedarf ohne Fehlermeldung.  
* **Neustart-Prüfung:** Ermittelt zuverlässig, ob nach dem Update ein Systemneustart empfohlen wird (z. B. nach einem Kernel-Update oder bei Kern-Bibliotheken).  
* **Desktop-Benachrichtigungen:** Sendet nach Abschluss eine native Systembenachrichtigung (ideal für KDE Plasma oder GNOME).

## **📋 Systemanforderungen**

* **Betriebssystem:** Fedora Linux (oder kompatible RHEL-basierte Distributionen)  
* **Abhängigkeiten:** bash, sudo, dnf  
* **Optional:** flatpak (für App-Updates), snapd (für Snap-Updates), libnotify (für Desktop-Benachrichtigungen via notify-send)

## **🛠️ Installation**

1. Das Repository klonen oder das Skript herunterladen:  
   git clone \[https://github.com/Obi-Wahn/fedora-update-script.git\](https://github.com/Obi-Wahn/fedora-update-script.git)  
   cd fedora-update-script

2. Das Skript ausführbar machen:  
   chmod \+x update-system.sh

3. **(Optional)** Das Skript in den lokalen Bin-Pfad verschieben, um es systemweit als Befehl (z.B. system-update) verfügbar zu machen:  
   mkdir \-p \~/.local/bin  
   mv update-system.sh \~/.local/bin/system-update

   *Hinweis: Möglicherweise muss das Terminal nach diesem Schritt neu gestartet werden.*

## **💻 Nutzung**

Wenn das Skript im aktuellen Verzeichnis liegt:

./update-system.sh

Wenn es nach \~/.local/bin verschoben wurde, genügt der Aufruf von überall im Terminal:

system-update

Beim Start wird einmalig das Sudo-Passwort abgefragt. Danach läuft das Skript vollautomatisch durch.

## **🤖 Hinweis zur Erstellung**

Dieses Skript sowie die vorliegende Dokumentation wurden mit Unterstützung von Künstlicher Intelligenz (KI) erstellt und optimiert.

## **📄 Lizenz**

Dieses Projekt ist Open Source und steht unter der [MIT-Lizenz](https://opensource.org/license/mit). Der Quellcode kann frei verwendet, angepasst und weitergegeben werden.
