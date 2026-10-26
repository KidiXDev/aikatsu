pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aikatsu

// This week's AniList airings, a day at a time. Opened from Home's "Up next".
Item {
    id: root
    objectName: "calendarPage"

    readonly property Main app: ApplicationWindow.window as Main
    // Midnights from the locale's first day of the week, 8 of them so day i ends at i + 1.
    readonly property var bounds: {
        const start = new Date();
        start.setHours(0, 0, 0, 0);
        start.setDate(start.getDate() - (start.getDay() - Qt.locale().firstDayOfWeek % 7 + 7) % 7);
        return [0, 1, 2, 3, 4, 5, 6, 7].map(i => new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
    }
    readonly property int today: bounds.filter(d => d.getTime() <= Date.now()).length - 1
    property int day: today
    property var week: null // meta::schedule
    property bool failed
    property bool mine
    readonly property var watchlist: Api.get("watchlist")
    readonly property var mineIds: watchlist.filter(w => w.anilist_id > 0 && (w.status === "watching" || w.status === "planning")).map(w => w.anilist_id)
    readonly property var shown: airingsOn(day)

    function load(refresh: bool): void {
        failed = false;
        Api.call("schedule", {
            from: bounds[0].getTime() / 1000,
            refresh: refresh
        }, w => root.week = w, () => root.failed = true);
    }

    function airingsOn(i: int): var {
        const from = bounds[i].getTime() / 1000, to = bounds[i + 1].getTime() / 1000;
        return (week ?? []).filter(a => a.airing_at >= from && a.airing_at < to && (!mine || mineIds.includes(a.anime.anilist_id)));
    }

    function open(a: var): void {
        const w = watchlist.find(w => w.anilist_id === a.anime.anilist_id);
        if (w) {
            app.openAnime({
                name: w.title,
                url: w.series_url,
                image: w.cover,
                source: w.source,
                anilistId: w.anilist_id
            }, 0);
            return;
        }
        const at = new Date(a.airing_at * 1000);
        info.item = {
            meta: a.anime,
            note: `Episode ${a.episode} · ${at < new Date() ? "aired" : "airs"} ${Qt.formatDateTime(at, "ddd hh:mm")}`
        };
        info.open();
    }

    Component.onCompleted: load(false)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding.extraLarge
        spacing: Theme.spacing.large

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.medium

            IconButton {
                type: IconButton.Tonal
                icon: "arrow_back"
                iconSize: 18
                onClicked: root.StackView.view.pop()
            }
            StyledText {
                Layout.fillWidth: true
                text: "Schedule"
                font: Theme.font.headline.large
            }
            Chip {
                text: "My shows"
                icon: "bookmark"
                selected: root.mine
                clickable: true
                onClicked: root.mine = !root.mine
            }
            IconButton {
                type: IconButton.Text
                icon: "refresh"
                onClicked: root.load(true)
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            Repeater {
                model: 7

                Chip {
                    required property int index

                    text: Qt.formatDate(root.bounds[index], "ddd d") + (root.week ? `  ${root.airingsOn(index).length}` : "")
                    icon: index === root.today ? "today" : ""
                    selected: root.day === index
                    clickable: true
                    onClicked: root.day = index
                }
            }
        }

        GridView {
            id: grid

            readonly property int columns: Math.max(2, Math.floor(width / 176))

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.shown.length > 0
            clip: true
            cellWidth: width / columns
            cellHeight: (cellWidth - Theme.spacing.large) * 1.45 + 80
            model: root.shown
            ScrollBar.vertical: StyledScrollBar {}

            delegate: Item {
                id: cell

                required property var modelData

                width: grid.cellWidth
                height: grid.cellHeight

                PosterCard {
                    anchors.fill: parent
                    anchors.margins: Theme.spacing.large / 2
                    title: cell.modelData.anime.title_english || cell.modelData.anime.title_romaji
                    subtitle: Qt.formatTime(new Date(cell.modelData.airing_at * 1000), "hh:mm")
                    image: cell.modelData.anime.cover
                    badge: `Ep ${cell.modelData.episode}`
                    onClicked: root.open(cell.modelData)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.shown.length === 0

            Loading {
                anchors.centerIn: parent
                visible: root.week === null && !root.failed
            }
            EmptyState {
                anchors.centerIn: parent
                visible: root.week !== null || root.failed
                face: root.failed ? "(×﹏×)" : "(・・ )?"
                title: root.failed ? "Couldn't load the schedule" : "Nothing airs this day"

                TextButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacing.small
                    visible: root.failed
                    type: TextButton.Tonal
                    text: "Try again"
                    onClicked: root.load(true)
                }
            }
        }
    }

    AnimeInfoDialog {
        id: info
    }
}
