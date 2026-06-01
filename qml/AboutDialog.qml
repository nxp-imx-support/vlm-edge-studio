/*
 * Copyright 2025-2026 NXP
 *
 * NXP Proprietary. This software is owned or controlled by NXP and may only be
 * used strictly in accordance with the applicable license terms.  By expressly
 * accepting such terms or by downloading, installing, activating and/or
 * otherwise using the software, you are agreeing that you have read, and that
 * you agree to comply with and are bound by, such license terms.  If you do
 * not agree to be bound by the applicable license terms, then you may not
 * retain, install, activate or otherwise use the software.
 *
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts

Window {
    id: root

    // Window configuration
    width: screenWidth
    height: screenHeight
    visible: false
    flags: Qt.Dialog | Qt.FramelessWindowHint
    modality: Qt.ApplicationModal
    color: "transparent"

    // Constants
    readonly property int screenWidth: 1920
    readonly property int screenHeight: 1080
    readonly property int dialogWidth: 720
    readonly property int dialogHeight: 320

    // Theme colors
    readonly property color backgroundColor: "#262626"
    readonly property color borderColor: "#0eafe0"
    readonly property color textColor: "#ffffff"
    readonly property color buttonColor: "#EBE7DD"

    // Spacing constants
    readonly property int outerMargin: 25
    readonly property int innerMargin: 10
    readonly property int sectionSpacing: 15
    readonly property int borderRadius: 30
    readonly property int buttonRadius: 15

    // Typography
    readonly property string fontFamily: "Poppins"
    readonly property int titleSize: 24
    readonly property int headerSize: 18
    readonly property int bodySize: 11

    // Center window on screen using property bindings (Design Studio friendly)
    x: (screenWidth - width) / 2
    y: (screenHeight - height) / 2

    // Background rectangle (dialog box)
    Rectangle {
        id: dialogBackground
        width: dialogWidth
        height: dialogHeight
        anchors.centerIn: parent
        color: backgroundColor
        radius: borderRadius
        border.color: borderColor
        border.width: 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: outerMargin
            spacing: innerMargin

	        // Title
            Label {
	            text: qsTr("VLM Edge Studio v" + Qt.application.version)
                font.family: fontFamily
                font.pixelSize: titleSize
                font.styleName: "Bold"
                color: textColor
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            // Copyright
            Label {
                text: qsTr("Copyright 2025-2026 NXP")
                font.family: fontFamily
                font.pixelSize: headerSize
                color: textColor
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            // License
            Label {
    	        text: qsTr("LA_OPT_NXP_Software_License - Section 2.3 applies")
            	font.family: fontFamily
                font.pixelSize: headerSize
                color: textColor
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            // Qt License
            Label {
                text: qsTr("Qt libraries under LGPL-3.0-only license")
                font.family: fontFamily
                font.pixelSize: headerSize
                color: textColor
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.topMargin: innerMargin
            }

            // Trademarks
            Label {
                text: qsTr("Trademarks and Service Marks: There are a number of proprietary logos, service marks, trademarks, slogans and product designations (\"Marks\") found on this Software. By making the Marks available on this Software, NXP is not granting you a license to use them in any fashion. Access to this Software does not confer upon you any license to the Marks under any of NXP or any third party's intellectual property rights.\n\nNXP and the NXP logo are trademarks of NXP B.V. © 2026 NXP B.V.")
                font.family: fontFamily
                font.pixelSize: bodySize
                color: textColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 5
            }

            // Close Button
            Button {
                text: qsTr("CLOSE")
                font.family: fontFamily
                font.bold: true
                Layout.preferredWidth: 80
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 10

                background: Rectangle {
                    color: buttonColor
                    radius: buttonRadius
                    implicitWidth: 80
                    implicitHeight: 40
                }

                onClicked: root.close()
            }

            // Spacer to push button to bottom
            Item {
                Layout.fillHeight: true
                Layout.minimumHeight: 10
            }
        }
    }
}
