// Zenbook Duo Power: what the laptop draws and where the power flows, in the panel;
// breakdown, temperatures, fans, power mode and battery in the popup.
// All numbers come from the org.zenbookduo.power plugin (sysfs, no helper processes).
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid
import org.zenbookduo.power

PlasmoidItem {
    id: root

    PowerMonitor {
        id: pm
        // slow in the panel, faster while the popup is open
        interval: root.expanded ? 1000 : 2000
    }

    function watts(w) { return w < 0 ? "–" : (w < 10 ? w.toFixed(1) : w.toFixed(0)) + " W" }
    function signedWatts(w) {
        const a = Math.abs(w)
        return (w >= 0.05 ? "+" : (w <= -0.05 ? "−" : "")) + (a < 10 ? a.toFixed(1) : a.toFixed(0)) + " W"
    }
    function duration(min) {
        if (min < 0) return ""
        const h = Math.floor(min / 60), m = min % 60
        return h > 0 ? h + " h " + m + " min" : m + " min"
    }
    function temp(t) { return t < 0 ? "–" : t.toFixed(0) + " °C" }

    readonly property double chipWatts: pm.raplAvailable ? pm.packageWatts + Math.max(0, pm.memoryWatts) : -1
    // what the laptop itself draws; without the platform sensor, on AC only the chip is known
    readonly property double headline: pm.systemWatts >= 0 ? pm.systemWatts : chipWatts
    readonly property string flowState: pm.batteryState
    readonly property bool flowShown: pm.onAc && (flowState === "charging" || flowState === "draining" || flowState === "limit")
    readonly property color flowColor: flowState === "charging" ? Kirigami.Theme.positiveTextColor
                                     : flowState === "draining" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
    readonly property string chargerName: pm.chargerMaxWatts > 0 ? Math.round(pm.chargerMaxWatts) + " W charger" : "charger"
    readonly property string limitText: pm.chargeLimit > 0 && pm.chargeLimit < 100 ? " (limit " + pm.chargeLimit + "%)" : ""
    readonly property string stateText: {
        const pct = pm.batteryPercent + "%"
        switch (flowState) {
        case "discharging":
            return pct + " · on battery" + (pm.minutesToEmpty >= 0 ? " · " + duration(pm.minutesToEmpty) + " left" : "")
        case "charging":
            return pct + " · charging at " + watts(Math.max(0, pm.batteryWatts)) +
                   (pm.minutesToFull >= 0 ? " · full in " + duration(pm.minutesToFull) + limitText : "")
        case "draining":
            return pct + " · draining at " + watts(-pm.batteryWatts) + " although plugged in" +
                   (pm.minutesToEmpty >= 0 ? " · " + duration(pm.minutesToEmpty) + " left" : "")
        case "limit":
            return pct + " · the " + chargerName + " is fully used, the battery holds about even"
        case "full":
            return pct + " · fully charged"
        default:
            return pct + " · plugged in, not charging" + limitText
        }
    }
    // the four parts of the breakdown; "rest" needs the whole-laptop number
    readonly property var parts: [
        { name: "Processor cores", w: pm.coreWatts, color: "#3daee9" },
        { name: "Graphics & chip", w: pm.socWatts, color: "#a77ee6" },
        { name: "Memory", w: pm.memoryWatts, color: "#2ecc9a" },
        { name: "Screens, Wi-Fi, SSD & rest", w: pm.restWatts, color: "#8a94a0" }
    ]
    readonly property string batteryIcon: {
        const level = Math.max(0, Math.min(100, Math.round(pm.batteryPercent / 10) * 10))
        const name = "battery-" + ("00" + level).slice(-3)
        return pm.onAc && flowState !== "draining" ? name + "-charging" : name
    }

    preferredRepresentation: compactRepresentation
    toolTipMainText: "Laptop draws " + watts(headline) + (flowShown ? " · battery " + signedWatts(pm.batteryWatts) : "")
    toolTipSubText: stateText

    compactRepresentation: MouseArea {
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                source: root.batteryIcon
            }
            PlasmaComponents.Label {
                text: root.watts(root.headline)
                font.features: { "tnum": 1 } // fixed-width digits: the panel does not jiggle
            }
            PlasmaComponents.Label {
                visible: root.flowShown
                text: root.signedWatts(pm.batteryWatts)
                color: root.flowColor
                font.features: { "tnum": 1 }
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
        Layout.maximumHeight: Layout.minimumHeight
        collapseMarginsHint: true

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            // ── headline ───────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                    source: root.batteryIcon
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    PlasmaComponents.Label {
                        text: root.watts(root.headline)
                        font.pixelSize: Kirigami.Units.gridUnit * 2
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                    PlasmaComponents.Label {
                        text: pm.systemWatts < 0 ? "processor + memory only (the laptop's sensor is not readable)"
                            : pm.onAc ? "the laptop itself, charging not included" : "the whole laptop, from the battery"
                        opacity: 0.65
                        font: Kirigami.Theme.smallFont
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    PlasmaComponents.Label {
                        text: root.stateText
                        color: root.flowState === "draining" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }
                }
            }

            // ── power flow: charger → laptop + battery ─────────────────
            RowLayout {
                Layout.fillWidth: true
                visible: pm.onAc && pm.chargerWatts >= 0
                spacing: Kirigami.Units.largeSpacing
                Repeater {
                    model: [
                        { name: "From the charger", value: root.watts(pm.chargerWatts),
                          note: pm.chargerMaxWatts > 0 ? "of " + Math.round(pm.chargerMaxWatts) + " W · " + pm.chargerVolts.toFixed(0) + " V " + pm.chargerAmps.toFixed(1) + " A" : "", color: Kirigami.Theme.textColor },
                        { name: "Laptop", value: root.watts(root.headline), note: "", color: Kirigami.Theme.textColor },
                        { name: "Battery", value: root.flowState === "full" || root.flowState === "idle" ? "0 W" : root.signedWatts(pm.batteryWatts),
                          note: root.flowState === "charging" ? "charging" : root.flowState === "draining" ? "helping out" : root.flowState === "limit" ? "about even" : root.flowState === "full" ? "full" : "not charging",
                          color: root.flowColor }
                    ]
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.minimumWidth: 0
                        Layout.horizontalStretchFactor: 1 // equal thirds
                        Layout.alignment: Qt.AlignTop
                        spacing: 0
                        PlasmaComponents.Label { text: modelData.name; opacity: 0.7; font: Kirigami.Theme.smallFont; Layout.fillWidth: true; elide: Text.ElideRight }
                        PlasmaComponents.Label { text: modelData.value; color: modelData.color; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
                        PlasmaComponents.Label { text: modelData.note; opacity: 0.6; font: Kirigami.Theme.smallFont; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
            }
            PlasmaComponents.Label {
                visible: pm.onAc && (root.flowState === "draining" || root.flowState === "limit" || (pm.chargerSlow && root.flowState === "charging"))
                text: root.flowState === "charging" ? "Slow charger: the battery charges only with the power the laptop leaves over."
                    : "This " + root.chargerName + " cannot keep up with the current load, so the battery " +
                      (root.flowState === "draining" ? "covers the difference." : "hardly charges.") + " A 65 W or stronger USB-C charger avoids this."
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.75
                font: Kirigami.Theme.smallFont
            }

            // ── breakdown: one stacked bar + legend ─────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: pm.raplAvailable

                Item {
                    id: bar
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 0.6
                    readonly property double sum: root.parts.reduce((a, p) => a + Math.max(0, p.w), 0)
                    Rectangle { anchors.fill: parent; radius: height / 2; color: Kirigami.Theme.textColor; opacity: 0.08 }
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: root.parts
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                height: bar.height
                                width: bar.sum > 0 ? bar.width * Math.max(0, modelData.w) / bar.sum : 0
                                color: modelData.color
                                radius: index === 0 || index === root.parts.length - 1 ? height / 2 : 0
                                Behavior on width { NumberAnimation { duration: Kirigami.Units.longDuration } }
                            }
                        }
                    }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: Kirigami.Units.smallSpacing
                    rowSpacing: Math.round(Kirigami.Units.smallSpacing / 2)
                    Repeater {
                        model: root.parts
                        delegate: RowLayout {
                            required property var modelData
                            visible: modelData.w >= 0
                            Layout.columnSpan: 3
                            Layout.fillWidth: true
                            Rectangle {
                                Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                                Layout.preferredHeight: Layout.preferredWidth
                                radius: width / 2
                                color: modelData.color
                            }
                            PlasmaComponents.Label { text: modelData.name; Layout.fillWidth: true; elide: Text.ElideRight }
                            PlasmaComponents.Label {
                                text: bar.sum > 0 ? Math.round(100 * Math.max(0, modelData.w) / bar.sum) + "%" : ""
                                opacity: 0.6
                                font.features: { "tnum": 1 }
                            }
                            PlasmaComponents.Label {
                                text: root.watts(modelData.w)
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }
            PlasmaComponents.Label {
                visible: !pm.raplAvailable || pm.systemWatts < 0
                text: "The breakdown and the total on AC need read access to the processor's energy counters: sudo ./duo apply desktop-power-widget"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.65
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // ── sensors ────────────────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: [
                        { icon: "temperature-normal", name: "Processor", value: root.temp(pm.cpuTemp) },
                        { icon: "drive-harddisk-solidstate", name: "SSD", value: root.temp(pm.ssdTemp) },
                        { icon: "network-wireless", name: "Wi-Fi", value: root.temp(pm.wifiTemp) },
                        { icon: "fan", name: "Fans", value: pm.fanCpu < 0 ? "–" : (pm.fanCpu === 0 && pm.fanGpu === 0 ? "off" : pm.fanCpu + " · " + pm.fanGpu + " rpm") }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            source: modelData.icon
                            fallback: "temperature-normal"
                            opacity: 0.8
                        }
                        PlasmaComponents.Label { text: modelData.name; opacity: 0.7 }
                        PlasmaComponents.Label { text: modelData.value; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; font.features: { "tnum": 1 } }
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // ── power mode ─────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                QQC2.ButtonGroup { id: modes }
                Repeater {
                    model: [
                        { id: "power-saver", label: "Quiet", icon: "battery-profile-powersave" },
                        { id: "balanced", label: "Balanced", icon: "battery-profile-balanced" },
                        { id: "performance", label: "Performance", icon: "battery-profile-performance" }
                    ]
                    delegate: PlasmaComponents.ToolButton {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1 // equal thirds
                        text: modelData.label
                        icon.name: modelData.icon
                        checkable: true
                        QQC2.ButtonGroup.group: modes
                        checked: pm.profile === modelData.id
                        onClicked: pm.setProfile(modelData.id)
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // ── battery ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    opacity: 0.8
                    text: "Battery health " + (pm.healthPercent < 0 ? "–" : pm.healthPercent + "%") +
                          " · " + pm.cycles + " cycles · " +
                          (pm.chargeLimit < 0 || pm.chargeLimit >= 100 ? "charges to 100%" : "stops at " + pm.chargeLimit + "%")
                }
                PlasmaComponents.ToolButton {
                    icon.name: "configure"
                    text: "Settings"
                    display: QQC2.AbstractButton.IconOnly
                    PlasmaComponents.ToolTip.text: "Power settings (charge limit, screen, sleep)"
                    PlasmaComponents.ToolTip.visible: hovered
                    onClicked: pm.openPowerSettings()
                }
            }
        }
    }
}
