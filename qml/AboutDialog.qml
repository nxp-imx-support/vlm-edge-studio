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
    id: aboutWindow
    width: 1920
    height: 1080
    visible: false
    flags: Qt.Dialog | Qt.FramelessWindowHint
    modality: Qt.ApplicationModal
    color: "transparent"

    function center() {
        x = (1920 - width) / 2
        y = (1080 - height) / 2
    }

    // Center on screen when shown
    onVisibleChanged: {
        if (visible) {
            Qt.callLater(center)
        }
    }

    Component.onCompleted: {
        if (visible) {
            Qt.callLater(center)
        }
    }

    Rectangle {
        id: rectangle
        width: 720
        height: 385
        color: "#262626"
        radius: 30
        border.color: "#0eafe0"
        border.width: 2
        anchors.centerIn: parent

        Text {
            id: title
            height: 35
            color: "#ffffff"
            text: qsTr("VLM Edge Studio v" + Qt.application.version)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 25
            font.pixelSize: 24
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.styleName: "Bold"
            font.family: "Poppins"
        }

        Text {
            id: copyright
            color: "#ffffff"
            text: qsTr("Copyright 2024-2026 NXP")
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: title.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 0
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: "Poppins"
        }

        Text {
            id: license
            color: "#ffffff"
            text: qsTr("LA_OPT_NXP_Software_License - Section 2.3 applies")
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: copyright.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 0
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: "Poppins"
        }

        Text {
            id: qt
            color: "#ffffff"
            text: qsTr("Qt libraries under LGPL-3.0-only license")
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: license.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 10
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: "Poppins"
        }

        Text {
            id: trademarks
            color: "#ffffff"
            text: qsTr("Trademarks and Service Marks: There are a number of proprietary logos, service marks, trademarks, slogans and product designations (\"Marks\") found on this Software. By making the Marks available on this Software, NXP is not granting you a license to use them in any fashion. Access to this Software does not confer upon you any license to the Marks under any of NXP or any third party's intellectual property rights.

NXP and the NXP logo are trademarks of NXP B.V. © 2025 NXP B.V.")
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: qt.bottom
            anchors.leftMargin: 45
            anchors.rightMargin: 45
            anchors.topMargin: 15
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            font.family: "Poppins"
        }

        Button {
            id: close_button_about
            width: 80
            text: qsTr("CLOSE")
            anchors.top: trademarks.bottom
            anchors.bottom: parent.bottom
            anchors.topMargin: 15
            anchors.bottomMargin: 25
            anchors.horizontalCenterOffset: 0
            font.bold: true
            font.family: "Poppins"
            anchors.horizontalCenter: parent.horizontalCenter
            display: AbstractButton.TextOnly

            background: Rectangle {
                color: "#EBE7DD" // Blue background
                radius: 15
            }
            onClicked: {
                aboutWindow.visible = false
                aboutWindow.close()
            }
        }
    }
}
