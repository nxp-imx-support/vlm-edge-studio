/*
 * SPDX-License-Identifier: BSD-3-Clause
 * Copyright 2025-2026 NXP
 *
 * @file gsttestglsink.h
 * @brief GStreamer test pattern video sink
 */

#ifndef GSTTESTGLSINK_H
#define GSTTESTGLSINK_H

#include <QString>
#include "cameradetector.h"
#include "gstqmlglsink.h"

/**
 * @brief Test pattern generator implementation
 */
class GstTestGLSink : public GstQmlGLSinkBase {
  Q_OBJECT
  Q_PROPERTY(bool animate READ animate WRITE setAnimate NOTIFY animateChanged)
  Q_PROPERTY(bool cameraStream READ cameraStream WRITE setCameraStream NOTIFY cameraStreamChanged FINAL)
  Q_PROPERTY(bool cameraConnected READ cameraConnected NOTIFY cameraConnectedChanged)
  Q_PROPERTY(bool isRecording READ isRecording NOTIFY isRecordingChanged)
  Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
  Q_PROPERTY(float ratio READ ratio WRITE setRatio NOTIFY ratioChanged FINAL)
  Q_PROPERTY(int patternType READ patternType WRITE setPatternType NOTIFY patternTypeChanged)
  Q_PROPERTY(QString videoSource READ videoSource WRITE setVideoSource NOTIFY videoSourceChanged FINAL)
  QML_ELEMENT

 public:
  explicit GstTestGLSink(QQuickItem *parent = nullptr);

  int patternType() const { return m_patternType; }
  bool animate() const { return m_animate; }

  bool isRecording() const;
  void setIsRecording(bool recording);

  QString videoSource() const;
  bool cameraStream() const;
  bool cameraConnected() const;
  bool playing() const;
  float ratio() const;

  Q_INVOKABLE void captureFrame();

 public Q_SLOTS:
  void setPatternType(int type);
  void setAnimate(bool animate);
  void setVideoSource(const QString &path);
  void setCameraStream(bool);
  void setCameraConnected(bool);
  void setPlaying(bool);
  void setRatio(float);

  void startRecording();
  void stopRecording();
  void switchToPlaybackMode();

 Q_SIGNALS:
  void patternTypeChanged();
  void animateChanged();

  void videoSourceChanged();
  void cameraStreamChanged();
  void cameraConnectedChanged();
  void playingChanged();
  void ratioChanged();
  void isRecordingChanged();

  // Extra signals
  void newFrame();
  void recordingFinished(const QString &videoPath);

  void recordingStarted();
  void recordingProgress(int current, int total);
  void videoModeActivated();
  void encodingCompleted();

  void frameCaptured(const QString &imagePath);

 protected:
  QString createPipelineString(const QString &uri) override;
  void connectSinkSignals(GstElement *pipeline) override;

 private:
  static GstFlowReturn newSampleCallback(GstElement *sink, gpointer user_data);
  static GstFlowReturn recordSampleCallback(GstElement *sink, gpointer user_data);
  static void eosCallback(GstElement *sink, gpointer user_data);
  void sendEOSToRecordingBranch();
  void encodeFramesToMP4();

  int m_patternType;  // 0=SMPTE, 1=snow, 2=black, 3=white, etc.
  bool m_animate;

   // Members
  bool m_isRecording;
  bool m_cameraStream;
  bool m_captureFrameRequested;

  int m_recordedFrames = 0;
  QTimer* m_recordingTimer = nullptr;

  QString m_videoPath;

  bool m_cameraConnected;
  bool m_playing;
  float m_ratio;
  bool m_isInitialized;
  bool m_playerHasFrame;
  int m_width;
  int m_height;

    // Frame buffer for recording
    QList<QByteArray> m_recordedFrameBuffer;
    QMutex m_frameBufferMutex;
    static const int MAX_RECORDING_FRAMES = 240;

    QString m_cameraDevice;
    CameraDetector* m_cameraDetector;
    QString m_recordedVideoPath;
    QString m_captureFramePath;
};

#endif  // GSTTESTGLSINK_H
