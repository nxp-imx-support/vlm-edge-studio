/*
 * SPDX-License-Identifier: BSD-3-Clause
 * Copyright 2025-2026 NXP
 *
 * @file gsttestglsink.cpp
 * @brief GStreamer test pattern video sink implementation
 */

#include "gsttestglsink.h"

#include <QLoggingCategory>
#include <QtConcurrent>
#include <QImage>
#include <QTimer>

Q_DECLARE_LOGGING_CATEGORY(lcGstGL)

GstTestGLSink::GstTestGLSink(QQuickItem *parent)
    : GstQmlGLSinkBase(parent),
      m_patternType(0),
      m_animate(false),
      m_isRecording(false),
      m_cameraStream(false),
      m_captureFrameRequested(false),
      m_videoPath("/usr/share/vlm-edge-studio/assets/videos/video.mp4"),
      m_cameraDevice("/dev/video0"),
      m_cameraDetector(new CameraDetector(this)),
      m_captureFramePath("") {

  // Validate that the selected camera is still available
  if (!m_cameraDetector->isCameraAvailable(m_cameraDevice)) {
      qWarning() << "Selected camera" << m_cameraDevice << "not available";
      auto cameras = m_cameraDetector->availableCameras();
      if (!cameras.isEmpty()) {
          // Extract device path from display name
          m_cameraDevice = cameras.first().split(" - ").first();
          qCDebug(lcGstGL) << "Camera device updated to:" << m_cameraDevice;
      } else {
          m_cameraDevice = "/dev/video0";
      }
  }


}

void GstTestGLSink::setPatternType(int type) {
  if (m_patternType != type) {
    m_patternType = type;
    Q_EMIT patternTypeChanged();
  }
}

void GstTestGLSink::setAnimate(bool animate) {
  if (m_animate != animate) {
    m_animate = animate;
    Q_EMIT animateChanged();
  }
}

void GstTestGLSink::connectSinkSignals(GstElement *pipeline) {
  GstElement *appsink = gst_bin_get_by_name(GST_BIN(pipeline), "sink");
  if (appsink) {
    m_sinkElements.append(appsink);

    // Connect multiple signals
    gulong sampleHandler = g_signal_connect(
        appsink, "new-sample", G_CALLBACK(newSampleCallback), this);
    gulong eosHandler =
        g_signal_connect(appsink, "eos", G_CALLBACK(eosCallback), this);

    m_signalHandlers.append(sampleHandler);
    m_signalHandlers.append(eosHandler);
    qCDebug(lcGstGL) << "Connected signals to main display sink";
  }

  // Connect to recording monitoring sink (only in camera mode)
  if (m_cameraStream) {
    GstElement *recordSink = gst_bin_get_by_name(GST_BIN(pipeline), "record_sink");
    if (recordSink) {
      m_sinkElements.append(recordSink);

      gulong recordSampleHandler = g_signal_connect(
          recordSink, "new-sample", G_CALLBACK(recordSampleCallback), this);
      gulong recordEosHandler =
          g_signal_connect(recordSink, "eos", G_CALLBACK(eosCallback), this);

      m_signalHandlers.append(recordSampleHandler);
      m_signalHandlers.append(recordEosHandler);

      qCDebug(lcGstGL) << "Connected signals to recording monitoring sink";
    }
  }

}

QString GstTestGLSink::createPipelineString(const QString &uri) {
  QString pipeline;

  qCDebug(lcGstGL) << "=== PIPELINE CREATION DEBUG ===";
  qCDebug(lcGstGL) << "Camera stream:" << m_cameraStream;
  qCDebug(lcGstGL) << "Is recording:" << m_isRecording;
  qCDebug(lcGstGL) << "URI:" << uri;

  if (m_cameraStream) {
    // Camera pipeline with error handling
    pipeline = QString(
      "v4l2src device=%1 ! "
      "video/x-raw,width=640,height=480,framerate=30/1 ! "
      "imxvideoconvert_g2d ! video/x-raw,format=RGBA ! "
      "tee name=t allow-not-linked=true "

      // Branch 1: Display path (always active)
      "t. ! queue name=display_queue max-size-buffers=2 leaky=downstream ! "
      "appsink name=sink sync=false drop=true max-buffers=1 emit-signals=true "

      // Branch 2: Recording + Capture path (shared, JPEG-encoded)
      "t. ! queue name=record_queue max-size-buffers=2 leaky=downstream ! "
      "appsink name=record_sink sync=false drop=true max-buffers=1 "
      "emit-signals=true").arg(m_cameraDevice);

      qCDebug(lcGstGL) << "Created camera pipeline for " << m_cameraDevice;

  } else {
    qCDebug (lcGstGL) << "Creating default video pipeline";
    pipeline = QString(
      "filesrc location=%1 ! decodebin3 ! imxvideoconvert_g2d ! video/x-raw,format=RGBA ! "
      "appsink name=sink sync=true drop=true max-buffers=1 "
      "emit-signals=true").arg(m_videoPath);

    qCDebug(lcGstGL) << "Created video file pipeline for:" << m_videoPath;
  }

  qCDebug(lcGstGL) << "gst-launch-1.0 " << pipeline;
  return pipeline;
}

// Static callback implementations
GstFlowReturn GstTestGLSink::newSampleCallback(GstElement *sink, gpointer user_data) {
  GstTestGLSink *self = static_cast<GstTestGLSink *>(user_data);

  GstSample *sample = nullptr;
  g_signal_emit_by_name(sink, "pull-sample", &sample);

  if (sample) {
    self->processSample(sample);
    gst_sample_unref(sample);
  }

  return GST_FLOW_OK;
}

// New callback for recording branch monitoring
GstFlowReturn GstTestGLSink::recordSampleCallback(GstElement *sink, gpointer user_data) {
  GstTestGLSink *self = static_cast<GstTestGLSink *>(user_data);

  GstSample *sample = nullptr;
  g_signal_emit_by_name(sink, "pull-sample", &sample);

  if (!sample) {
    return GST_FLOW_OK;
  }

  GstBuffer *buffer = gst_sample_get_buffer(sample);
  if (!buffer) {
    gst_sample_unref(sample);
    return GST_FLOW_ERROR;
  }

    // CHECK 1: Single frame capture (encode RGBA → JPEG in software)
  {
    QMutexLocker locker(&self->m_frameBufferMutex);
    if (self->m_captureFrameRequested) {
      qCDebug(lcGstGL) << "[Frame Capture] Capturing single frame";

      // Map buffer and save JPEG
      GstMapInfo map;
      if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
        QString filePath = self->m_captureFramePath;
        QImage image(map.data, 640, 480, QImage::Format_RGBA8888);

        if (image.save(filePath, "JPEG", 85)) {  // 85 = quality
          QFileInfo fileInfo(filePath);
          qCDebug(lcGstGL) << "[Frame Capture] Saved JPEG:" << filePath;
          qCDebug(lcGstGL) << "[Frame Capture] File size:" << fileInfo.size() << "bytes";

          // Emit signal to QML
          QMetaObject::invokeMethod(self, [self, filePath]() {
            Q_EMIT self->frameCaptured(filePath);
          }, Qt::QueuedConnection);
        } else {
          qCWarning(lcGstGL) << "[Frame Capture] Failed to save JPEG:" << filePath;
        }

        gst_buffer_unmap(buffer, &map);
      }

      // Reset flag
      self->m_captureFrameRequested = false;
      self->m_captureFramePath = "";

      gst_sample_unref(sample);
      return GST_FLOW_OK;
      }
  }

    // Process only when recording is active
    if(self->m_isRecording){
        // Extract frame data and store in buffer
        GstBuffer *buffer = gst_sample_get_buffer(sample);
        if (buffer) {
            GstMapInfo map;
            if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
                // Store frame in buffer
                QMutexLocker locker(&self->m_frameBufferMutex);
                QByteArray frameData((const char*)map.data, map.size);
                self->m_recordedFrameBuffer.append(frameData);

                gst_buffer_unmap(buffer, &map);
                self->m_recordedFrames++;

                // Stop after 240 frames
                if (self->m_recordedFrames >= MAX_RECORDING_FRAMES) {
                QMetaObject::invokeMethod(self, [self]() {
                    qCDebug(lcGstGL) << "Reached 240 frames - stopping recording";
                    self->stopRecording();
                }, Qt::QueuedConnection);
                }

                // Emit progress
                QMetaObject::invokeMethod(self, [self]() {
                Q_EMIT self->recordingProgress(self->m_recordedFrames, MAX_RECORDING_FRAMES);
                }, Qt::QueuedConnection);
            }
        }
    }

    gst_sample_unref(sample);
    return GST_FLOW_OK;
}

void GstTestGLSink::eosCallback(GstElement *sink, gpointer user_data) {
  GstTestGLSink *self = static_cast<GstTestGLSink *>(user_data);
  Q_UNUSED(sink)

  qDebug() << "End of stream received";
  // Emit a signal or handle EOS as needed
  QMetaObject::invokeMethod(
      self,
      [self]() {
        // Handle EOS in main thread
        qDebug() << "Processing EOS in main thread";
      },
      Qt::QueuedConnection);
}

bool GstTestGLSink::isRecording() const {
  return true;
}

void GstTestGLSink::setIsRecording(bool recording) {
    if (m_isRecording != recording) {
        m_isRecording = recording;
    }
}

QString GstTestGLSink::videoSource() const {
  return m_videoPath;
}

bool GstTestGLSink::cameraStream() const {
  return true;
}

bool GstTestGLSink::cameraConnected() const {
  return true;
}

bool GstTestGLSink::playing() const {
    return true;
}

float GstTestGLSink::ratio() const {
    return 1.0f;  // Default implementation returning a standard aspect ratio
}

void GstTestGLSink::setVideoSource(const QString &path) {
  m_videoPath = path;
  Q_EMIT videoSourceChanged();
}

void GstTestGLSink::setCameraStream(bool stream) {
  if (m_cameraStream != stream) {
        m_cameraStream = stream;
        Q_EMIT cameraStreamChanged();
    }
}

void GstTestGLSink::setCameraConnected(bool){}
void GstTestGLSink::setPlaying(bool){}
void GstTestGLSink::setRatio(float){}

void GstTestGLSink::startRecording() {
    if (!m_cameraStream) {
        qCWarning(lcGstGL) << "Recording only available in camera mode";
        return;
    }

    if (m_isRecording) {
        qCWarning(lcGstGL) << "Recording already in progress";
        return;
    }

    // Clear any existing buffer
    QMutexLocker locker(&m_frameBufferMutex);
    m_recordedFrameBuffer.clear();

    m_isRecording = true;
    m_recordedFrames = 0;

    Q_EMIT recordingStarted();
    qCDebug(lcGstGL) << "Recording started - monitoring frames";
}

void GstTestGLSink::stopRecording() {
    if (!m_isRecording) {
        return;
    }

    m_isRecording = false;

    qCDebug(lcGstGL) << "Recording stopped - captured " << m_recordedFrames << " frames";
    qCDebug(lcGstGL) << "Start MP4 encoding...";

    // After successfully saving the video
    QString recordedPath = "/usr/share/vlm-edge-studio/assets/videos/recording.mp4";
    m_recordedVideoPath = recordedPath;
    Q_EMIT recordingFinished(recordedPath);

    // Start background encoding
    auto future = QtConcurrent::run([this]() {
        encodeFramesToMP4();
    });

    Q_UNUSED(future);
}

void GstTestGLSink::switchToPlaybackMode() {
    qCDebug(lcGstGL) << "Switching to video playback mode";

    // Switch from camera to video mode
    m_cameraStream = false;
    m_isRecording = false;

    // Restart pipeline for video playback
    if (playing()) {
        stopPipeline();
        // Set video source to the recorded file
        setVideoSource("/usr/share/vlm-edge-studio/assets/videos/recording.mp4");
        startPipeline();
    }

    Q_EMIT cameraStreamChanged();
    Q_EMIT videoModeActivated();
}

void GstTestGLSink::sendEOSToRecordingBranch() {
    if (!m_pipeline) return;

    // Send EOS to the recording sink to finalize MP4
    GstElement *recordSink = gst_bin_get_by_name(GST_BIN(m_pipeline), "record_sink");
    if (recordSink) {
        GstPad *sinkPad = gst_element_get_static_pad(recordSink, "sink");
        if (sinkPad) {
            gst_pad_send_event(sinkPad, gst_event_new_eos());
            gst_object_unref(sinkPad);
        }
        gst_object_unref(recordSink);
    }
}

void GstTestGLSink::encodeFramesToMP4() {
    QMutexLocker locker(&m_frameBufferMutex);

    if (m_recordedFrameBuffer.isEmpty()) {
        qCWarning(lcGstGL) << "No frames to encode";
        return;
    }

    // Write frames to temporary raw file
    QString tempRawFile = "/tmp/recording_raw.rgba";
    QFile rawFile(tempRawFile);

    if (!rawFile.open(QIODevice::WriteOnly)) {
        qCWarning(lcGstGL) << "Failed to create temporary raw file";
        return;
    }

    for (const QByteArray &frameData : m_recordedFrameBuffer) {
        rawFile.write(frameData);
    }
    rawFile.close();
    m_recordedFrameBuffer.clear();

    // Direct Raw → MP4 using system command
    QString finalMp4File = "/usr/share/vlm-edge-studio/assets/videos/recording.mp4";
    QString mp4Command = QString(
        "gst-launch-1.0 -e filesrc location=%1 "
        "! rawvideoparse width=640 height=480 framerate=30/1 format=rgba "
        "! videoconvert "
        "! video/x-raw,format=NV12 "
        "! v4l2h264enc "
        "extra-controls=\"encode,h264_profile=4,h264_level=10,video_bitrate=2000000\" "
        "! h264parse "
        "! mp4mux "
        "! filesink location=%2"
    ).arg(tempRawFile).arg(finalMp4File);

    qCDebug(lcGstGL) << "Direct MP4 encoding:" << mp4Command;
    int result = QProcess::execute("/bin/sh", QStringList() << "-c" << mp4Command);

    if (result != 0) {
        qCWarning(lcGstGL) << "Failed to encode MP4 video";
    } else {
        qCDebug(lcGstGL) << "MP4 recording completed:" << finalMp4File;
    }

    // Cleanup
    QFile::remove(tempRawFile);

    // Emit completion
    QMetaObject::invokeMethod(this, [this]() {
        Q_EMIT encodingCompleted();
        switchToPlaybackMode();
    }, Qt::QueuedConnection);
}

void GstTestGLSink::captureFrame()
{
    if (!m_cameraStream) {
        qCWarning(lcGstGL) << "Frame capture only available in camera mode";
        return;
    }
    qCDebug(lcGstGL) << "[Frame Capture] Capture frame requested";

    // Generate unique filename
    QString timestamp = QDateTime::currentDateTime().toString("yyyyMMdd_hhmmss");
    QString captureDir = "/usr/share/vlm-edge-studio/assets/images";

    // Ensure directory exists
    QDir dir;
    if (!dir.exists(captureDir)) {
        dir.mkpath(captureDir);
    }

    QString imagePath = QString("%1/capture_%2.jpg").arg(captureDir, timestamp);

    QMutexLocker locker(&m_frameBufferMutex);
    m_captureFrameRequested = true;
    m_captureFramePath = imagePath;
    qCDebug(lcGstGL) << "[Frame Capture] Will capture next frame to:" << imagePath;
}

#include "gsttestglsink.moc"
