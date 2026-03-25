/*
 * SPDX-License-Identifier: BSD-3-Clause
 * Copyright 2025 NXP
 *
 * @file gstqmlglsink.h
 * @brief GStreamer video sink header with inheritance support
 */

#ifndef GSTQMLGLSINK_H
#define GSTQMLGLSINK_H

#include <gst/gst.h>
#include <gst/video/video.h>

#include <QByteArray>
#include <QMutex>
#include <QOpenGLFunctions>
#include <QQuickFramebufferObject>

class QTimer;
class QOpenGLShaderProgram;
class QOpenGLBuffer;
class QOpenGLVertexArrayObject;

// Forward declarations
class GstQmlGLSinkBase;
class GstVideoRenderer;

/**
 * @brief Base class for GStreamer QML GL sinks
 */
class GstQmlGLSinkBase : public QQuickFramebufferObject {
  Q_OBJECT

 public:
  explicit GstQmlGLSinkBase(QQuickItem *parent = nullptr);
  virtual ~GstQmlGLSinkBase();

  // Public interface
  Q_INVOKABLE void startPipeline(const QString &uri = QString());
  Q_INVOKABLE void stopPipeline();

  // Thread-safe accessors for renderer
  GLuint getCurrentTextureId() const;
  void lockMutex();
  void unlockMutex();
  bool hasNewFrame() const;
  QByteArray getFrameData() const;
  int getFrameWidth() const;
  int getFrameHeight() const;
  void markFrameProcessed();

 protected:
  // Virtual methods for customization by derived classes
  virtual void connectSinkSignals(GstElement *pipeline) = 0;  // Pure virtual
  virtual void disconnectSinkSignals();  // Virtual with default impl
  virtual QList<GstElement *> getAllSinkElements(
      GstElement *pipeline);  // Get all relevant sinks
  virtual QString createPipelineString(const QString &uri) = 0;
  virtual GstElement *getSinkElement(GstElement *pipeline);
  virtual void configurePipeline(GstElement *pipeline);
  virtual bool processSample(GstSample *sample);

  // QQuickFramebufferObject interface
  Renderer *createRenderer() const override;

  // Store multiple sinks if needed
  QList<GstElement *> m_sinkElements;
  QList<gulong> m_signalHandlers;  // Store signal handler IDs for cleanup

 private Q_SLOTS:
  void handleTimeout();

 private:
  void initializeGStreamer();
  static GstFlowReturn newSample(GstElement *sink, gpointer user_data);

 protected:
  // GStreamer objects
  GstElement *m_pipeline;
  GstElement *m_glsink;

  // Qt objects
  QTimer *m_timer;

  // Synchronization and data
  mutable QMutex m_mutex;
  GLuint m_textureId;
  bool m_initialized;

  // Frame data (protected by mutex)
  int m_frameWidth;
  int m_frameHeight;
  QByteArray m_frameData;
  bool m_hasNewFrame;

  friend class GstVideoRenderer;
};

/**
 * @brief OpenGL renderer for video frames
 */
class GstVideoRenderer : public QQuickFramebufferObject::Renderer,
                         protected QOpenGLFunctions {
 public:
  explicit GstVideoRenderer(GstQmlGLSinkBase *sink);
  ~GstVideoRenderer();

 protected:
  void render() override;
  QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override;

 private:
  void initializeGL();
  void uploadFrameToTexture();

  GstQmlGLSinkBase *m_sink;
  GLuint m_textureId;
  bool m_initialized;

  QOpenGLShaderProgram *m_program;
  QOpenGLVertexArrayObject *m_vao;
  QOpenGLBuffer *m_vbo;

  int m_currentWidth;
  int m_currentHeight;
};

#endif  // GSTQMLGLSINK_H
