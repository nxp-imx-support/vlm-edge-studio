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
 */
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import QtQuick.Dialogs
import QtQuick.Layouts
import GStreamerApp 1.0
import SubmitPrompt 1.0

Window {
    id: window
    width: 1920
    height: 1080
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    visibility: "FullScreen"
    color: "#000000"

    // ═══════════════════════════════════════════════════════════════
    // COLOR SCHEME
    // ═══════════════════════════════════════════════════════════════
    readonly property color bgPrimary: "#000000"
    readonly property color bgSecondary: "#1C1C1E"
    readonly property color bgTertiary: "#2C2C2E"
    readonly property color accentPrimary: "#0A84FF"
    readonly property color accentSecondary: "#30D158"
    readonly property color accentWarning: "#FF9F0A"
    readonly property color textPrimary: "#FFFFFF"
    readonly property color textSecondary: "#98989D"
    readonly property color borderActive: "#0A84FF"
    readonly property color borderInactive: "#38383A"
    readonly property string defaultImagePath: "/usr/share/vlm-edge-studio/assets/images/image.jpg"
    readonly property string defaultVideoPath: "/usr/share/vlm-edge-studio/assets/videos/video.mp4"

    // ═══════════════════════════════════════════════════════════════
    // STATE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════
    // Analysis mode (driven by loaded model)
    property string analysisMode: "none" // "none", "image", "video"
    // Media input source
    property string mediaSource: "none" // "none", "file", "camera"
    // Last loaded media
    property string loadedMediaPath: ""

    // Processing state
    property bool isRecording: false
    property bool isProcessing: false
    property bool showRecordingIndicator: false
    property bool showProcessingIndicator: false

    // Aliases for UI components
    property alias input_prompt: input_prompt
    property alias scrollView: scrollView
    property alias media_rectangle: media_rectangle
    property alias submit_button: submit_button
    property alias output_llm_rectangle: output_llm_rectangle
    readonly property bool multiEndpoint: false
    readonly property bool cancelSupport: false

    // ═══════════════════════════════════════════════════════════════
    // STATE HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    // Load image from file
    function loadImageFile(imagePath) {
        analysisMode = "image"
        mediaSource = "file"

        // Format path for QML Image component (needs file://)
        var qmlPath = imagePath.toString()
        if (!qmlPath.startsWith("file://") && qmlPath.startsWith("/")) {
            qmlPath = "file://" + qmlPath
        }
        loadedMediaPath = qmlPath

        // Format path for backend (no file://)
        var backendPath = imagePath.toString().replace(/^file:\/\//, "")
        console.log("[STATE] QML path:", qmlPath)
        console.log("[STATE] Backend path:", backendPath)

        // Store current loaded media
        loadedMediaPath = backendPath
        console.log("[STATE] Stored loadedMediaPath:", loadedMediaPath)

        // Update backend
        mySubmitPrompt.setActiveMediaType("image")
        mySubmitPrompt.setImageSourcePath(backendPath)

        // Stop any video pipeline
        video_1.setPlaying(false)
        video_1.setCameraStream(false)

        // Stop any video pipeline
        video_1.setPlaying(false)
        video_1.setCameraStream(false)
        video_1.stopPipeline()

        console.log("[STATE] Image file loaded, ready for analysis")
    }

    // Load video from file
    function loadVideoFile(videoPath) {
        analysisMode = "video"
        mediaSource = "file"

        // Format path for backend (no file://)
        var backendPath = videoPath.toString().replace(/^file:\/\//, "")

        // Set as current loaded media
        loadedMediaPath = backendPath
        console.log("[STATE] Stored loadedMediaPath:", loadedMediaPath)

        // Update backend
        mySubmitPrompt.setActiveMediaType("video")
        mySubmitPrompt.setVideoSourcePath(backendPath)

        // Stop camera if active
        if (video_1.cameraStream) {
            video_1.setCameraStream(false)
        }

        // Update video player
        video_1.setVideoSource(videoPath)
        video_1.startPipeline()

        console.log("[STATE] Video file loaded, ready for playback")
    }

    // Activate camera for image capture
    function activateCameraForImage() {
        analysisMode = "image"
        mediaSource = "camera"

        // Clear output immediately
        mySubmitPrompt.clearOutputDisplay()

        // Update backend
        mySubmitPrompt.setActiveMediaType("image")

        // Start camera stream
        video_1.setCameraStream(true)
        video_1.startPipeline()

        console.log("[STATE] Camera active - use Capture button to grab frame")
    }

    // Activate camera for video recording
    function activateCameraForVideo() {
        analysisMode = "video"
        mediaSource = "camera"

        // Clear output immediately
        mySubmitPrompt.clearOutputDisplay()

        // Update backend
        mySubmitPrompt.setActiveMediaType("video")

        // Start camera stream
        video_1.setCameraStream(true)
        video_1.startPipeline()

        console.log("[STATE] Camera active - use Capture button to record video")
    }

    // Check if submit is allowed
    function canSubmit() {
        // Need a loaded model
        if (!mySubmitPrompt.isModelLoaded)
            return false

        // Can't submit while processing
        if (isRecording || isProcessing || mySubmitPrompt.isProcessingInference)
            return false

        // Need media loaded
        if (analysisMode === "image") {
            // For image: need file loaded OR captured frame
            return mediaSource === "file" && loadedMediaPath !== ""
        } else if (analysisMode === "video") {
            // For video: need file loaded OR recorded video
            return mediaSource === "file" && loadedMediaPath !== ""
        }

        return false
    }

    // Reset to initial state
    function resetToInitialState() {
        console.log("[RESET] Resetting to initial state")

        // Stop pipelines
        if (video_1.playing)
            video_1.setPlaying(false)
        if (video_1.cameraStream)
            video_1.setCameraStream(false)
        video_1.stopPipeline()

        // Clear state
        analysisMode = "none"
        mediaSource = "none"
        loadedMediaPath = ""
        imageDisplay.source = ""

        // Reset backend
        mySubmitPrompt.setActiveMediaType("")
        mySubmitPrompt.setImageSourcePath("")
        mySubmitPrompt.setVideoSourcePath("")
        mySubmitPrompt.clearOutputDisplay()

        // Reset flags
        isRecording = false
        isProcessing = false
        showRecordingIndicator = false
        showProcessingIndicator = false

        // Stop timers
        recordingIndicatorTimer.stop()
        loadVideoTimer.stop()
        videoUpdateTimer.stop()
        progressTimerImage.stop()
        progressBarImage.value = 0

        console.log("[RESET] Ready for new analysis")
    }

    // ═══════════════════════════════════════════════════════════════
    // DEFAULT MEDIA LOADING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    function loadDefaultMedia() {
        console.log("[DEFAULT] Loading default media...")
        console.log("[DEFAULT] Analysis mode:", analysisMode)

        // Determine what to load based on model capabilities and preference
        if (analysisMode === "image"
                && mySubmitPrompt.modelSupportsImage) {
            loadDefaultImage()
        } else if (analysisMode === "video"
                   && mySubmitPrompt.modelSupportsVideo) {
            loadDefaultVideo()
        } else {
            console.log("[DEFAULT] No suitable default media for current model")
        }
    }

    function loadDefaultImage() {
        console.log("[DEFAULT] Loading default image:", defaultImagePath)

        // Check if file exists (optional - you can skip this)
        if (!Qt.resolvedUrl(defaultImagePath)) {
            console.warn("[DEFAULT] Default image not found:", defaultImagePath)
            return
        }

        // Load the image
        progressBarImage.value = 0
        mySubmitPrompt.isLoadingMedia = true
        loadImageFile(defaultImagePath)
        loadVideoTimer.start()

        console.log("[DEFAULT] Default image loaded successfully")
    }

    function loadDefaultVideo() {
        console.log("[DEFAULT] Loading default video:", defaultVideoPath)

        // Check if file exists (optional)
        if (!Qt.resolvedUrl(defaultVideoPath)) {
            console.warn("[DEFAULT] Default video not found:", defaultVideoPath)
            return
        }

        // Load the video
        progressBarImage.value = 0
        mySubmitPrompt.isLoadingMedia = true
        loadVideoFile(defaultVideoPath)
        loadVideoTimer.start()

        console.log("[DEFAULT] Default video loaded successfully")
    }

    function restoreImageFileMode() {
        console.log("[STATE] Restoring image file mode")
        // Determine which path to use
        var pathToLoad = ""

        if (loadedMediaPath !== "") {
            // Use stored path (from previous load or capture)
            pathToLoad = loadedMediaPath
            console.log("[STATE] Using stored loadedMediaPath:", pathToLoad)
        } else if (defaultImagePath !== "") {
            // Fallback to default
            pathToLoad = defaultImagePath
            console.log("[STATE] No previous image, using default:", pathToLoad)
        } else {
            console.warn("[STATE] No image path available")
            return
        }

        // Load the image
        progressBarImage.value = 0
        mySubmitPrompt.isLoadingMedia = true
        loadImageFile(pathToLoad)
        loadVideoTimer.start()
    }

    function restoreVideoFileMode() {
        console.log("[STATE] Restoring video file mode")

        // Determine which path to use
        var pathToLoad = ""

        if (loadedMediaPath !== "") {
            // Use stored path (from previous load or record)
            pathToLoad = loadedMediaPath
            console.log("[STATE] Using stored loadedMediaPath:", pathToLoad)
        } else if (defaultVideoPath !== "") {
            // Fallback to default
            pathToLoad = defaultVideoPath
            console.log("[STATE] No previous video, using default:", pathToLoad)
        } else {
            console.warn("[STATE] No video path available")
            return
        }

        // Load the video
        progressBarImage.value = 0
        mySubmitPrompt.isLoadingMedia = true
        loadVideoFile(pathToLoad)
        loadVideoTimer.start()
    }

    // ═══════════════════════════════════════════════════════════════
    // BACKEND CONNECTION
    // ═══════════════════════════════════════════════════════════════
    SubmitPrompt {
        id: mySubmitPrompt

        onIsModelLoadedChanged: {
            console.log("[MODEL] Model loaded changed:",
                        mySubmitPrompt.isModelLoaded)

            if (mySubmitPrompt.isModelLoaded) {
                // Model loaded - set analysis mode based on capabilities
                if (mySubmitPrompt.modelSupportsImage) {
                    window.analysisMode = "image"
                    console.log("[MODEL] Auto-set to Image Analysis mode")
                } else if (mySubmitPrompt.modelSupportsVideo) {
                    window.analysisMode = "video"
                    console.log("[MODEL] Auto-set to Video Analysis mode")
                } else {
                    // Text-only model
                    window.analysisMode = "none"
                    console.log("[MODEL] Text-only model, no analysis mode")
                }
                // Auto load default media
                loadDefaultMedia()
            } else {
                // Model unloaded - reset
                window.analysisMode = "none"
                window.mediaSource = "none"
                window.loadedMediaPath = ""
                console.log("[MODEL] Model unloaded, reset analysis mode")
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // CAMERA RECORDING WORKFLOW
    // ═══════════════════════════════════════════════════════════════
    Connections {
        target: video_1

        // VIDEO RECORDING: Recording finished (frames captured)
        function onRecordingFinished(videoPath) {
            console.log("[RECORDING] Finished capturing frames:", videoPath)

            // 1. Hide red "REC" indicator
            window.showRecordingIndicator = false
            window.isRecording = false

            // 2. Show "Processing video..." indicator
            window.showProcessingIndicator = true
            window.isProcessing = true

            // 3. Store the recorded video path
            window.loadedMediaPath = videoPath
            console.log("[RECORDING] Updated loadedMediaPath:",
                        window.loadedMediaPath)

            // 4. Update backend
            mySubmitPrompt.handleRecordingComplete(videoPath)
            console.log("[RECORDING] Encoding in background...")
        }

        // VIDEO RECORDING: Encoding complete, ready for playback
        function onVideoModeActivated() {
            console.log("[RECORDING] Encoding complete, switching to playback")

            // 1. Hide "Processing video..." indicator
            window.showProcessingIndicator = false
            window.isProcessing = false

            // 2. Switch to video mode
            window.mediaSource = "file"
            window.analysisMode = "video"

            // 3. Show success notification
            recordingCompleteToast.visible = true
            recordingCompleteToast.opacity = 1
            toastTimer.start()

            console.log("[RECORDING] Video ready for analysis!")
        }

        function onRecordingProgress(current, total) {
            var percentage = Math.round((current / total) * 100)
        }

        // IMAGE CAPTURE: Frame captured
        function onFrameCaptured(imagePath) {
            console.log("[CAPTURE] Frame captured:", imagePath)

            // Load the captured frame
            window.loadImageFile(imagePath)

            // Show success notification
            captureCompleteToast.visible = true
            captureCompleteToast.opacity = 1
            captureToastTimer.start()
            console.log("[CAPTURE] Frame ready for analysis!")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // UI INDICATORS
    // ═══════════════════════════════════════════════════════════════
    // INDICATOR 1: Red "REC" during frame capture
    Rectangle {
        id: recordingIndicator
        width: 120
        height: 40
        color: "#80000000"
        radius: 8
        anchors.top: media_rectangle.top
        anchors.right: media_rectangle.right
        anchors.topMargin: 50
        anchors.rightMargin: 50
        visible: window.showRecordingIndicator
        z: 2000

        Row {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                id: recordingDot
                width: 12
                height: 12
                radius: 6
                color: "#FF0000"
                anchors.verticalCenter: parent.verticalCenter

                SequentialAnimation on opacity {
                    running: recordingIndicator.visible
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.2
                        duration: 600
                    }
                    NumberAnimation {
                        to: 1.0
                        duration: 600
                    }
                }
            }

            Text {
                text: "REC"
                color: "#FF0000"
                font.pixelSize: 16
                font.bold: true
                font.family: "Poppins"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // INDICATOR 2: "Processing video..." during encoding
    Rectangle {
        id: processingIndicator
        width: 250
        height: 50
        color: "#80000000"
        radius: 8
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 150
        visible: window.showProcessingIndicator
        z: 2000

        Row {
            anchors.centerIn: parent
            spacing: 12

            BusyIndicator {
                width: 32
                height: 32
                running: processingIndicator.visible

                contentItem: Item {
                    implicitWidth: 32
                    implicitHeight: 32

                    Item {
                        id: processingSpinner
                        x: parent.width / 2 - 16
                        y: parent.height / 2 - 16
                        width: 32
                        height: 32

                        RotationAnimator {
                            target: processingSpinner
                            running: processingIndicator.visible
                            from: 0
                            to: 360
                            loops: Animation.Infinite
                            duration: 1500
                        }

                        Repeater {
                            model: 8

                            Rectangle {
                                id: spinnerDot
                                x: processingSpinner.width / 2 - width / 2
                                y: processingSpinner.height / 2 - height / 2
                                implicitWidth: 4
                                implicitHeight: 4
                                radius: 2
                                color: "#0eafe0"

                                required property int index

                                transform: [
                                    Translate {
                                        y: -12
                                    },
                                    Rotation {
                                        angle: spinnerDot.index * 45
                                        origin.x: 2
                                        origin.y: 12
                                    }
                                ]

                                opacity: 0.3 + (0.7 * ((spinnerDot.index + 1) / 8))
                            }
                        }
                    }
                }
            }

            Text {
                text: "Processing video..."
                color: "#FFFFFF"
                font.pixelSize: 16
                font.family: "Poppins"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // INDICATOR 3: Success toast
    Rectangle {
        id: recordingCompleteToast
        width: 350
        height: 50
        color: "#69CA00"
        radius: 8
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 150
        visible: false
        opacity: 0
        z: 1000

        Text {
            anchors.centerIn: parent
            text: "✓ Video ready for analysis!"
            color: "#FFFFFF"
            font.pixelSize: 18
            font.family: "Poppins"
            font.bold: true
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 300
            }
        }

        Timer {
            id: toastTimer
            interval: 3000
            repeat: false
            onTriggered: {
                recordingCompleteToast.opacity = 0
                hideTimer.start()
            }
        }

        Timer {
            id: hideTimer
            interval: 300
            repeat: false
            onTriggered: recordingCompleteToast.visible = false
        }
    }

    // INDICATOR 4: Success toast for frame capture
    Rectangle {
        id: captureCompleteToast
        width: 350
        height: 50
        color: "#69CA00"
        radius: 8
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 150
        visible: false
        opacity: 0
        z: 1000

        Text {
            anchors.centerIn: parent
            text: "✓ Frame captured!"
            color: "#FFFFFF"
            font.pixelSize: 18
            font.family: "Poppins"
            font.bold: true
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 300
            }
        }

        Timer {
            id: captureToastTimer
            interval: 2000
            onTriggered: {
                captureCompleteToast.opacity = 0
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // UI AboutDialog
    // ═══════════════════════════════════════════════════════════════
    AboutDialog {
        id: aboutWindow
    }

    // ═══════════════════════════════════════════════════════════════
    // UI Timers
    // ═══════════════════════════════════════════════════════════════
    Timer {
        id: progressTimerModelLoad
        interval: 200
        repeat: true
        running: mySubmitPrompt.shouldLoadModel
        onTriggered: {
            if (progressBarModel.value < (progressBarModel.to * 0.95)) {
                progressBarModel.value += 100
            }
        }

        onRunningChanged: {
            if (running) {
                // Reset to 0 when loading starts
                progressBarModel.value = 0
            } else {
                // When stopped (model ready), jump to 100%
                progressBarModel.value = progressBarModel.to
            }
        }
    }

    Timer {
        id: resetTimer
        interval: 10
        repeat: false
        onTriggered: {
            mySubmitPrompt.setLoadModel(true)
        }
    }

    Timer {
        id: progressTimerImage
        interval: 200
        repeat: true
        running: mySubmitPrompt.isLoadingMedia
        onTriggered: {
            if (progressBarImage.value < progressBarImage.to) {
                progressBarImage.value += 100
            }
        }
    }

    Timer {
        id: loadVideoTimer
        interval: 3000
        repeat: false
        onTriggered: {
            mySubmitPrompt.isLoadingMedia = false
            if (window.analysisMode === "video") {
                console.log("[QML] Loading QwenVL model for video analysis")
            }
        }
    }

    Timer {
        id: videoUpdateTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (window.analysisMode === "video") {
                console.log("[QML] videoUpdateTimer triggered")
                video_1.setPlaying(false)
                video_1.setPlaying(true)
            }
        }
    }

    Timer {
        id: recordingIndicatorTimer
        interval: 12000
        repeat: false
        onTriggered: {
            window.showRecordingIndicator = false
            window.isRecording = false
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // nxpBranding Rectangle
    // ═══════════════════════════════════════════════════════════════
    Rectangle {
        id: nxpBranding
        height: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 0
        anchors.rightMargin: 0
        anchors.topMargin: 0
        gradient: Gradient {

            GradientStop {
                position: 0.1
                color: "#F9B500"
            }

            GradientStop {
                position: 0.45
                color: "#69CA00"
            }

            GradientStop {
                position: 0.55
                color: "#69CA00"
            }

            GradientStop {
                position: 0.9
                color: "#0EAFE0"
            }

            orientation: Gradient.Horizontal
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Main Title Rectangle
    // ═══════════════════════════════════════════════════════════════
    Rectangle {
        id: mainTitle
        height: 125
        color: "#00ffffff"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: nxpBranding.bottom
        anchors.leftMargin: 0
        anchors.rightMargin: 0
        anchors.topMargin: 0

        Image {
            id: title_image
            height: 125
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 0
            anchors.rightMargin: 754
            horizontalAlignment: Image.AlignLeft
            source: "../images/title.png"
            fillMode: Image.PreserveAspectFit
        }

        Button {
            id: close_button
            icon.source: down ? "images/close_pressed.png" : "images/close.png"
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.leftMargin: 1650
            anchors.rightMargin: 25
            display: AbstractButton.IconOnly
            icon.height: 40
            icon.width: 120
            enabled: !isRecording && !isProcessing
                     && !mySubmitPrompt.isProcessingInference
                     && !mySubmitPrompt.isLoadingMedia
            opacity: enabled ? 1.0 : 0.3
            onClicked: {
                mySubmitPrompt.killConnectorProcess()
                Qt.quit()
            }

            background: Rectangle {
                color: close_button.enabled
                       && close_button.hovered ? "#404040" : "transparent"
                border.color: close_button.enabled
                              && close_button.hovered ? "#666666" : "transparent"
                border.width: 1

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }
        }

        Button {
            id: about_button
            icon.source: down ? "images/about_pressed.png" : "images/about.png"
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: close_button.left
            anchors.rightMargin: 15
            icon.height: 40
            icon.width: 120
            display: AbstractButton.IconOnly
            enabled: !isRecording && !isProcessing
                     && !mySubmitPrompt.isProcessingInference
                     && !mySubmitPrompt.isLoadingMedia
            opacity: enabled ? 1.0 : 0.3
            onClicked: aboutWindow.visible = true

            background: Rectangle {
                color: about_button.enabled
                       && about_button.hovered ? "#404040" : "transparent"
                border.color: about_button.enabled
                              && about_button.hovered ? "#666666" : "transparent"
                border.width: 1

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Input Rectangle
    // ═══════════════════════════════════════════════════════════════
    Rectangle {
        id: input_prompt_rectangle
        y: 700
        height: 100
        color: bgSecondary
        radius: 15
        border.color: accentPrimary
        border.width: 2
        anchors.left: output_llm_rectangle.left
        anchors.right: submit_rectangle.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 0
        anchors.rightMargin: 15
        anchors.bottomMargin: 25
        clip: true

        TextInput {
            id: input_prompt
            color: "#ffffff"
            selectedTextColor: "#EBE7DD"
            selectionColor: "#0068DF"
            text: mySubmitPrompt.userPromptText
            anchors.fill: parent
            anchors.leftMargin: 15
            anchors.rightMargin: 15
            anchors.topMargin: 15
            anchors.bottomMargin: 15
            font.pixelSize: 26
            wrapMode: Text.WordWrap
            activeFocusOnPress: true
            font.family: "Poppins"
            enabled: !isRecording && !isProcessing
                     && !mySubmitPrompt.isProcessingInference
                     && !mySubmitPrompt.isLoadingMedia
            opacity: enabled ? 1.0 : 0.3
            Keys.onReturnPressed: {
                mySubmitPrompt.setUserPromptText(input_prompt.text)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Submit Button
    // ═══════════════════════════════════════════════════════════════
    Rectangle {
        id: submit_rectangle
        x: 1601
        width: 200
        color: "transparent"
        anchors.right: parent.right
        anchors.top: output_llm_rectangle.bottom
        anchors.bottom: parent.bottom
        anchors.rightMargin: 15
        anchors.topMargin: 25
        anchors.bottomMargin: 25

        Button {
            id: submit_button
            text: qsTr("SUBMIT")
            anchors.fill: parent
            anchors.leftMargin: 0
            anchors.rightMargin: 0
            anchors.topMargin: 0
            anchors.bottomMargin: 0
            enabled: canSubmit() && !mySubmitPrompt.isProcessingInference
                     && !mySubmitPrompt.isLoadingMedia
            opacity: enabled ? 1.0 : 0.3
            visible: true
            icon.width: 200
            icon.height: 100
            icon.source: "../images/submit.svg"
            display: AbstractButton.IconOnly
            font.family: "Poppins"
            font.bold: true
            font.pointSize: 26
            onClicked: {
                console.log("[QML] submit_button clicked")
                console.log("[SUBMIT] Media:", loadedMediaPath)
                mySubmitPrompt.setUserPromptText(input_prompt.text)
            }
            background: Rectangle {
                color: submit_button.hovered ? accentSecondary : "transparent"
                radius: 10

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Output LLM Rectangle
    // ═══════════════════════════════════════════════════════════════
    Rectangle {
        id: output_llm_rectangle
        color: bgSecondary
        radius: 15
        border.color: borderInactive
        border.width: 2
        anchors.left: media_rectangle.right
        anchors.right: parent.right
        anchors.top: mainTitle.bottom
        anchors.bottom: input_prompt_rectangle.top
        anchors.leftMargin: 25
        anchors.rightMargin: 25
        anchors.topMargin: 0
        anchors.bottomMargin: 25

        // ═══════════════════════════════════════════════════════════
        // SCROLL VIEW - Output LLM Text (TOP SECTION)
        // ═══════════════════════════════════════════════════════════
        ScrollView {
            id: scrollView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: stats_rectangle.top
            anchors.leftMargin: 15
            anchors.rightMargin: 15
            anchors.topMargin: 15
            anchors.bottomMargin: 15
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            Text {
                id: output_llm_text
                width: scrollView.width - 30
                color: textPrimary
                text: mySubmitPrompt.modelResponseText
                font.pixelSize: 26
                wrapMode: Text.WordWrap
                textFormat: Text.MarkdownText
                font.family: "Poppins"
            }
        }

        // Cancel button (overlays on scroll view)
        Button {
            id: cancel_button
            width: 100
            height: 40
            enabled: mySubmitPrompt.isProcessingInference
            opacity: mySubmitPrompt.isProcessingInference ? 1.0 : 0.3
            visible: window.cancelSupport && mySubmitPrompt.isProcessingInference
            anchors.right: parent.right
            anchors.bottom: stats_rectangle.top
            anchors.rightMargin: 15
            anchors.bottomMargin: 20
            icon.height: 30
            icon.width: 90
            icon.source: down ? "images/cancel_pressed.png" : "images/cancel.png"
            display: AbstractButton.IconOnly
            z: 10

            background: Rectangle {
                color: "transparent"
            }

            onClicked: {
                console.log("[QML] cancel_button clicked")
                mySubmitPrompt.cancelInference()
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // Stats Rectangle - Dynamic Display Based on State
        // ═══════════════════════════════════════════════════════════════
        Rectangle {
            id: stats_rectangle
            height: 40
            color: bgTertiary
            radius: 5
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: rowModelSelector.top
            anchors.leftMargin: 15
            anchors.rightMargin: 15
            anchors.bottomMargin: 5

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 15
                spacing: 12

                // CURRENT MODE PILL (Only when model loaded and mode selected)
                Rectangle {
                    id: currentModePill
                    width: modeText.width + 32
                    height: 28
                    radius: 14

                    // Show when model loaded and analysis mode selected
                    visible: mySubmitPrompt.isModelLoaded
                             && window.analysisMode !== "none"

                    opacity: visible ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                        }
                    }

                    // Color based on analysis mode
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: window.analysisMode === "image" ? "#4CAF50" : "#2196F3" // Green for image, blue for video
                        }
                        GradientStop {
                            position: 1.0
                            color: window.analysisMode === "image" ? "#66BB6A" : "#42A5F5"
                        }
                    }

                    border.width: 2
                    border.color: "#FFFFFF"

                    // Pulse animation when processing
                    SequentialAnimation on border.width {
                        running: mySubmitPrompt.isProcessingInference
                                 && currentModePill.visible
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 2
                            to: 3
                            duration: 500
                        }
                        NumberAnimation {
                            from: 3
                            to: 2
                            duration: 500
                        }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            id: modeText
                            text: {
                                if (window.analysisMode === "image")
                                    return "Image Mode"
                                if (window.analysisMode === "video")
                                    return "Video Mode"
                                return "Ready"
                            }
                            font.pixelSize: 12
                            font.family: "Poppins"
                            font.bold: true
                            color: "#FFFFFF"
                        }
                    }
                }

                // Separator (only when mode pill is visible)
                Rectangle {
                    width: 2
                    height: 24
                    color: borderInactive
                    visible: currentModePill.visible
                    opacity: currentModePill.visible ? 1.0 : 0.0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                        }
                    }
                }

                // DYNAMIC TEXT - Changes based on state
                Text {
                    id: stats_text
                    text: {
                        // STATE 1: Model loading
                        if (mySubmitPrompt.shouldLoadModel) {
                            return "Loading model in progress..."
                        }
                        // STATE 2: Model not loaded - show description + capabilities
                        if (!mySubmitPrompt.isModelLoaded) {
                            if (mySubmitPrompt.selectedModelIndex >= 0) {
                                var desc = mySubmitPrompt.selectedModelDescription
                                var caps = []
                                if (mySubmitPrompt.modelSupportsImage) {
                                    caps.push("Image")
                                }
                                if (mySubmitPrompt.modelSupportsVideo) {
                                    caps.push("Video")
                                }
                                if (caps.length > 0) {
                                    return desc + " (Supports: " + caps.join(
                                                ", ") + ")"
                                } else {
                                    return desc + " (Text only)"
                                }
                            } else {
                                return "Select a model from the dropdown below"
                            }
                        }
                        // STATE 3: Model loaded - show stats or ready message
                        if (mySubmitPrompt.inferenceMetrics
                                && mySubmitPrompt.inferenceMetrics !== "") {
                            return mySubmitPrompt.inferenceMetrics
                        } else {
                            return ""
                        }
                    }
                    // Dynamic styling based on state
                    color: {
                        if (!mySubmitPrompt.isModelLoaded
                                || mySubmitPrompt.shouldLoadModel)
                            return textSecondary
                        return textPrimary
                    }

                    font.pixelSize: {
                        if (mySubmitPrompt.shouldLoadModel
                                || !mySubmitPrompt.isModelLoaded)
                            return 16
                        return 18
                    }

                    font.family: "Poppins"
                    font.italic: true
                    anchors.verticalCenter: parent.verticalCenter

                    // Calculate available width
                    width: {
                        var baseWidth = stats_rectangle.width - 60 // Account for margins
                        if (currentModePill.visible) {
                            return baseWidth - currentModePill.width
                                    - 14 // Account for pill + separator
                        }
                        return baseWidth
                    }

                    elide: Text.ElideRight

                    // Smooth transitions
                    Behavior on color {
                        ColorAnimation {
                            duration: 300
                        }
                    }

                    Behavior on font.pixelSize {
                        NumberAnimation {
                            duration: 200
                        }
                    }

                    // Fade transition when text changes
                    Behavior on text {
                        SequentialAnimation {
                            NumberAnimation {
                                target: stats_text
                                property: "opacity"
                                to: 0
                                duration: 150
                            }
                            PropertyAction {}
                            NumberAnimation {
                                target: stats_text
                                property: "opacity"
                                to: 1
                                duration: 150
                            }
                        }
                    }

                    // Tooltip for full text when truncated
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true

                        ToolTip.visible: containsMouse && stats_text.truncated
                        ToolTip.text: stats_text.text
                        ToolTip.delay: 500
                    }
                }
            }

            BusyIndicator {
                id: processing_llm_spinner
                x: -15
                width: 40
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.rightMargin: 5
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                visible: mySubmitPrompt.isProcessingInference
                running: mySubmitPrompt.isProcessingInference

                contentItem: Item {
                    implicitWidth: 40
                    implicitHeight: 40

                    Item {
                        id: ringRotator
                        anchors.centerIn: parent
                        width: 32
                        height: 32

                        // Multiple arcs to create ring effect
                        Repeater {
                            model: 3 // 3 segments for smooth ring

                            Item {
                                id: segment
                                anchors.fill: parent

                                required property int index

                                rotation: index * 120 // 120 degrees apart

                                Canvas {
                                    anchors.fill: parent

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)

                                        var centerX = width / 2
                                        var centerY = height / 2
                                        var radius = 13
                                        var startAngle = -Math.PI / 2
                                        var endAngle = startAngle
                                                + (Math.PI * 0.8) // 80% of 180 degrees

                                        // Gradient from transparent to white
                                        ctx.lineWidth = 4
                                        ctx.lineCap = "round"

                                        // Create gradient
                                        var gradient = ctx.createLinearGradient(
                                                    centerX - radius, centerY,
                                                    centerX + radius, centerY)
                                        gradient.addColorStop(0, "#00FFFFFF")
                                        gradient.addColorStop(0.5, "#80FFFFFF")
                                        gradient.addColorStop(1, "#FFFFFF")

                                        ctx.strokeStyle = gradient
                                        ctx.beginPath()
                                        ctx.arc(centerX, centerY, radius,
                                                startAngle, endAngle, false)
                                        ctx.stroke()
                                    }
                                }
                            }
                        }

                        // Rotation animation
                        RotationAnimator on rotation {
                            running: processing_llm_spinner.running
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                            easing.type: Easing.Linear
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        // MODEL SELECTOR ROW (Selectors on left, Buttons on right)
        // ═══════════════════════════════════════════════════════════
        Rectangle {
            id: rowModelSelector
            height: 50
            color: bgTertiary
            radius: 5
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: progressBarModel.top
            anchors.leftMargin: 15
            anchors.rightMargin: 15
            anchors.bottomMargin: 5

            // LEFT SIDE: Model and Endpoint Selectors
            Row {
                id: modelSelectorRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 15
                spacing: 10

                // Model Label
                Text {
                    id: modelLabel
                    text: "Model:"
                    color: "#ebe7dd"
                    font.pixelSize: 18
                    font.family: "Poppins"
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Model Selector
                ComboBox {
                    id: modelSelector
                    width: 200
                    height: 32

                    model: mySubmitPrompt.availableModelNames()
                    currentIndex: mySubmitPrompt.selectedModelIndex

                    enabled: !mySubmitPrompt.isProcessingInference
                             && analysisMode === "none"
                    opacity: enabled ? 1.0 : 0.5

                    font.pixelSize: 16
                    font.family: "Poppins"

                    Component.onCompleted: {
                        console.log("[QML] ModelSelector initialized")
                        console.log("[QML] Available models:",
                                    mySubmitPrompt.availableModelNames())
                        console.log("[QML] Current index:",
                                    mySubmitPrompt.selectedModelIndex)
                    }

                    onCurrentIndexChanged: {
                        console.log("[QML] Model selector currentIndex changed to:",
                                    currentIndex)
                        console.log("[QML] Backend currentModelIndex:",
                                    mySubmitPrompt.selectedModelIndex)

                        if (currentIndex !== mySubmitPrompt.selectedModelIndex) {
                            console.log("[QML] Model selector changed to index:",
                                        currentIndex)
                            mySubmitPrompt.setCurrentModelIndex(currentIndex)
                        }
                    }

                    Connections {
                        target: mySubmitPrompt

                        function onAvailableModelsChanged() {
                            console.log("[QML] availableModelsChanged signal received")
                            console.log("[QML] New models list:",
                                        mySubmitPrompt.availableModelNames())
                            modelSelector.model = mySubmitPrompt.availableModelNames()
                        }

                        function onSelectedModelIndexChanged() {
                            console.log("[QML] currentModelIndexChanged signal received")
                            console.log("[QML] New index:",
                                        mySubmitPrompt.selectedModelIndex)
                            modelSelector.currentIndex = mySubmitPrompt.selectedModelIndex
                        }
                    }

                    background: Rectangle {
                        color: modelSelector.enabled ? bgSecondary : bgTertiary
                        border.color: modelSelector.down ? accentPrimary : borderInactive
                        border.width: 1
                        radius: 4
                    }

                    contentItem: Text {
                        leftPadding: 10
                        text: modelSelector.displayText
                        font: modelSelector.font
                        color: modelSelector.enabled ? textPrimary : textSecondary
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    popup: Popup {
                        y: modelSelector.height
                        width: modelSelector.width
                        implicitHeight: contentItem.implicitHeight
                        padding: 1

                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: modelSelector.popup.visible ? modelSelector.delegateModel : null
                            currentIndex: modelSelector.highlightedIndex

                            ScrollIndicator.vertical: ScrollIndicator {}
                        }

                        background: Rectangle {
                            color: "#262626"
                            border.color: "#69ca00"
                            border.width: 1
                            radius: 4
                        }
                    }

                    delegate: ItemDelegate {
                        width: modelSelector.width
                        contentItem: Text {
                            text: modelData
                            color: "#ffffff"
                            font: modelSelector.font
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 10
                        }
                        highlighted: modelSelector.highlightedIndex === index

                        background: Rectangle {
                            color: highlighted ? "#0eafe0" : "transparent"
                            opacity: highlighted ? 0.3 : 1.0
                        }
                    }
                }

                // Endpoint Label
                Text {
                    id: endpointLabel
                    text: "Endpoint:"
                    color: "#ebe7dd"
                    font.pixelSize: 18
                    font.family: "Poppins"
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Endpoint Selector
                ComboBox {
                    id: endpointSelector
                    width: 120
                    height: 32
                    model: window.multiEndpoint ? ["USB", "PCIe0", "PCIe1", "All"] : ["PCIe0"]
                    currentIndex: window.multiEndpoint ? 1 : 0
                    enabled: !mySubmitPrompt.isProcessingInference
                    opacity: enabled ? 1.0 : 0.5
                    font.pixelSize: 16
                    font.family: "Poppins"

                    onCurrentIndexChanged: {
                        console.log("[QML] Endpoint changed to:", currentText)
                        mySubmitPrompt.setActiveEndpoint(currentText)
                    }

                    background: Rectangle {
                        color: endpointSelector.enabled ? bgSecondary : bgTertiary
                        border.color: endpointSelector.down ? accentPrimary : borderInactive
                        border.width: 1
                        radius: 4
                    }

                    contentItem: Text {
                        leftPadding: 10
                        text: endpointSelector.displayText
                        font: endpointSelector.font
                        color: endpointSelector.enabled ? textPrimary : textSecondary
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    popup: Popup {
                        y: endpointSelector.height
                        width: endpointSelector.width
                        implicitHeight: contentItem.implicitHeight
                        padding: 1

                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: endpointSelector.popup.visible ? endpointSelector.delegateModel : null
                            currentIndex: endpointSelector.highlightedIndex

                            ScrollIndicator.vertical: ScrollIndicator {}
                        }

                        background: Rectangle {
                            color: "#262626"
                            border.color: "#69ca00"
                            border.width: 1
                            radius: 4
                        }
                    }

                    delegate: ItemDelegate {
                        width: endpointSelector.width
                        contentItem: Text {
                            text: modelData
                            color: "#ffffff"
                            font: endpointSelector.font
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 10
                        }
                        highlighted: endpointSelector.highlightedIndex === index

                        background: Rectangle {
                            color: highlighted ? "#0eafe0" : "transparent"
                            opacity: highlighted ? 0.3 : 1.0
                        }
                    }
                }
            }

            // RIGHT SIDE: Load and Eject Buttons
            Row {
                id: modelButtonsRow
                spacing: 5
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 15

                Button {
                    id: loadModelButton
                    width: 80
                    height: 36
                    text: "Load"
                    font.pixelSize: 14
                    font.family: "Poppins"
                    font.bold: true
                    enabled: !mySubmitPrompt.isModelLoaded
                             && !mySubmitPrompt.shouldLoadModel
                    opacity: enabled ? 1.0 : 0.3

                    onClicked: {
                        console.log("[QML] Load button clicked")
                        progressBarModel.value = 0
                        resetTimer.start()
                    }

                    background: Rectangle {
                        color: loadModelButton.enabled
                               && loadModelButton.hovered ? accentSecondary : bgSecondary
                        radius: 5
                        border.color: loadModelButton.enabled ? accentSecondary : borderInactive
                        border.width: 2

                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }
                    }

                    contentItem: Text {
                        text: loadModelButton.text
                        font: loadModelButton.font
                        color: loadModelButton.enabled ? textPrimary : textSecondary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Button {
                    id: ejectModelButton
                    width: 80
                    height: 36
                    text: "Eject"
                    font.pixelSize: 14
                    font.family: "Poppins"
                    font.bold: true
                    enabled: mySubmitPrompt.isModelLoaded
                             && !mySubmitPrompt.isProcessingInference
                    opacity: enabled ? 1.0 : 0.3

                    onClicked: {
                        mySubmitPrompt.ejectModel()
                    }

                    background: Rectangle {
                        color: ejectModelButton.enabled
                               && ejectModelButton.hovered ? accentWarning : bgSecondary
                        radius: 5
                        border.color: ejectModelButton.enabled ? accentWarning : borderInactive
                        border.width: 2

                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }
                    }

                    contentItem: Text {
                        text: ejectModelButton.text
                        font: ejectModelButton.font
                        color: ejectModelButton.enabled ? textPrimary : textSecondary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        // MODEL LOADING PROGRESS BAR (Full width at bottom)
        // ═══════════════════════════════════════════════════════════
        ProgressBar {
            id: progressBarModel
            height: 30
            from: 0
            to: mySubmitPrompt.modelLoadingDuration
            value: 0
            visible: mySubmitPrompt.shouldLoadModel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 15
            anchors.rightMargin: 15
            anchors.bottomMargin: 15
            indeterminate: false
            property bool allowAnimation: true

            background: Rectangle {
                anchors.fill: progressBarModel
                color: bgTertiary
                radius: 10

                // Subtle inner border
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 9
                    color: "transparent"
                    border.width: 1
                    border.color: "#20FFFFFF"
                }
            }

            contentItem: Item {
                Rectangle {
                    id: mainProgress
                    height: parent.height
                    width: progressBarModel.width * (progressBarModel.value / progressBarModel.to)
                    radius: 10

                    // Bright blue gradient: cyan to deep blue
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: "#00D9FF"
                        } // Bright cyan
                        GradientStop {
                            position: 1.0
                            color: "#0A84FF"
                        } // Bright blue
                    }

                    // Transform origin set to left edge for proper pulse
                    transformOrigin: Item.Left

                    // Pulse animation from left edge
                    SequentialAnimation on scale {
                        running: progressBarModel.visible
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 1.0
                            to: 1.02
                            duration: 800
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            from: 1.02
                            to: 1.0
                            duration: 800
                            easing.type: Easing.InOutQuad
                        }
                    }

                    // Traveling light effect
                    Rectangle {
                        width: 60
                        height: parent.height
                        radius: 10

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0.0
                                color: "#00FFFFFF"
                            }
                            GradientStop {
                                position: 0.3
                                color: "#80FFFFFF"
                            }
                            GradientStop {
                                position: 0.7
                                color: "#80FFFFFF"
                            }
                            GradientStop {
                                position: 1.0
                                color: "#00FFFFFF"
                            }
                        }

                        SequentialAnimation on x {
                            running: progressBarModel.visible
                                     && mainProgress.width > 0
                            loops: Animation.Infinite
                            NumberAnimation {
                                from: 0
                                to: mainProgress.width
                                duration: 1500
                                easing.type: Easing.InOutQuad
                            }
                            PauseAnimation {
                                duration: 200
                            }
                        }
                    }
                }
            }

            // Conditional animation - only animate when completing
            Behavior on value {
                enabled: progressBarModel.allowAnimation
                NumberAnimation {
                    duration: 500
                    easing.type: Easing.OutQuad
                }
            }

            onVisibleChanged: {
                console.log("[QML] ProgressBar visible changed:", visible,
                            "current value:", value)
                if (visible) {
                    // When becoming visible, disable animation and reset to 0
                    allowAnimation = false
                    value = 0
                    allowAnimation = true
                } else if (!mySubmitPrompt.shouldLoadModel) {
                    allowAnimation = false
                    value = 0
                    allowAnimation = true
                }
            }
        }

        // Progress percentage text (overlays on progress bar)
        Text {
            id: progressBarTextModel
            height: 20
            visible: progressBarModel.visible
            text: Math.round(
                      progressBarModel.value / progressBarModel.to * 100.0) + "%"
            anchors.horizontalCenter: progressBarModel.horizontalCenter
            anchors.verticalCenter: progressBarModel.verticalCenter
            font.pixelSize: 14
            font.family: "Poppins"
            font.weight: Font.Bold
            color: progressBarModel.value > (progressBarModel.to * 0.5) ? "#000000" : textPrimary

            // Subtle pulse animation
            SequentialAnimation on opacity {
                running: progressBarModel.visible
                loops: Animation.Infinite
                NumberAnimation {
                    from: 0.7
                    to: 1.0
                    duration: 1000
                }
                NumberAnimation {
                    from: 1.0
                    to: 0.7
                    duration: 1000
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Control buttons
    // ═══════════════════════════════════════════════════════════════
    Rectangle {
        id: button_load_rectangle
        color: "#00ebe7dd"
        radius: 0
        border.color: "#00ffffff"
        anchors.left: parent.left
        anchors.right: media_rectangle.right
        anchors.top: media_rectangle.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 25
        anchors.rightMargin: 0
        anchors.topMargin: 25
        anchors.bottomMargin: 25

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            spacing: 1

            // LOAD BUTTON - Opens file dialog
            Button {
                id: load_button
                text: qsTr("Button")
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                enabled: mySubmitPrompt.isModelLoaded
                         && !mySubmitPrompt.isProcessingInference
                         && window.mediaSource !== "camera"
                opacity: enabled ? 1.0 : 0.3
                icon.height: 90
                icon.width: 90
                display: AbstractButton.IconOnly
                icon.source: down ? "images/load_pressed.svg" : "images/load_unpressed.svg"
                background: Rectangle {
                    color: "transparent"
                }
                onClicked: {
                    // Set file dialog filters based on model capabilities
                    var filters = []
                    if (!mySubmitPrompt.isModelLoaded) {
                        console.log("[Load] Model not loaded - blocking action")
                        return
                    }
                    if (mySubmitPrompt.modelSupportsImage) {
                        fileDialog.currentFolder = "file:///usr/share/vlm-edge-studio/assets/images"
                        filters.push("JPEG Images (*.jpeg *.jpg)")
                    }
                    if (mySubmitPrompt.modelSupportsVideo) {
                        fileDialog.currentFolder = "file:///usr/share/vlm-edge-studio/assets/videos"
                        filters.push("MP4 Videos (*.mp4)")
                    }
                    if (filters.length === 0) {
                        errorDialog.text = "Current model does not support image or video analysis."
                        errorDialog.open()
                        return
                    }
                    // Add "All supported files" option
                    if (filters.length > 1) {
                        filters.unshift(
                                    "All Supported Files (*.jpg *.jpeg *.mp4)")
                    }

                    fileDialog.nameFilters = filters
                    fileDialog.selectedNameFilter.index = 0
                    fileDialog.open()
                    console.log("[Load] Opening file dialog with filters:",
                                filters)
                }

                ToolTip {
                    id: loadTooltip
                    text: "⚠️ Load a model first"
                    delay: 500
                    timeout: 5000
                    visible: load_button.hovered && !mySubmitPrompt.isModelLoaded

                    // Position below button
                    y: load_button.height + 10

                    contentItem: Text {
                        text: loadTooltip.text
                        font.pixelSize: 14
                        font.family: "Poppins"
                        color: "#FFFFFF"
                        padding: 8
                    }

                    background: Rectangle {
                        color: "#2C2C2E"
                        border.color: accentWarning
                        border.width: 2
                        radius: 6
                    }

                    enter: Transition {
                        NumberAnimation {
                            property: "opacity"
                            from: 0.0
                            to: 1.0
                            duration: 200
                            easing.type: Easing.OutQuad
                        }
                    }

                    exit: Transition {
                        NumberAnimation {
                            property: "opacity"
                            from: 1.0
                            to: 0.0
                            duration: 150
                            easing.type: Easing.InQuad
                        }
                    }
                }
            }

            // IMAGE LOAD
            Button {
                id: image_button
                visible: true
                enabled: mySubmitPrompt.isModelLoaded
                         && !mySubmitPrompt.isProcessingInference
                         && window.analysisMode === "image"
                opacity: enabled ? 1.0 : 0.3
                icon.height: 90
                icon.width: 90
                icon.source: "images/image.svg"
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                display: AbstractButton.IconOnly
                background: Rectangle {
                    color: "transparent"
                }
                onClicked: {
                    console.log("[BUTTON] Image button clicked")
                    console.log("[BUTTON] Current mediaSource:", mediaSource)
                    console.log("[BUTTON] loadedMediaPath:", loadedMediaPath)

                    if (mediaSource === "camera") {
                        // Switch from camera → restore file mode
                        console.log("[BUTTON] Switching from camera to image file mode")
                        restoreImageFileMode()
                    } else if (mediaSource === "file") {
                        // Already in file mode → reload
                        if (loadedMediaPath !== "") {
                            console.log("[BUTTON] Reloading current image")
                            loadImageFile(loadedMediaPath)
                        } else {
                            console.log("[BUTTON] Opening file dialog")
                            fileDialog.nameFilters = ["JPEG Images (*.jpeg *.jpg)"]
                            fileDialog.selectedNameFilter.index = 0
                            fileDialog.open()
                        }
                    } else {
                        // No mode active → restore or open dialog
                        if (loadedMediaPath !== "") {
                            restoreImageFileMode()
                        } else {
                            fileDialog.nameFilters = ["JPEG Images (*.jpeg *.jpg)"]
                            fileDialog.selectedNameFilter.index = 0
                            fileDialog.open()
                        }
                    }
                }
            }

            // VIDEO LOAD
            Button {
                id: video_button
                visible: true
                enabled: mySubmitPrompt.isModelLoaded
                         && !mySubmitPrompt.isProcessingInference
                         && window.analysisMode === "video"
                opacity: enabled ? 1.0 : 0.3
                icon.height: 90
                icon.width: 90
                icon.source: "images/video.svg"
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                display: AbstractButton.IconOnly
                background: Rectangle {
                    color: "transparent"
                }

                onClicked: {
                    console.log("[BUTTON] Video button clicked")
                    console.log("[BUTTON] Current mediaSource:", mediaSource)
                    console.log("[BUTTON] loadedMediaPath:", loadedMediaPath)

                    if (mediaSource === "camera") {
                        // Switch from camera → restore file mode
                        console.log("[BUTTON] Switching from camera to video file mode")
                        restoreVideoFileMode()
                    } else if (mediaSource === "file") {
                        // Already in file mode → restart playback
                        if (loadedMediaPath !== "") {
                            console.log("[BUTTON] Already in video file mode")
                            if (!video_1.playing) {
                                console.log("[BUTTON] Restarting video playback")
                                video_1.startPipeline()
                            }
                        } else {
                            console.log("[BUTTON] Opening file dialog")
                            fileDialog.nameFilters = ["MP4 Videos (*.mp4)"]
                            fileDialog.selectedNameFilter.index = 0
                            fileDialog.open()
                        }
                    } else {
                        // No mode active → restore or open dialog
                        if (loadedMediaPath !== "") {
                            restoreVideoFileMode()
                        } else {
                            fileDialog.nameFilters = ["MP4 Videos (*.mp4)"]
                            fileDialog.selectedNameFilter.index = 0
                            fileDialog.open()
                        }
                    }
                }
            }

            // CAMERA BUTTON - Activates live camera
            Button {
                id: camera_button
                visible: true
                enabled: mySubmitPrompt.isModelLoaded
                         && !mySubmitPrompt.isProcessingInference
                         && (mySubmitPrompt.modelSupportsImage
                             || mySubmitPrompt.modelSupportsVideo)
                opacity: enabled ? 1.0 : 0.3
                icon.height: 90
                icon.width: 90
                icon.source: "images/camera.svg"
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                display: AbstractButton.IconOnly
                background: Rectangle {
                    color: mediaSource === "camera" ? "#80000000" : "transparent"
                    radius: 8
                }

                onClicked: {
                    console.log("[BUTTON] Camera button clicked")
                    console.log("[BUTTON] Current analysisMode:", analysisMode)
                    console.log("[BUTTON] Current loadedMediaPath:",
                                loadedMediaPath)

                    // Activate camera (loadedMediaPath preserved)
                    if (analysisMode === "video") {
                        activateCameraForVideo()
                    } else if (analysisMode === "image") {
                        activateCameraForImage()
                    } else {
                        console.warn("[BUTTON] No analysis mode set")
                    }
                }

                ToolTip {
                    id: cameraTooltip
                    text: "Activate Camera"
                    delay: 500
                    timeout: 5000
                    visible: enabled && camera_button.hovered
                             && mySubmitPrompt.isModelLoaded

                    // Position below button
                    y: camera_button.height + 10

                    contentItem: Text {
                        text: cameraTooltip.text
                        font.pixelSize: 14
                        font.family: "Poppins"
                        color: "#FFFFFF"
                        padding: 8
                    }

                    background: Rectangle {
                        color: "#2C2C2E"
                        border.color: "#0EAFE0"
                        border.width: 2
                        radius: 6
                    }

                    enter: Transition {
                        NumberAnimation {
                            property: "opacity"
                            from: 0.0
                            to: 1.0
                            duration: 200
                            easing.type: Easing.OutQuad
                        }
                    }

                    exit: Transition {
                        NumberAnimation {
                            property: "opacity"
                            from: 1.0
                            to: 0.0
                            duration: 150
                            easing.type: Easing.InQuad
                        }
                    }
                }
            }

            // CAPTURE BUTTON - Context-aware: records video OR captures frame
            Button {
                id: capture_button
                text: "Button"

                // Reuse existing flags - button disabled when any indicator is showing
                enabled: mySubmitPrompt.isModelLoaded
                         && window.mediaSource === "camera"
                         && video_1.cameraConnected
                         && !window.showRecordingIndicator
                         && !window.showProcessingIndicator

                opacity: enabled ? 1.0 : 0.3

                icon.height: 90
                icon.width: 90
                display: AbstractButton.IconOnly
                icon.source: down ? "images/capture_pressed.svg" : "images/capture_unpressed.svg"
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

                background: Rectangle {
                    color: "transparent"
                }

                onClicked: {
                    if (!video_1.playing)
                        return
                    console.log("[Capture] Button clicked, mode:", analysisMode)

                    // Record video
                    if (analysisMode === "video") {
                        progressBarImage.value = 0
                        window.showRecordingIndicator = true
                        recordingIndicatorTimer.restart()
                        video_1.startRecording()
                        console.log("[Capture] Started video recording")
                    } // Capture single frame
                    else if (analysisMode === "image") {
                        video_1.captureFrame()
                        console.log("[Capture] Captured single frame")
                    }
                }

                ToolTip {
                    id: captureTooltip
                    text: analysisMode === "video" ? "Record video" : "Capture current frame"
                    delay: 500
                    timeout: 5000
                    visible: enabled && capture_button.hovered
                             && mySubmitPrompt.isModelLoaded

                    // Position below button
                    y: capture_button.height + 10

                    contentItem: Text {
                        text: captureTooltip.text
                        font.pixelSize: 14
                        font.family: "Poppins"
                        color: "#FFFFFF"
                        padding: 8
                    }

                    background: Rectangle {
                        color: "#2C2C2E"
                        border.color: "#69CA00"
                        border.width: 2
                        radius: 6
                    }

                    enter: Transition {
                        NumberAnimation {
                            property: "opacity"
                            from: 0.0
                            to: 1.0
                            duration: 200
                            easing.type: Easing.OutQuad
                        }
                    }

                    exit: Transition {
                        NumberAnimation {
                            property: "opacity"
                            from: 1.0
                            to: 0.0
                            duration: 150
                            easing.type: Easing.InQuad
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: "Open file"

        // Helper function to detect file type
        function getFileType(filePath) {
            var extension = filePath.substring(filePath.lastIndexOf(
                                                   '.') + 1).toLowerCase()
            if (extension === "jpg" || extension === "jpeg")
                return "image"
            if (extension === "mp4")
                return "video"
            return "unknown"
        }

        onAccepted: {
            var path = selectedFile.toString()
            path = path.replace(/^(file:\/{2})/, "")
            var fileType = getFileType(path)

            console.log("[FileDialog] File selected:", path, "Type:", fileType)

            if (fileType === "image") {
                progressBarImage.value = 0
                mySubmitPrompt.isLoadingMedia = true
                loadImageFile(path)
                loadVideoTimer.start()
            } else if (fileType === "video") {
                progressBarImage.value = 0
                mySubmitPrompt.isLoadingMedia = true
                loadVideoFile(path)
                loadVideoTimer.start()
            } else {
                console.warn("[FileDialog] Unsupported file type")
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    /// Media Rectangle
    // ═══════════════════════════════════════════════════════════════
    Rectangle {
        id: media_rectangle
        width: 795
        color: "transparent"
        border.color: borderInactive
        anchors.left: parent.left
        anchors.top: mainTitle.bottom
        anchors.bottom: output_llm_rectangle.bottom
        anchors.leftMargin: 25
        anchors.topMargin: 0
        anchors.bottomMargin: 0

        // Image display (for image mode or captured frames)
        Image {
            id: imageDisplay
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            visible: analysisMode === "image" && mediaSource === "file"
            source: {
                if (analysisMode === "image" && mediaSource === "file"
                        && loadedMediaPath !== "") {
                    // Format for QML Image component
                    var path = loadedMediaPath
                    if (!path.startsWith("file://")) {
                        return "file://" + path
                    }
                    return path
                }
                return ""
            }

            asynchronous: true
            smooth: true
            cache: true

            // Loading indicator
            BusyIndicator {
                anchors.centerIn: parent
                running: imageDisplay.status === Image.Loading
                visible: running
                width: 64
                height: 64
                contentItem: Item {
                    implicitWidth: 64
                    implicitHeight: 64

                    Item {
                        id: imageLoadingSpinner
                        x: parent.width / 2 - 32
                        y: parent.height / 2 - 32
                        width: 64
                        height: 64

                        RotationAnimator {
                            target: imageLoadingSpinner
                            running: imageDisplay.status === Image.Loading
                            from: 0
                            to: 360
                            loops: Animation.Infinite
                            duration: 1500
                        }

                        Repeater {
                            model: 8

                            Rectangle {
                                id: loadingDot
                                x: imageLoadingSpinner.width / 2 - width / 2
                                y: imageLoadingSpinner.height / 2 - height / 2
                                implicitWidth: 6
                                implicitHeight: 6
                                radius: 3
                                color: "#0eafe0"

                                required property int index

                                transform: [
                                    Translate {
                                        y: -20
                                    },
                                    Rotation {
                                        angle: loadingDot.index * 45
                                        origin.x: 3
                                        origin.y: 20
                                    }
                                ]

                                opacity: 0.3 + (0.7 * ((loadingDot.index + 1) / 8))
                            }
                        }
                    }
                }
            }

            // Error message
            Text {
                anchors.centerIn: parent
                text: "Failed to load image"
                color: "#FF0000"
                font.pixelSize: 20
                font.family: "Poppins"
                visible: imageDisplay.status === Image.Error
            }

            onStatusChanged: {
                if (status === Image.Ready) {
                    console.log("[Image] Loaded successfully:", source)
                } else if (status === Image.Error) {
                    console.log("[Image] Failed to load:", source)
                }
            }
        }

        // Video/Camera display for video and camera modes
        GstTestGLSink {
            id: video_1
            anchors.fill: parent
            anchors.centerIn: parent
            patternType: 0
            animate: true
            visible: analysisMode === "video" || mediaSource === "camera"
        }

        // Video Play Button (only visible in video mode)
        Button {
            id: playButton
            width: 50
            height: 50
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 15
            anchors.bottomMargin: 15
            visible: analysisMode === "video" && mediaSource === "file"
            opacity: enabled ? 0.7 : 0
            z: 10

            // Smooth show/hide animation
            Behavior on opacity {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.InOutQuad
                }
            }

            background: Rectangle {
                anchors.fill: parent
                radius: 8
                color: "#80808080"
                border.color: "#A0A0A0"
                border.width: 1

                // Subtle inner highlight
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 7
                    color: "transparent"
                    border.color: "#60FFFFFF"
                    border.width: 1
                }
            }

            // Play icon
            Text {
                anchors.centerIn: parent
                text: "▶"
                color: "#FFFFFF"
                font.pixelSize: 20
                font.family: "Poppins"
                font.bold: true
                anchors.horizontalCenterOffset: 1
            }

            onClicked: {
                console.log("[QML] Discrete play button clicked - starting video pipeline")
                video_1.startPipeline()
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: parent.clicked()

                onEntered: {
                    parent.opacity = 0.9
                }
                onExited: {
                    parent.opacity = 0.7
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutQuad
                }
            }
        }

        ProgressBar {
            id: progressBarImage
            from: 0
            to: 750 // Aprox. time to process image embeddings
            value: 0
            height: 10
            visible: mySubmitPrompt.isLoadingMedia
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 0
            anchors.rightMargin: 0
            anchors.bottomMargin: 0
            background: Rectangle {
                anchors.fill: progressBarImage
                color: "#262626"
                radius: 4
                border.width: 1
                border.color: "#262626"
            }
            contentItem: Rectangle {
                height: progressBarImage.height
                width: progressBarImage.width * (progressBarImage.value / progressBarImage.to)
                color: progressBarImage.value === 0.0 ? "#262626" : "#69CA00"
                radius: 4
            }
            onVisibleChanged: {
                progressBarImage.value = 0
            }
        }

        Text {
            id: progressBarTextImage
            x: 0
            y: 785
            width: 795
            height: 10
            visible: progressBarImage.visible
            text: Math.round(
                      progressBarImage.value / progressBarImage.to * 100.0) + qsTr(
                      "%")
            font.pixelSize: 10
            color: progressBarImage.value < (progressBarImage.to / 2) ? "#FFFFFF" : "#000000"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: "Poppins"
        }
    }
}
