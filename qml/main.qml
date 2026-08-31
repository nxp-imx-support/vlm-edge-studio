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
import QtQuick
import QtQuick.Controls
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
    color: theme.bgPrimary

    // ═══════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════
    readonly property bool cancelSupport: false
    readonly property bool configSupport: true
    readonly property string defaultImagePath: "/usr/share/vlm-edge-studio/assets/images/image.jpg"
    readonly property string defaultVideoPath: "/usr/share/vlm-edge-studio/assets/videos/video.mp4"
    property bool isProgressBarCompleting: false

    // ═══════════════════════════════════════════════════════════════
    // COLOR SCHEME - Minimal Dark Pro
    // ═══════════════════════════════════════════════════════════════
    QtObject {
        id: theme
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
        readonly property color borderPopup: "#48484A"

        // UI Dimensions
        readonly property int brandingHeight: 10
        readonly property int titleHeight: 125
        readonly property int inputHeight: 100
        readonly property int submitWidth: 200
        readonly property int statsHeight: 40
        readonly property int selectorHeight: 50
        readonly property int standardMargin: 15
        readonly property int bottomMargin: 25
        readonly property int standardRadius: 15
        readonly property int smallRadius: 5
        readonly property int borderWidth: 2
        readonly property int contentRow: 820 // 1080 - brandingHeight - titleHeight - inputHeight - bottomMargin

        // Font sizes
        readonly property int fontLarge: 26
        readonly property int fontMedium: 22
        readonly property int fontSmall: 18
        readonly property int fontTiny: 16
        readonly property int fontMicro: 14
        readonly property int fontProgress: 12

        // Animation durations
        readonly property int animationFast: 200
        readonly property int animationMedium: 500
        readonly property int animationSlow: 800
        readonly property int animationPulse: 1000
        readonly property int animationShimmer: 1500
    }

    // ═══════════════════════════════════════════════════════════════
    // STATE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════
    // Analysis mode (driven by loaded model)
    property string analysisMode: "none" // "none", "image", "video"
    // Media input source
    property string mediaSource: "none" // "none", "file", "camera"
    // Last loaded media
    property string loadedMediaPath: ""
    // Per-mode remembered paths so image<->video switching reloads the correct file
    property string lastImagePath: ""
    property string lastVideoPath: ""

    // Processing state
    property bool isRecording: false
    property bool isProcessing: false
    property bool showRecordingIndicator: false
    property bool showProcessingIndicator: false

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
        lastImagePath = backendPath
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
        lastVideoPath = backendPath
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

    // Function to check if download dialog should be shown
    function checkAndShowDownloadDialog() {
        if (!mySubmitPrompt) {
            return
        }
        var modelsCount = mySubmitPrompt.availableModelNames().length
        var isLoading = mySubmitPrompt.modelsLoading
        var isDownloading = mySubmitPrompt.isDownloadingModels
        if (modelsCount === 0 && !isLoading && !isDownloading) {
            console.log("[Main.qml] No models found, opening download dialog")
            modelDownloadDialog.open()
        }
    }

    // Check on completion if we should show download dialog
    Component.onCompleted: {
        checkAndShowDownloadDialog()
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
        // Determine which path to use. Use the per-mode image path so a
        // switch from video mode does not try to load an .mp4 as an image.
        var pathToLoad = ""

        if (lastImagePath !== "") {
            // Use last known image path (from previous load or capture)
            pathToLoad = lastImagePath
            console.log("[STATE] Using stored lastImagePath:", pathToLoad)
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

        // Determine which path to use. Use the per-mode video path so a
        // switch from image mode does not try to load a .jpg as a video.
        var pathToLoad = ""

        if (lastVideoPath !== "") {
            // Use last known video path (from previous load or record)
            pathToLoad = lastVideoPath
            console.log("[STATE] Using stored lastVideoPath:", pathToLoad)
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
                window.isProgressBarCompleting = true
                progressBarModel.allowAnimation = true
                progressBarModel.value = 100 //progressBarModel.to
                console.log("[Progress] Model loaded, animating to 100% then fading out")
                progressCompleteTimer.start()

                // Set analysis mode
                if (mySubmitPrompt.modelSupportsImage) {
                    window.analysisMode = "image"
                } else if (mySubmitPrompt.modelSupportsVideo) {
                    window.analysisMode = "video"
                } else {
                    window.analysisMode = "none"
                }
                loadDefaultMedia()
            } else {
                // Model unloaded → reset bar immediately
                progressCompleteTimer.stop()
                window.isProgressBarCompleting = false
                progressBarModel.allowAnimation = false
                progressBarModel.value = 0

                // Model unloaded - reset
                window.analysisMode = "none"
                window.mediaSource = "none"
                window.loadedMediaPath = ""
                console.log("[MODEL] Model unloaded, reset analysis mode")
            }
        }

        function onAvailableModelsChanged() {
            console.log("[QML] Available models changed, count:",
                       mySubmitPrompt.availableModelNames().length)
            // Auto-open dialog if no models and not already downloading
            if (mySubmitPrompt.availableModelNames().length === 0 &&
                !mySubmitPrompt.modelsLoading &&
                !mySubmitPrompt.isDownloadingModels) {
                console.log("[QML] No models found, opening download dialog")
                modelDownloadDialog.open()
            }
        }

        function onModelsLoadingErrorChanged() {
            console.log("[QML] Models loading error:",
                       mySubmitPrompt.modelsLoadingError)
            // Also check when there's an error loading models
            if (mySubmitPrompt.modelsLoadingError !== "" &&
                mySubmitPrompt.availableModelNames().length === 0) {
                console.log("[QML] Models loading failed, opening download dialog")
                modelDownloadDialog.open()
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

    readonly property var modelLoadTimesMs: {
        "qwen2.5-vl-7b-instruct": 420000,   // 7 min
        "qwen2_5-vl-3b":          240000,   // 4 min
        "qwen2.5-image-3b":       120000    // 2 min
    }

    property int expectedLoadTimeMs: {
        var models = mySubmitPrompt.availableModelNames()
        if (models.length === 0 || mySubmitPrompt.selectedModelIndex < 0)
            return 300000

        var name = models[mySubmitPrompt.selectedModelIndex].toLowerCase()

        for (var key in modelLoadTimesMs) {
            if (name.indexOf(key) !== -1)
                return modelLoadTimesMs[key]
        }

        return 300000
    }

    // ═══════════════════════════════════════════════════════════════
    // UI INDICATORS
    // ═══════════════════════════════════════════════════════════════

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
    // DIALOGS
    // ═══════════════════════════════════════════════════════════════
    AboutDialog {
        id: aboutDialog
    }

    ModelDownloadDialog {
        id: modelDownloadDialog
        submitPrompt: mySubmitPrompt
        anchors.centerIn: parent
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
            if (progressBarModel.value < 95) {
                // increment = 95 / (expectedLoadTimeMs / interval)
                var totalTicks = window.expectedLoadTimeMs / interval
                var increment  = 95.0 / totalTicks
                progressBarModel.value = Math.min(
                    progressBarModel.value + increment, 95)
            }
        }

        onRunningChanged: {
            if (running) {
                // Reset to 0 when loading starts
                progressBarModel.allowAnimation = false
                progressBarModel.value = 0
            } 
        }
    }

    Timer {
        id: progressCompleteTimer
        interval: 800  // animationMedium (500ms) + 300ms buffer for fade
        repeat: false
        onTriggered: {
            window.isProgressBarCompleting = false
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
    // MAIN LAYOUT
    // ═══════════════════════════════════════════════════════════════
    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        spacing: 0

        // ───────────────────────────────────────────────────────────
        // ROW 1: NXP Branding Bar
        // ───────────────────────────────────────────────────────────
        Rectangle {
            id: brandingBar
            Layout.fillWidth: true
            Layout.preferredHeight: theme.brandingHeight
	        Layout.maximumHeight: 15

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.1;  color: "#F9B500" }
                GradientStop { position: 0.45; color: "#69CA00" }
                GradientStop { position: 0.55; color: "#69CA00" }
                GradientStop { position: 0.9;  color: "#0EAFE0" }
            }
        }

        // ───────────────────────────────────────────────────────────
        // ROW 2: Title Bar
        // ───────────────────────────────────────────────────────────
        RowLayout {
            id: titleBar
            Layout.fillWidth: true
            Layout.preferredHeight: theme.titleHeight
            Layout.maximumHeight: theme.titleHeight
	        Layout.minimumHeight:   theme.titleHeight
            Layout.rightMargin: theme.standardMargin
            Layout.leftMargin: 5
            spacing: theme.standardMargin

            Image {
                id: titleImage
                Layout.fillWidth: true
                Layout.fillHeight: true
                horizontalAlignment: Image.AlignLeft
                source: "../images/title.png"
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 3096
            }

            // Right-side buttons
            RowLayout {
                id: rightButtonsRow
                Layout.alignment: Qt.AlignVCenter
                spacing: theme.standardMargin

                Button {
                    id: aboutButton
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 50
                    text: "About"
                    font.pixelSize: theme.fontMedium
                    font.family: "Poppins"
                    font.bold: true
                    onClicked: aboutDialog.visible = true

                    background: Rectangle {
                        color: aboutButton.hovered ? theme.borderInactive : theme.bgSecondary
                        radius: theme.smallRadius
                        border.color: theme.textSecondary
                        border.width: theme.borderWidth
                        Behavior on color {
                            ColorAnimation { duration: theme.animationFast }
                        }
                    }

                    contentItem: Text {
                        text: aboutButton.text
                        font: aboutButton.font
                        color: theme.textPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Button {
                    id: closeButton
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 50
                    text: "Close"
                    font.pixelSize: theme.fontMedium
                    font.family: "Poppins"
                    font.bold: true
                    onClicked: {
                        mySubmitPrompt.killConnectorProcess()
                        Qt.quit()
                    }

                    background: Rectangle {
                        color: closeButton.hovered ? theme.borderInactive : theme.bgSecondary
                        radius: theme.smallRadius
                        border.color: theme.textSecondary
                        border.width: theme.borderWidth
                        Behavior on color {
                            ColorAnimation { duration: theme.animationFast }
                        }
                    }

                    contentItem: Text {
                        text: closeButton.text
                        font: closeButton.font
                        color: theme.textPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        // ───────────────────────────────────────────────────────────
        // ROW 3: Media & Output Area
        // ───────────────────────────────────────────────────────────
        RowLayout {
	        id: contentRow
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: theme.contentRow
	        Layout.leftMargin: theme.standardMargin
	        Layout.rightMargin: theme.standardMargin
            Layout.bottomMargin: theme.bottomMargin
	        spacing: theme.standardMargin

            // ── LEFT: Media Area ────────────────────────────────────
            Rectangle {
                id: mediaArea
                Layout.fillHeight: theme.contentRow
                Layout.preferredWidth: parent.width * 0.42
                color: theme.bgSecondary
                radius: theme.standardRadius
                border.color: theme.borderInactive
                border.width: theme.borderWidth
                clip: true
                layer.enabled: true

                // Image display (for image mode or captured frames)
                Image {
                    id: imageDisplay
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    z: 2

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

                // Red "REC" during frame capture
                Rectangle {
                    id: recordingIndicator
                    width: 120
                    height: 40
                    color: "#80000000"
                    radius: 8
                    anchors.top: mediaArea.top
                    anchors.right: mediaArea.right
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

                // "Processing video..." during encoding
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
            }
        
            // ── RIGHT: Output Area ──────────────────────────────────
            Rectangle {
                id: outputArea
                Layout.fillWidth: true
                Layout.fillHeight: theme.contentRow
                color: theme.bgSecondary
                radius: theme.standardRadius
                border.color: theme.borderInactive
                border.width: theme.borderWidth

                ColumnLayout {
                    id: outputLayout
                    anchors.fill: parent
                    anchors.margins: theme.standardMargin
                    spacing: 5

                    // ── Scrollable Output Text ──────────────────────
                    ScrollView {
                        id: scrollView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        Flickable {
                            id: flickable
                            contentWidth: scrollView.availableWidth
                            contentHeight: outputText.contentHeight
                                           + theme.standardMargin * 2
                            boundsBehavior: Flickable.StopAtBounds

                            Text {
                                id: outputText
                                x: theme.standardMargin
                                y: theme.standardMargin
                                width: flickable.contentWidth
                                       - theme.standardMargin * 2
                                color: theme.textPrimary
                                text: mySubmitPrompt.modelResponseText
                                font.pixelSize: theme.fontLarge
                                font.family: "Poppins"
                                wrapMode: Text.WordWrap
                                textFormat: Text.MarkdownText
                                onTextChanged: scrollToBottom.restart()
                            }
                        }

                        Timer {
                            id: scrollToBottom
                            interval: 50
                            onTriggered: {
                                if (flickable.contentHeight > flickable.height)
                                    flickable.contentY = flickable.contentHeight
                                                         - flickable.height
                            }
                        }
                    }

                    // ── Stats Bar ───────────────────────────────────
                    Rectangle {
                        id: statsBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: theme.statsHeight
                        color: theme.bgTertiary
                        radius: theme.smallRadius

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: theme.standardMargin
                            anchors.rightMargin: 5
                            spacing: 5

                            // MODE SELECTOR - Segmented Image/Video toggle
                            Rectangle {
                                id: currentModePill
                                width: modeSegments.implicitWidth + 8
                                height: 28
                                radius: 14
                                color: theme.bgSecondary
                                border.width: 1
                                border.color: theme.borderInactive

                                // Both modes available on the loaded model
                                property bool dualMode: mySubmitPrompt.modelSupportsImage
                                                        && mySubmitPrompt.modelSupportsVideo
                                // Reacts to clicks only when a model is loaded and idle
                                property bool interactive: mySubmitPrompt.isModelLoaded
                                                           && !mySubmitPrompt.isProcessingInference

                                // Show when model loaded and analysis mode selected
                                visible: mySubmitPrompt.isModelLoaded
                                        && window.analysisMode !== "none"

                                opacity: visible ? (interactive ? 1.0 : 0.5) : 0.0
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 300
                                    }
                                }

                                Row {
                                    id: modeSegments
                                    anchors.centerIn: parent
                                    spacing: 0

                                    // IMAGE segment
                                    Rectangle {
                                        id: imageSegment
                                        visible: mySubmitPrompt.modelSupportsImage
                                        width: imageRow.implicitWidth + 20
                                        height: 24
                                        radius: 12
                                        color: window.analysisMode === "image" ? "#4CAF50" : "transparent"
                                        Behavior on color { ColorAnimation { duration: theme.animationFast } }

                                        Row {
                                            id: imageRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Image {
                                                width: 14; height: 14
                                                anchors.verticalCenter: parent.verticalCenter
                                                source: "images/image.svg"
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                antialiasing: true
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Image"
                                                color: window.analysisMode === "image" ? "#FFFFFF" : theme.textSecondary
                                                font.pixelSize: 12
                                                font.family: "Poppins"
                                                font.bold: window.analysisMode === "image"
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: currentModePill.interactive
                                                     && mySubmitPrompt.modelSupportsImage
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                console.log("[MODE] Image segment clicked")
                                                if (window.analysisMode !== "image") {
                                                    console.log("[MODE] Switching to image mode")
                                                    // Clear GUI output on every image<->video switch
                                                    mySubmitPrompt.clearOutputDisplay()
                                                    restoreImageFileMode()
                                                } else if (mediaSource === "camera") {
                                                    restoreImageFileMode()
                                                }
                                            }
                                            ToolTip.visible: containsMouse && currentModePill.dualMode
                                            ToolTip.text: "Switch to Image mode"
                                            ToolTip.delay: 500
                                        }
                                    }

                                    // VIDEO segment
                                    Rectangle {
                                        id: videoSegment
                                        visible: mySubmitPrompt.modelSupportsVideo
                                        width: videoRow.implicitWidth + 20
                                        height: 24
                                        radius: 12
                                        color: window.analysisMode === "video" ? "#2196F3" : "transparent"
                                        Behavior on color { ColorAnimation { duration: theme.animationFast } }

                                        Row {
                                            id: videoRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Image {
                                                width: 14; height: 14
                                                anchors.verticalCenter: parent.verticalCenter
                                                source: "images/video.svg"
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                antialiasing: true
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Video"
                                                color: window.analysisMode === "video" ? "#FFFFFF" : theme.textSecondary
                                                font.pixelSize: 12
                                                font.family: "Poppins"
                                                font.bold: window.analysisMode === "video"
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: currentModePill.interactive
                                                     && mySubmitPrompt.modelSupportsVideo
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                console.log("[MODE] Video segment clicked")
                                                if (window.analysisMode !== "video") {
                                                    console.log("[MODE] Switching to video mode")
                                                    // Clear GUI output on every image<->video switch
                                                    mySubmitPrompt.clearOutputDisplay()
                                                    restoreVideoFileMode()
                                                } else if (mediaSource === "camera") {
                                                    restoreVideoFileMode()
                                                }
                                            }
                                            ToolTip.visible: containsMouse && currentModePill.dualMode
                                            ToolTip.text: "Switch to Video mode"
                                            ToolTip.delay: 500
                                        }
                                    }
                                }
                            }

                            // Separator (only when mode selector is visible)
                            Rectangle {
                                width: 2
                                height: 24
                                color: theme.borderInactive
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
                                        return theme.textSecondary
                                    return theme.textPrimary
                                }

                                font.pixelSize: {
                                    if (mySubmitPrompt.shouldLoadModel
                                            || !mySubmitPrompt.isModelLoaded)
                                        return 16
                                    return 18
                                }

                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                font.family: "Poppins"
                                font.italic: true

                                // Calculate available width
                                width: {
                                    var baseWidth = statsBar.width - 60 // Account for margins
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

                    // ── Model Selector Bar ──────────────────────
                    Rectangle {
                        id: modelSelectorBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: theme.selectorHeight
                        color: theme.bgTertiary
                        radius: theme.smallRadius

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: theme.standardMargin
                            anchors.rightMargin: theme.standardMargin
                            spacing: 10

                            // Model label + selector
                            Text {
                                text: "Model:"
                                color: theme.textSecondary
                                font.pixelSize: theme.fontSmall
                                font.family: "Poppins"
                                font.bold: true
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledComboBox {
                                id: modelSelector
                                Layout.preferredWidth: 200
                                Layout.preferredHeight: 32
                                Layout.alignment: Qt.AlignVCenter
                                model: mySubmitPrompt.availableModelNames()
                                currentIndex: mySubmitPrompt.selectedModelIndex
                                enabled: !mySubmitPrompt.isModelLoaded
                                         && !mySubmitPrompt.isProcessingInference
                                         && !mySubmitPrompt.shouldLoadModel
                                         && mySubmitPrompt.selectedModelIndex >= 0

                                onCurrentIndexChanged: {
                                    console.log("[QML] Model selector currentIndex changed to:",
                                                currentIndex)
                                    console.log("[QML] Backend selectedModelIndex:",
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
                                        console.log("[QML] selectedModelIndexChanged signal received")
                                        console.log("[QML] New index:",
                                                    mySubmitPrompt.selectedModelIndex)
                                        modelSelector.currentIndex = mySubmitPrompt.selectedModelIndex
                                    }
                                }
                            }

                            // Endpoint label + selector
                            Text {
                                text: "Endpoint:"
                                color: theme.textSecondary
                                font.pixelSize: theme.fontSmall
                                font.family: "Poppins"
                                font.bold: true
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledComboBox {
                                id: endpointSelector
                                Layout.preferredWidth: 200
                                Layout.preferredHeight: 32
                                Layout.alignment: Qt.AlignVCenter
                                model: mySubmitPrompt.endpointNames
                                currentIndex: 0
                                enabled: !mySubmitPrompt.isModelLoaded
                                         && !mySubmitPrompt.shouldLoadModel
                                         && !mySubmitPrompt.isProcessingInference
                                onActivated: function(index) {
                                    console.log("[QML] Endpoint selector changed to index:", index, currentText) 
                                    mySubmitPrompt.initializeEndpoint(index, currentText)
                                }
                            }

                            // Spacer pushes buttons to right
                            Item { Layout.fillWidth: true }

                            // Action buttons
                            ActionButton {
                                id: loadButton
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 36
                                Layout.alignment: Qt.AlignVCenter
                                text: "Load"
                                accentColor: theme.accentSecondary
                                enabled: !mySubmitPrompt.isModelLoaded
                                         && !mySubmitPrompt.shouldLoadModel
                                         && mySubmitPrompt.selectedModelIndex >= 0
                                onClicked: {
                                    progressBarModel.value = 0
                                    mySubmitPrompt.setLoadModel(true)
                                }
                            }

                            ActionButton {
                                id: ejectButton
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 36
                                Layout.alignment: Qt.AlignVCenter
                                text: "Eject"
                                accentColor: theme.accentWarning
                                enabled: mySubmitPrompt.isModelLoaded
                                         && !mySubmitPrompt.isProcessingInference
                                onClicked: mySubmitPrompt.ejectModel()
                            }

                            Button {
                                id: gearButton
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                Layout.alignment: Qt.AlignVCenter
                                visible: configSupport
                                enabled: !mySubmitPrompt.isProcessingInference
                                opacity: enabled ? 1.0 : 0.3
                                hoverEnabled: true
                                onClicked: modelConfigPopup.open()

                                background: Rectangle {
                                    color: gearButton.hovered ? theme.bgTertiary : "transparent"
                                    radius: theme.smallRadius
                                    border.color: gearButton.hovered
                                                  ? theme.accentPrimary
                                                  : theme.borderInactive
                                    border.width: theme.borderWidth
                                    Behavior on color      { ColorAnimation { duration: theme.animationFast } }
                                    Behavior on border.color { ColorAnimation { duration: theme.animationFast } }
                                }

                                contentItem: Text {
                                    text: "⚙"
                                    font.pixelSize: 20
                                    color: gearButton.hovered
                                           ? theme.accentPrimary
                                           : theme.textSecondary
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    Behavior on color { ColorAnimation { duration: theme.animationFast } }

                                    RotationAnimation on rotation {
                                        running: gearButton.hovered
                                        from: 0; to: 360
                                        duration: 1500
                                        loops: Animation.Infinite
                                    }
                                }

                                ToolTip {
                                    visible: gearButton.hovered
                                    text: "Model loading configuration"
                                    delay: 500
                                    font.pixelSize: theme.fontMicro
                                    font.family: "Poppins"
                                }
                            }
                        }
                    }

                    // ── Progress Bar ────────────────────────────
                    // Visible:false collapses height, use height:0 + clip instead

                    Item {
                        id: progressContainer
                        Layout.fillWidth: true
                        Layout.preferredHeight: (mySubmitPrompt.shouldLoadModel
                                                ||  window.isProgressBarCompleting) ? 15 : 0
                        clip: true   // hides bar content when height = 0

                        Behavior on Layout.preferredHeight {
                            NumberAnimation {
                                duration: theme.animationFast
                                easing.type: Easing.OutQuad
                            }
                        }

                        AnimatedProgressBar {
                            id: progressBarModel
                            anchors.fill: parent
                            visible: mySubmitPrompt.shouldLoadModel
                            from: 0
                            to: 100
                            value: 0
                            property bool allowAnimation: false // disable by default to prevent initial animation

                            opacity: window.isProgressBarCompleting
                                    && !mySubmitPrompt.shouldLoadModel ? 0 : 1
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 500
                                    easing.type: Easing.InQuad
                                }
                            }

                            onVisibleChanged: {
                                if (visible && mySubmitPrompt.shouldLoadModel) {
                                    allowAnimation = false
                                    value = 0
                                }
                            }

                            Text {
                                id: progressText
                                anchors.centerIn: parent
                                visible: progressBarModel.visible
                                text: Math.round(
                                    progressBarModel.value
                                    / progressBarModel.to * 100.0) + "%"
                                font.pixelSize: theme.fontProgress
                                font.family: "Poppins"
                                font.weight: Font.Medium
                                color: theme.textPrimary

                                SequentialAnimation on opacity {
                                    running: progressBarModel.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.7; to: 1.0; duration: theme.animationPulse }
                                    NumberAnimation { from: 1.0; to: 0.7; duration: theme.animationPulse }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // Row 4: Input Area
        // ═══════════════════════════════════════════════════════════════
        RowLayout {
            id: inputRow
	        Layout.fillWidth: true
            Layout.preferredHeight: theme.inputHeight
	        Layout.maximumHeight:   theme.inputHeight
            Layout.minimumHeight:   theme.inputHeight
            Layout.leftMargin: theme.standardMargin
            Layout.rightMargin: theme.standardMargin
            Layout.bottomMargin: theme.bottomMargin
            spacing: theme.standardMargin

            // Control buttons
            Rectangle {
                id: mediaControllerBar
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.42
                color: theme.bgPrimary

                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.leftMargin:  theme.standardMargin
                    anchors.rightMargin: theme.standardMargin

                    // LOAD BUTTON - Opens file dialog
                    Button {
                        id: load_button
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        display: AbstractButton.IconOnly
                        enabled: mySubmitPrompt.isModelLoaded
                                && !mySubmitPrompt.isProcessingInference
                                && window.mediaSource !== "camera"
                        opacity: enabled ? 1.0 : 0.3
                        background: Rectangle { color: "transparent" }
                        contentItem: Image {
                            anchors.centerIn: parent
                            width: parent.width * 0.72
                            height: parent.width * 0.72
                            source: load_button.down ? "images/load_pressed.svg" : "images/load_unpressed.svg"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            antialiasing: true
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
                                border.color: theme.accentWarning
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

                    // CAMERA BUTTON - Activates live camera
                    Button {
                        id: camera_button
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        display: AbstractButton.IconOnly
                        enabled: mySubmitPrompt.isModelLoaded
                                && !mySubmitPrompt.isProcessingInference
                                && (mySubmitPrompt.modelSupportsImage
                                    || mySubmitPrompt.modelSupportsVideo)
                        opacity: enabled ? 1.0 : 0.3
                        background: Rectangle {
                            color: mediaSource === "camera" ? "#80000000" : "transparent"
                            radius: 8
                        }
                        contentItem: Image {
                            anchors.centerIn: parent
                            width: parent.width * 0.72
                            height: parent.width * 0.72
                            source: "images/camera.svg"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            antialiasing: true
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
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        display: AbstractButton.IconOnly
                        // Reuse existing flags - button disabled when any indicator is showing
                        enabled: mySubmitPrompt.isModelLoaded
                                && window.mediaSource === "camera"
                                && video_1.cameraConnected
                                && !window.showRecordingIndicator
                                && !window.showProcessingIndicator
                        opacity: enabled ? 1.0 : 0.3
                        background: Rectangle { color: "transparent" }
                        contentItem: Image {
                            anchors.centerIn: parent
                            width: parent.width * 0.72
                            height: parent.width * 0.72
                            source: capture_button.down ? "images/capture_pressed.svg" : "images/capture_unpressed.svg"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            antialiasing: true
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

            // Text field for analysis queries  
            RowLayout {
                id: promptRow
                Layout.fillWidth: true
                Layout.fillHeight: true
                anchors.leftMargin:  theme.standardMargin
                anchors.rightMargin: theme.standardMargin
                spacing: theme.standardMargin

                TextField {
                    id: inputPrompt
                    Layout.fillWidth: true
                    Layout.preferredHeight: theme.inputHeight

                    placeholderText: "Enter your analysis prompt..."
                    placeholderTextColor: theme.textSecondary
                    color: enabled ? theme.textPrimary : theme.textSecondary
                    selectedTextColor: "#EBE7DD"
                    selectionColor: "#0068DF"
                    text: mySubmitPrompt.userPromptText
                    focus: true

                    font.pixelSize: theme.fontLarge
                    font.family: "Poppins"
                    wrapMode: TextInput.WordWrap
                    padding: 5
                    rightPadding: 5
                    leftPadding: 5
                    bottomPadding: 5
                    topPadding: 5
                    verticalAlignment: TextInput.AlignVCenter

                    cursorDelegate: Rectangle {
                        id: cursor
                        width: 2
                        height: inputPrompt.font.pixelSize + 6
                        color: theme.accentPrimary
                        visible: inputPrompt.cursorVisible && inputPrompt.activeFocus
                        radius: 1

                        SequentialAnimation on opacity {
                            running: inputPrompt.activeFocus
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.0; duration: 600; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 0.0; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                        }

                        // Reset opacity when focus is lost
                        onVisibleChanged: {
                            if (!visible) opacity = 1.0
                        }
                    }

                    enabled: !window.isRecording
                            && !window.isProcessing
                            && !mySubmitPrompt.isProcessingInference
                            && !mySubmitPrompt.isLoadingMedia
                            && mySubmitPrompt.isModelLoaded
                    opacity: enabled ? 1.0 : 0.5

                    background: Rectangle {
                        color: theme.bgSecondary
                        radius: theme.standardRadius
                        border.color: inputPrompt.activeFocus ? theme.accentPrimary : theme.borderInactive
                        border.width: theme.borderWidth

                        Behavior on border.color {
                            ColorAnimation {
                                duration: theme.animationFast
                            }
                        }
                    }

                    Keys.onReturnPressed: {
                        mySubmitPrompt.setUserPromptText(inputPrompt.text)
                    }

                    Component.onCompleted: {
                        if (inputPrompt.enabled) {
                            console.log("force active focus")
                            inputPrompt.forceActiveFocus()
                        }
                    }
                }

                Button {
                    id: submitButton
                    Layout.preferredWidth: theme.submitWidth
                    Layout.fillHeight: true
                    enabled: canSubmit() && !mySubmitPrompt.isProcessingInference
                            && !mySubmitPrompt.isLoadingMedia
                    opacity: enabled ? 1.0 : 0.3

                    onClicked: mySubmitPrompt.setUserPromptText(inputPrompt.text)

                    background: Rectangle {
                        color: submitButton.hovered && submitButton.enabled
                               ? theme.accentSecondary
                               : "transparent"
                        radius: theme.standardRadius
                        Behavior on color {
                            ColorAnimation { duration: theme.animationFast }
                        }
                    }

                    contentItem: Image {
                        anchors.fill: parent
                        source: "../images/submit.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        antialiasing: true
                    }

                    scale: submitButton.enabled && submitButton.hovered ? 1.05 : 1.0
                    Behavior on scale {
                        NumberAnimation { duration: theme.animationFast; easing.type: Easing.OutQuad }
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
    }

    // ═══════════════════════════════════════════════════════════════
    // MODEL CONFIG POPUP
    // ═══════════════════════════════════════════════════════════════
    Popup {
        id: modelConfigPopup
        width: 430
        height: 360
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        x: (window.width - width) / 2
        y: (window.height - height) / 2

        // Working copy edited by the user; committed to backend only on Apply
        property var pendingParams: ({})

        // True only when every visible field holds an acceptable value
        property bool allValid: fieldMaxTokens.acceptableInput &&
                                fieldTemperature.fieldValid &&
                                fieldTopK.acceptableInput &&
                                fieldTopP.fieldValid

        onOpened: {
            pendingParams = Object.assign({}, mySubmitPrompt.llmParams)
            // Reset debounced valid flags so the popup opens without red borders
            fieldTemperature.fieldValid = true
            fieldTopP.fieldValid = true
        }

        // Refresh all TextField texts when pendingParams is replaced (Reset or Open)
        onPendingParamsChanged: {
            if (pendingParams["generate_max_tokens"] !== undefined)
                fieldMaxTokens.text = pendingParams["generate_max_tokens"].toString()
            if (pendingParams["temperature"] !== undefined)
                fieldTemperature.text = pendingParams["temperature"].toString()
            if (pendingParams["top_k"] !== undefined)
                fieldTopK.text = pendingParams["top_k"].toString()
            if (pendingParams["top_p"] !== undefined)
                fieldTopP.text = pendingParams["top_p"].toString()
        }

        background: Rectangle {
            color: theme.bgSecondary
            border.color: theme.borderPopup
            border.width: theme.borderWidth
            radius: theme.standardRadius
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Text {
                text: "Model Configuration"
                color: theme.textPrimary
                font.pixelSize: theme.fontSmall
                font.family: "Poppins"
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: theme.borderInactive }

            // Max Tokens row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "Max Tokens (1-4096):"
                    color: theme.textSecondary
                    font.pixelSize: theme.fontMicro
                    font.family: "Poppins"
                    Layout.preferredWidth: 180
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Button {
                        id: maxTokDecBtn
                        width: 26; height: 32
                        text: "<"
                        font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        onClicked: {
                            var v = Math.max(1, (parseInt(fieldMaxTokens.text) || 1) - 1)
                            fieldMaxTokens.text = v.toString()
                            var m = Object.assign({}, modelConfigPopup.pendingParams)
                            m["generate_max_tokens"] = v
                            modelConfigPopup.pendingParams = m
                        }
                        background: Rectangle {
                            color: maxTokDecBtn.pressed ? theme.accentPrimary : maxTokDecBtn.hovered ? theme.bgSecondary : theme.bgTertiary
                            radius: theme.smallRadius; border.color: theme.borderInactive; border.width: theme.borderWidth
                        }
                        contentItem: Text { text: maxTokDecBtn.text; font: maxTokDecBtn.font; color: theme.textSecondary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    TextField {
                        id: fieldMaxTokens
                        Layout.fillWidth: true; height: 32
                        color: theme.textPrimary; font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        horizontalAlignment: Text.AlignHCenter
                        selectionColor: theme.accentPrimary
                        selectedTextColor: theme.bgPrimary
                        selectByMouse: true
                        cursorDelegate: Rectangle { color: theme.accentPrimary; width: 2; radius: 1 }
                        text: modelConfigPopup.pendingParams["generate_max_tokens"] !== undefined ? modelConfigPopup.pendingParams["generate_max_tokens"].toString() : ""
                        validator: IntValidator { bottom: 1; top: 4096 }
                        inputMethodHints: Qt.ImhDigitsOnly
                        background: Rectangle {
                            color: theme.bgTertiary
                            border.color: !fieldMaxTokens.acceptableInput ? "#FF453A" : fieldMaxTokens.activeFocus ? theme.accentPrimary : theme.borderInactive
                            border.width: theme.borderWidth
                            Behavior on border.color { ColorAnimation { duration: theme.animationFast } }
                        }
                        onTextEdited: {
                            if (!acceptableInput) return
                            var m = Object.assign({}, modelConfigPopup.pendingParams)
                            m["generate_max_tokens"] = parseInt(text)
                            modelConfigPopup.pendingParams = m
                        }
                        onEditingFinished: {
                            if (acceptableInput) {
                                var m = Object.assign({}, modelConfigPopup.pendingParams)
                                m["generate_max_tokens"] = parseInt(text)
                                modelConfigPopup.pendingParams = m
                            }
                        }
                    }
                    Button {
                        id: maxTokIncBtn
                        width: 26; height: 32
                        text: ">"
                        font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        onClicked: {
                            var v = Math.min(4096, (parseInt(fieldMaxTokens.text) || 0) + 1)
                            fieldMaxTokens.text = v.toString()
                            var m = Object.assign({}, modelConfigPopup.pendingParams)
                            m["generate_max_tokens"] = v
                            modelConfigPopup.pendingParams = m
                        }
                        background: Rectangle {
                            color: maxTokIncBtn.pressed ? theme.accentPrimary : maxTokIncBtn.hovered ? theme.bgSecondary : theme.bgTertiary
                            radius: theme.smallRadius; border.color: theme.borderInactive; border.width: theme.borderWidth
                        }
                        contentItem: Text { text: maxTokIncBtn.text; font: maxTokIncBtn.font; color: theme.textSecondary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }

            // Temperature row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "Temperature (0.0-1.0):"
                    color: theme.textSecondary; font.pixelSize: theme.fontMicro; font.family: "Poppins"
                    Layout.preferredWidth: 180
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Button {
                        id: tempDecBtn
                        width: 26; height: 32; text: "<"
                        font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        onClicked: {
                            var v = Math.round((parseFloat(fieldTemperature.text || "0") - 0.1) * 10) / 10
                            v = Math.max(0.0, Math.min(1.0, v))
                            fieldTemperature.text = v.toFixed(1)
                            fieldTemperature.fieldValid = true
                            var m = Object.assign({}, modelConfigPopup.pendingParams)
                            m["temperature"] = v
                            modelConfigPopup.pendingParams = m
                        }
                        background: Rectangle { color: tempDecBtn.pressed ? theme.accentPrimary : tempDecBtn.hovered ? theme.bgSecondary : theme.bgTertiary; radius: theme.smallRadius; border.color: theme.borderInactive; border.width: theme.borderWidth }
                        contentItem: Text { text: tempDecBtn.text; font: tempDecBtn.font; color: theme.textSecondary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    TextField {
                        id: fieldTemperature
                        Layout.fillWidth: true; height: 32
                        color: theme.textPrimary; font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        horizontalAlignment: Text.AlignHCenter
                        selectionColor: theme.accentPrimary
                        selectedTextColor: theme.bgPrimary
                        selectByMouse: true
                        cursorDelegate: Rectangle { color: theme.accentPrimary; width: 2; radius: 1 }
                        text: modelConfigPopup.pendingParams["temperature"] !== undefined ? modelConfigPopup.pendingParams["temperature"].toString() : ""
                        validator: RegularExpressionValidator { regularExpression: /^(0(\.\d{0,2})?|\.\d{1,2}|1(\.0{0,2})?)$/ }
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        property bool fieldValid: true
                        Timer {
                            id: tempDebounce; interval: 600; repeat: false
                            onTriggered: {
                                fieldTemperature.fieldValid = fieldTemperature.acceptableInput
                                if (fieldTemperature.acceptableInput) {
                                    var m = Object.assign({}, modelConfigPopup.pendingParams)
                                    m["temperature"] = parseFloat(fieldTemperature.text)
                                    modelConfigPopup.pendingParams = m
                                }
                            }
                        }
                        background: Rectangle {
                            color: theme.bgTertiary
                            border.color: !fieldTemperature.fieldValid ? "#FF453A" : fieldTemperature.activeFocus ? theme.accentPrimary : theme.borderInactive
                            border.width: theme.borderWidth
                            Behavior on border.color { ColorAnimation { duration: theme.animationFast } }
                        }
                        onTextEdited: tempDebounce.restart()
                        onEditingFinished: {
                            tempDebounce.stop()
                            fieldValid = acceptableInput
                            if (acceptableInput) {
                                var m = Object.assign({}, modelConfigPopup.pendingParams)
                                m["temperature"] = parseFloat(text)
                                modelConfigPopup.pendingParams = m
                            }
                        }
                    }
                    Button {
                        id: tempIncBtn
                        width: 26; height: 32; text: ">"
                        font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        onClicked: {
                            var v = Math.round((parseFloat(fieldTemperature.text || "0") + 0.1) * 10) / 10
                            v = Math.max(0.0, Math.min(1.0, v))
                            fieldTemperature.text = v.toFixed(1)
                            fieldTemperature.fieldValid = true
                            var m = Object.assign({}, modelConfigPopup.pendingParams)
                            m["temperature"] = v
                            modelConfigPopup.pendingParams = m
                        }
                        background: Rectangle { color: tempIncBtn.pressed ? theme.accentPrimary : tempIncBtn.hovered ? theme.bgSecondary : theme.bgTertiary; radius: theme.smallRadius; border.color: theme.borderInactive; border.width: theme.borderWidth }
                        contentItem: Text { text: tempIncBtn.text; font: tempIncBtn.font; color: theme.textSecondary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }

            // Top-K row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "Top K (0-100):"
                    color: theme.textSecondary; font.pixelSize: theme.fontMicro; font.family: "Poppins"
                    Layout.preferredWidth: 180
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Button {
                        id: topKDecBtn
                        width: 26; height: 32; text: "<"
                        font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        onClicked: {
                            var v = Math.max(0, (parseInt(fieldTopK.text) || 0) - 1)
                            fieldTopK.text = v.toString()
                            var m = Object.assign({}, modelConfigPopup.pendingParams)
                            m["top_k"] = v
                            modelConfigPopup.pendingParams = m
                        }
                        background: Rectangle { color: topKDecBtn.pressed ? theme.accentPrimary : topKDecBtn.hovered ? theme.bgSecondary : theme.bgTertiary; radius: theme.smallRadius; border.color: theme.borderInactive; border.width: theme.borderWidth }
                        contentItem: Text { text: topKDecBtn.text; font: topKDecBtn.font; color: theme.textSecondary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    TextField {
                        id: fieldTopK
                        Layout.fillWidth: true; height: 32
                        color: theme.textPrimary; font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        horizontalAlignment: Text.AlignHCenter
                        selectionColor: theme.accentPrimary
                        selectedTextColor: theme.bgPrimary
                        selectByMouse: true
                        cursorDelegate: Rectangle { color: theme.accentPrimary; width: 2; radius: 1 }
                        text: modelConfigPopup.pendingParams["top_k"] !== undefined ? modelConfigPopup.pendingParams["top_k"].toString() : ""
                        validator: IntValidator { bottom: 0; top: 100 }
                        inputMethodHints: Qt.ImhDigitsOnly
                        background: Rectangle {
                            color: theme.bgTertiary
                            border.color: !fieldTopK.acceptableInput ? "#FF453A" : fieldTopK.activeFocus ? theme.accentPrimary : theme.borderInactive
                            border.width: theme.borderWidth
                            Behavior on border.color { ColorAnimation { duration: theme.animationFast } }
                        }
                        onTextEdited: {
                            if (!acceptableInput) return
                            var m = Object.assign({}, modelConfigPopup.pendingParams)
                            m["top_k"] = parseInt(text)
                            modelConfigPopup.pendingParams = m
                        }
                        onEditingFinished: {
                            if (acceptableInput) {
                                var m = Object.assign({}, modelConfigPopup.pendingParams)
                                m["top_k"] = parseInt(text)
                                modelConfigPopup.pendingParams = m
                            }
                        }
                    }
                    Button {
                        id: topKIncBtn
                        width: 26; height: 32; text: ">"
                        font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        onClicked: {
                            var v = Math.min(100, (parseInt(fieldTopK.text) || 0) + 1)
                            fieldTopK.text = v.toString()
                            var m = Object.assign({}, modelConfigPopup.pendingParams)
                            m["top_k"] = v
                            modelConfigPopup.pendingParams = m
                        }
                        background: Rectangle { color: topKIncBtn.pressed ? theme.accentPrimary : topKIncBtn.hovered ? theme.bgSecondary : theme.bgTertiary; radius: theme.smallRadius; border.color: theme.borderInactive; border.width: theme.borderWidth }
                        contentItem: Text { text: topKIncBtn.text; font: topKIncBtn.font; color: theme.textSecondary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }

            // Top-P row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "Top P (0.0-1.0):"
                    color: theme.textSecondary; font.pixelSize: theme.fontMicro; font.family: "Poppins"
                    Layout.preferredWidth: 180
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Button {
                        id: topPDecBtn
                        width: 26; height: 32; text: "<"
                        font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        onClicked: {
                            var v = Math.round((parseFloat(fieldTopP.text || "0") - 0.1) * 10) / 10
                            v = Math.max(0.0, Math.min(1.0, v))
                            fieldTopP.text = v.toFixed(1)
                            fieldTopP.fieldValid = true
                            var m = Object.assign({}, modelConfigPopup.pendingParams)
                            m["top_p"] = v
                            modelConfigPopup.pendingParams = m
                        }
                        background: Rectangle { color: topPDecBtn.pressed ? theme.accentPrimary : topPDecBtn.hovered ? theme.bgSecondary : theme.bgTertiary; radius: theme.smallRadius; border.color: theme.borderInactive; border.width: theme.borderWidth }
                        contentItem: Text { text: topPDecBtn.text; font: topPDecBtn.font; color: theme.textSecondary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    TextField {
                        id: fieldTopP
                        Layout.fillWidth: true; height: 32
                        color: theme.textPrimary; font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        horizontalAlignment: Text.AlignHCenter
                        selectionColor: theme.accentPrimary
                        selectedTextColor: theme.bgPrimary
                        selectByMouse: true
                        cursorDelegate: Rectangle { color: theme.accentPrimary; width: 2; radius: 1 }
                        text: modelConfigPopup.pendingParams["top_p"] !== undefined ? modelConfigPopup.pendingParams["top_p"].toString() : ""
                        validator: RegularExpressionValidator { regularExpression: /^(0(\.\d{0,4})?|\.\d{1,4}|1(\.0{0,4})?)$/ }
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        property bool fieldValid: true
                        Timer {
                            id: topPDebounce; interval: 600; repeat: false
                            onTriggered: {
                                fieldTopP.fieldValid = fieldTopP.acceptableInput
                                if (fieldTopP.acceptableInput) {
                                    var m = Object.assign({}, modelConfigPopup.pendingParams)
                                    m["top_p"] = parseFloat(fieldTopP.text)
                                    modelConfigPopup.pendingParams = m
                                }
                            }
                        }
                        background: Rectangle {
                            color: theme.bgTertiary
                            border.color: !fieldTopP.fieldValid ? "#FF453A" : fieldTopP.activeFocus ? theme.accentPrimary : theme.borderInactive
                            border.width: theme.borderWidth
                            Behavior on border.color { ColorAnimation { duration: theme.animationFast } }
                        }
                        onTextEdited: topPDebounce.restart()
                        onEditingFinished: {
                            topPDebounce.stop()
                            fieldValid = acceptableInput
                            if (acceptableInput) {
                                var m = Object.assign({}, modelConfigPopup.pendingParams)
                                m["top_p"] = parseFloat(text)
                                modelConfigPopup.pendingParams = m
                            }
                        }
                    }
                    Button {
                        id: topPIncBtn
                        width: 26; height: 32; text: ">"
                        font.pixelSize: theme.fontMicro; font.family: "Poppins"
                        onClicked: {
                            var v = Math.round((parseFloat(fieldTopP.text || "0") + 0.1) * 10) / 10
                            v = Math.max(0.0, Math.min(1.0, v))
                            fieldTopP.text = v.toFixed(1)
                            fieldTopP.fieldValid = true
                            var m = Object.assign({}, modelConfigPopup.pendingParams)
                            m["top_p"] = v
                            modelConfigPopup.pendingParams = m
                        }
                        background: Rectangle { color: topPIncBtn.pressed ? theme.accentPrimary : topPIncBtn.hovered ? theme.bgSecondary : theme.bgTertiary; radius: theme.smallRadius; border.color: theme.borderInactive; border.width: theme.borderWidth }
                        contentItem: Text { text: topPIncBtn.text; font: topPIncBtn.font; color: theme.textSecondary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: theme.borderInactive }

            // Reset / Apply row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    Layout.fillWidth: true; height: 42
                    text: "Reset"
                    font.pixelSize: theme.fontMicro; font.family: "Poppins"; font.bold: true
                    onClicked: {
                        tempDebounce.stop()
                        topPDebounce.stop()
                        modelConfigPopup.pendingParams = Object.assign({}, mySubmitPrompt.defaultLlmParams)
                        fieldTemperature.fieldValid = true
                        fieldTopP.fieldValid = true
                    }
                    background: Rectangle {
                        color: parent.pressed ? "#C0392B" : parent.hovered ? "#E74C3C" : theme.bgSecondary
                        radius: theme.smallRadius; border.color: "#E74C3C"; border.width: theme.borderWidth
                        Behavior on color { ColorAnimation { duration: theme.animationFast } }
                    }
                    contentItem: Text { text: parent.text; font: parent.font; color: theme.textPrimary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }

                Button {
                    Layout.fillWidth: true; height: 42
                    text: "Apply"
                    font.pixelSize: theme.fontMicro; font.family: "Poppins"; font.bold: true
                    enabled: modelConfigPopup.allValid
                    opacity: enabled ? 1.0 : 0.35
                    onClicked: {
                        mySubmitPrompt.setLlmParams(modelConfigPopup.pendingParams)
                        modelConfigPopup.close()
                    }
                    background: Rectangle {
                        color: parent.enabled && parent.pressed ? "#27AE60" : parent.enabled && parent.hovered ? "#2ECC71" : parent.enabled ? theme.bgSecondary : theme.bgTertiary
                        radius: theme.smallRadius
                        border.color: parent.enabled ? theme.accentSecondary : theme.borderInactive
                        border.width: theme.borderWidth
                        Behavior on color { ColorAnimation { duration: theme.animationFast } }
                        Behavior on border.color { ColorAnimation { duration: theme.animationFast } }
                    }
                    contentItem: Text { text: parent.text; font: parent.font; color: parent.enabled ? theme.textPrimary : theme.textSecondary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // REUSABLE COMPONENTS
    // ═══════════════════════════════════════════════════════════════
    component ActionButton: Button {
        id: actionBtn
        property color accentColor: theme.accentPrimary
        font.pixelSize: theme.fontMicro
        font.family: "Poppins"
        font.bold: true
        opacity: enabled ? 1.0 : 0.3
        hoverEnabled: true

        background: Rectangle {
            color: actionBtn.enabled && actionBtn.hovered
                   ? actionBtn.accentColor : theme.bgSecondary
            radius: theme.smallRadius
            border.color: actionBtn.enabled ? actionBtn.accentColor : theme.borderInactive
            border.width: theme.borderWidth
            Behavior on color { ColorAnimation { duration: theme.animationFast } }
        }

        contentItem: Text {
            text: actionBtn.text
            font: actionBtn.font
            color: actionBtn.enabled ? theme.textPrimary : theme.textSecondary
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component StyledComboBox: ComboBox {
        id: combo
        font.pixelSize: theme.fontTiny
        font.family: "Poppins"
        opacity: enabled ? 1.0 : 0.5

        background: Rectangle {
            color: combo.enabled ? theme.bgSecondary : theme.bgTertiary
            border.color: combo.down ? theme.accentPrimary : theme.borderInactive
            border.width: 1
            radius: 4
        }

        contentItem: Text {
            leftPadding: 10
            text: combo.displayText
            font: combo.font
            color: combo.enabled ? theme.textPrimary : theme.textSecondary
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        popup: Popup {
            y: combo.height
            width: combo.width
            implicitHeight: contentItem.implicitHeight
            padding: 1
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
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
            width: combo.width
            contentItem: Text {
                text: modelData
                color: "#ffffff"
                font: combo.font
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                leftPadding: 10
            }
            highlighted: combo.highlightedIndex === index
            background: Rectangle {
                color: highlighted ? "#0eafe0" : "transparent"
                opacity: highlighted ? 0.3 : 1.0
            }
        }
    }

    component AnimatedProgressBar: ProgressBar {
        id: progBar
        indeterminate: false
        property bool allowAnimation: true

        background: Rectangle {
            implicitWidth:  parent.width
            implicitHeight: parent.height
            color:  theme.bgTertiary
            radius: 10
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
                width:  progBar.visualPosition * parent.width
                radius: 10
                transformOrigin: Item.Left
                clip: true

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00D9FF" }
                    GradientStop { position: 1.0; color: "#0A84FF" }
                }

                SequentialAnimation on scale {
                    running: progBar.visible && mainProgress.width > 0
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 1.02; duration: theme.animationSlow; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 1.02; to: 1.0; duration: theme.animationSlow; easing.type: Easing.InOutQuad }
                }

                Rectangle {
                    id: shimmer
                    width:  60
                    height: parent.height
                    radius: 10
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#00FFFFFF" }
                        GradientStop { position: 0.3; color: "#80FFFFFF" }
                        GradientStop { position: 0.7; color: "#80FFFFFF" }
                        GradientStop { position: 1.0; color: "#00FFFFFF" }
                    }
                    SequentialAnimation on x {
                        running: progBar.visible && mainProgress.width > shimmer.width
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0
                            to: mainProgress.width - shimmer.width
                            duration: theme.animationShimmer
                            easing.type: Easing.InOutQuad
                        }
                        PauseAnimation { duration: theme.animationFast }
                    }
                }
            }
        }

        Behavior on value {
            enabled: progBar.allowAnimation
            NumberAnimation {
                duration: theme.animationMedium
                easing.type: Easing.OutQuad
            }
        }
    }

    ProgressBar {
        id: progressBarTTFT
        visible: false
        from: 0; to: 10000; value: 0
    }
}
