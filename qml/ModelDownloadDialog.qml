import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: downloadDialog
    modal: true
    standardButtons: Dialog.Close

    property var submitPrompt: null
    property bool downloadComplete: false

    width: 550
    height: 450

    // Center in parent
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    contentItem: Item {
        ColumnLayout {
            anchors.fill: parent
            spacing: 20

            // Header
            Label {
                text: "No models found. Download a model to get started."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                font.pointSize: 11
                font.bold: true
            }

            // Models list
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                color: "#f5f5f5"
                border.color: "#ddd"
                border.width: 1
                radius: 4

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 8

                    Label {
                        text: "Available Models:"
                        font.bold: true
                        font.pointSize: 10
                    }

                    Label {
                        text: "• nxp/Qwen2.5-VL-7B-Instruct-Ara240"
                        font.pointSize: 10
                        font.family: "monospace"
                    }
                }
            }

            // Status display
            RowLayout {
                visible: submitPrompt && submitPrompt.isDownloadingModels && !downloadComplete
                spacing: 15
                Layout.fillWidth: true

                // Animated spinner
                BusyIndicator {
                    running: true
                    implicitWidth: 48
                    implicitHeight: 48
                }

                // Status text
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Label {
                        text: submitPrompt ? submitPrompt.downloadStatus : ""
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pointSize: 9
                    }
                }
            }

            // Enhanced progress bar with percentage
            Rectangle {
                visible: submitPrompt && submitPrompt.isDownloadingModels && !downloadComplete
                Layout.fillWidth: true
                height: 60
                color: "#f8f9fa"
                border.color:  "#dee2e6"
                border.width: 1
                radius: 4

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            text: "Download Progress"
                            font.bold: true
                            font.pointSize: 9
                        }

                        Item { Layout.fillWidth: true }
                        Label {
                            text: submitPrompt ?
                                  (submitPrompt.downloadProgress + "%") : "0%"
                            font.bold: true
                            font.pointSize: 10
                            color: "#007bff"
                        }
                    }

                    ProgressBar {
                        id: progressBar
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: submitPrompt ? submitPrompt.downloadProgress : 0

                        // Smooth animation
                        Behavior on value {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }
            }

            // Pulsing hint text
            Label {
                visible: submitPrompt && submitPrompt.isDownloadingModels &&
                        submitPrompt.downloadProgress > 0 &&
                        submitPrompt.downloadProgress < 100 &&
                        !downloadComplete
                text: "Large model files are being downloaded. This may take several minutes."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                font.pointSize: 10
                color: "#6c757d"
                horizontalAlignment: Text.AlignHCenter

                // Pulsing animation
                SequentialAnimation on opacity {
                    running: parent.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: 1500 }
                    NumberAnimation { to: 1.0; duration: 1500 }
                }
            }


            // Action buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Layout.topMargin: 10

                Button {
                    text: submitPrompt && submitPrompt.isDownloadingModels ?
                          "Downloading..." : "Start Download"
                    enabled: submitPrompt && !submitPrompt.isDownloadingModels
                    Layout.fillWidth: true
                    highlighted: true
                    icon.name: "download"

                    onClicked: {
                        console.log("[ModelDownloadDialog] Download button clicked")
                        if (submitPrompt) {
                            submitPrompt.downloadMissingModels()
                        }
                    }
                }

                Button {
                    text: "Cancel Download"
                    visible: submitPrompt && submitPrompt.isDownloadingModels
                    enabled: submitPrompt && submitPrompt.isDownloadingModels
                    Layout.fillWidth: true

                    onClicked: {
                        console.log("[ModelDownloadDialog] Cancel button clicked")
                        if (submitPrompt) {
                            submitPrompt.cancelDownload()
                        }
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }

    // Auto-close on success
    Connections {
        target: submitPrompt

        function onModelDownloadCompleted() {
            console.log("[ModelDownloadDialog] Download completed, closing dialog")
            downloadDialog.close()
        }
    }
}