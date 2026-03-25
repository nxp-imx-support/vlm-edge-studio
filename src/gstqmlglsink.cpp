/*
 * SPDX-License-Identifier: BSD-3-Clause
 * Copyright 2025 NXP
 *
 * @file gstqmlglsink.cpp
 * @brief GStreamer video sink implementation for Qt QML integration with
 * inheritance support
 *
 * This file implements a base QQuickFramebufferObject that integrates
 * GStreamer video pipelines with Qt's OpenGL rendering system for QML,
 * with support for inheritance to customize pipeline creation.
 */

#include "gstqmlglsink.h"

#include <QDebug>
#include <QGuiApplication>
#include <QLoggingCategory>
#include <QOpenGLBuffer>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QOpenGLShaderProgram>
#include <QOpenGLVertexArrayObject>
#include <QQuickWindow>
#include <QTimer>

// Define the logging category (not declare - that should be in the header)
Q_LOGGING_CATEGORY(lcGstGL, "gst.gl")

// =============================================================================
// GstQmlGLSinkBase Implementation (Base Class)
// =============================================================================

/**
 * @brief Constructor for GstQmlGLSinkBase
 * @param parent Parent QQuickItem
 */
GstQmlGLSinkBase::GstQmlGLSinkBase(QQuickItem *parent)
    : QQuickFramebufferObject(parent),
      m_pipeline(nullptr),
      m_glsink(nullptr),
      m_timer(new QTimer(this)),
      m_textureId(0),
      m_initialized(false),
      m_frameWidth(0),
      m_frameHeight(0),
      m_hasNewFrame(false) {
  initializeGStreamer();

  connect(m_timer, &QTimer::timeout, this, &GstQmlGLSinkBase::handleTimeout);
  m_timer->start(33);  // ~30 FPS update

  setMirrorVertically(true);
}

/**
 * @brief Destructor - cleans up GStreamer resources
 */
GstQmlGLSinkBase::~GstQmlGLSinkBase() {
  qCDebug(lcGstGL) << "GstQmlGLSinkBase destructor";
  stopPipeline();
}

/**
 * @brief Initialize GStreamer library if not already initialized
 */
void GstQmlGLSinkBase::initializeGStreamer() {
  if (!gst_is_initialized()) {
    gst_init(nullptr, nullptr);
  }
}

/**
 * @brief Create the OpenGL renderer for this framebuffer object
 * @return Pointer to the created renderer
 */
QQuickFramebufferObject::Renderer *GstQmlGLSinkBase::createRenderer() const {
  return new GstVideoRenderer(const_cast<GstQmlGLSinkBase *>(this));
}

/**
 * @brief Get the current OpenGL texture ID (thread-safe)
 * @return Current texture ID
 */
GLuint GstQmlGLSinkBase::getCurrentTextureId() const {
  QMutexLocker locker(&m_mutex);
  return m_textureId;
}

/**
 * @brief Lock the internal mutex for thread-safe access
 */
void GstQmlGLSinkBase::lockMutex() { m_mutex.lock(); }

/**
 * @brief Unlock the internal mutex
 */
void GstQmlGLSinkBase::unlockMutex() { m_mutex.unlock(); }

/**
 * @brief Check if a new video frame is available (thread-safe)
 * @return True if new frame is available
 */
bool GstQmlGLSinkBase::hasNewFrame() const {
  QMutexLocker locker(&m_mutex);
  return m_hasNewFrame;
}

/**
 * @brief Get the current frame data (thread-safe)
 * @return Frame data as QByteArray
 */
QByteArray GstQmlGLSinkBase::getFrameData() const {
  QMutexLocker locker(&m_mutex);
  return m_frameData;
}

/**
 * @brief Get the current frame width (thread-safe)
 * @return Frame width in pixels
 */
int GstQmlGLSinkBase::getFrameWidth() const {
  QMutexLocker locker(&m_mutex);
  return m_frameWidth;
}

/**
 * @brief Get the current frame height (thread-safe)
 * @return Frame height in pixels
 */
int GstQmlGLSinkBase::getFrameHeight() const {
  QMutexLocker locker(&m_mutex);
  return m_frameHeight;
}

/**
 * @brief Mark the current frame as processed (thread-safe)
 */
void GstQmlGLSinkBase::markFrameProcessed() {
  QMutexLocker locker(&m_mutex);
  m_hasNewFrame = false;
}

/**
 * @brief Start the GStreamer video pipeline
 * @param uri Video source URI or configuration parameter
 */
void GstQmlGLSinkBase::startPipeline(const QString &uri) {
  stopPipeline();

  QString pipelineStr = createPipelineString(uri);
  if (pipelineStr.isEmpty()) {
    qWarning() << "Failed to create pipeline string";
    return;
  }

  GError *error = nullptr;
  m_pipeline = gst_parse_launch(pipelineStr.toUtf8().constData(), &error);

  if (error) {
    qWarning() << "GStreamer pipeline error:" << error->message;
    g_error_free(error);
    return;
  }

  // Configure the pipeline (virtual method for customization)
  configurePipeline(m_pipeline);

  // Connect sink-specific signals (implemented by derived classes)
  connectSinkSignals(m_pipeline);

  gst_element_set_state(m_pipeline, GST_STATE_PLAYING);
  m_initialized = true;
}

/**
 * @brief Stop and cleanup the GStreamer pipeline
 */
void GstQmlGLSinkBase::stopPipeline() {
  if (m_pipeline) {
    // Disconnect all signals first
    disconnectSinkSignals();

    gst_element_set_state(m_pipeline, GST_STATE_NULL);
    gst_object_unref(m_pipeline);
    m_pipeline = nullptr;
  }

  // Clean up sink references
  for (GstElement *sink : m_sinkElements) {
    if (sink) {
      gst_object_unref(sink);
    }
  }
  m_sinkElements.clear();
  m_signalHandlers.clear();

  m_initialized = false;

  QMutexLocker locker(&m_mutex);
  m_textureId = 0;
  m_hasNewFrame = false;
  m_frameData.clear();
}

void GstQmlGLSinkBase::disconnectSinkSignals() {
  // Disconnect all stored signal handlers
  for (int i = 0; i < m_sinkElements.size() && i < m_signalHandlers.size();
       ++i) {
    if (m_sinkElements[i] && m_signalHandlers[i] > 0) {
      g_signal_handler_disconnect(m_sinkElements[i], m_signalHandlers[i]);
    }
  }
  m_signalHandlers.clear();
}

QList<GstElement *> GstQmlGLSinkBase::getAllSinkElements(GstElement *pipeline) {
  // Default implementation - derived classes can override
  QList<GstElement *> sinks;
  GstElement *mainSink = getSinkElement(pipeline);
  if (mainSink) {
    sinks.append(mainSink);
  }
  return sinks;
}

/**
 * @brief Default implementation of getSinkElement - looks for "sink" element
 * @param pipeline The GStreamer pipeline
 * @return Pointer to sink element or nullptr
 */
GstElement *GstQmlGLSinkBase::getSinkElement(GstElement *pipeline) {
  return gst_bin_get_by_name(GST_BIN(pipeline), "sink");
}

/**
 * @brief Default implementation of configurePipeline - does nothing
 * @param pipeline The GStreamer pipeline to configure
 */
void GstQmlGLSinkBase::configurePipeline(GstElement *pipeline) {
  // Default implementation does nothing
  // Derived classes can override to add custom configuration
  Q_UNUSED(pipeline)
}

/**
 * @brief Process a new video sample - can be overridden for custom processing
 * @param sample The GStreamer sample
 * @return True if sample was processed successfully
 */
bool GstQmlGLSinkBase::processSample(GstSample *sample) {
  if (!sample) {
    return false;
  }

  GstBuffer *buffer = gst_sample_get_buffer(sample);
  GstCaps *caps = gst_sample_get_caps(sample);

  GstVideoInfo info;
  if (gst_video_info_from_caps(&info, caps)) {
    GstMapInfo map;
    if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
      QMutexLocker locker(&m_mutex);

      m_frameWidth = GST_VIDEO_INFO_WIDTH(&info);
      m_frameHeight = GST_VIDEO_INFO_HEIGHT(&info);
      m_frameData = QByteArray((const char *)map.data, map.size);
      m_hasNewFrame = true;

      gst_buffer_unmap(buffer, &map);

      QMetaObject::invokeMethod(this, "update", Qt::QueuedConnection);
      return true;
    }
  }

  return false;
}

/**
 * @brief GStreamer callback for new video samples
 * @param sink GStreamer appsink element
 * @param user_data Pointer to GstQmlGLSinkBase instance
 * @return GStreamer flow return code
 */
GstFlowReturn GstQmlGLSinkBase::newSample(GstElement *sink,
                                          gpointer user_data) {
  GstQmlGLSinkBase *self = static_cast<GstQmlGLSinkBase *>(user_data);

  GstSample *sample = nullptr;
  g_signal_emit_by_name(sink, "pull-sample", &sample);

  if (sample) {
    self->processSample(sample);
    gst_sample_unref(sample);
  }

  return GST_FLOW_OK;
}

/**
 * @brief Handle timer timeout for regular updates
 */
void GstQmlGLSinkBase::handleTimeout() {
  if (m_initialized) {
    update();
  }
}

// =============================================================================
// GstVideoRenderer Implementation (Shared Renderer)
// =============================================================================

/**
 * @brief Constructor for the OpenGL renderer
 * @param sink Pointer to the parent GstQmlGLSinkBase
 */
GstVideoRenderer::GstVideoRenderer(GstQmlGLSinkBase *sink)
    : m_sink(sink),
      m_textureId(0),
      m_initialized(false),
      m_program(nullptr),
      m_vao(nullptr),
      m_vbo(nullptr),
      m_currentWidth(0),
      m_currentHeight(0) {}

/**
 * @brief Destructor - cleanup OpenGL resources
 */
GstVideoRenderer::~GstVideoRenderer() {
  if (m_textureId) {
    glDeleteTextures(1, &m_textureId);
  }
  delete m_program;
  delete m_vao;
  delete m_vbo;
}

/**
 * @brief Main rendering function called by Qt
 */
void GstVideoRenderer::render() {
  if (!m_initialized) {
    initializeOpenGLFunctions();
    initializeGL();

    glGenTextures(1, &m_textureId);
    glBindTexture(GL_TEXTURE_2D, m_textureId);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, 0);

    m_initialized = true;
  }

  if (m_sink->hasNewFrame()) {
    uploadFrameToTexture();
    m_sink->markFrameProcessed();
  }

  glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  if (m_textureId != 0 && m_program && m_currentWidth > 0 &&
      m_currentHeight > 0) {
    m_program->bind();

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_textureId);
    m_program->setUniformValue("u_texture", 0);

    if (m_vao) {
      m_vao->bind();
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
      m_vao->release();
    } else {
      m_vbo->bind();
      m_program->enableAttributeArray(0);
      m_program->enableAttributeArray(1);
      m_program->setAttributeBuffer(0, GL_FLOAT, 0, 2, 4 * sizeof(float));
      m_program->setAttributeBuffer(1, GL_FLOAT, 2 * sizeof(float), 2,
                                    4 * sizeof(float));
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
      m_program->disableAttributeArray(0);
      m_program->disableAttributeArray(1);
      m_vbo->release();
    }

    m_program->release();
    glBindTexture(GL_TEXTURE_2D, 0);
  }
}

/**
 * @brief Upload new frame data to OpenGL texture
 */
void GstVideoRenderer::uploadFrameToTexture() {
  QByteArray frameData = m_sink->getFrameData();
  int width = m_sink->getFrameWidth();
  int height = m_sink->getFrameHeight();

  if (frameData.isEmpty() || width <= 0 || height <= 0) {
    return;
  }

  if (width != m_currentWidth || height != m_currentHeight) {
    m_currentWidth = width;
    m_currentHeight = height;
    qDebug() << "Updating texture size to:" << width << "x" << height;
  }

  glBindTexture(GL_TEXTURE_2D, m_textureId);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA,
               GL_UNSIGNED_BYTE, frameData.constData());
  glBindTexture(GL_TEXTURE_2D, 0);
}

/**
 * @brief Initialize OpenGL shaders and vertex data
 */
void GstVideoRenderer::initializeGL() {
  QString vertexShaderSource =
      "#version 320 es\n"
      "in vec2 a_position;\n"
      "in vec2 a_texCoord;\n"
      "out vec2 v_texCoord;\n"
      "void main()\n"
      "{\n"
      "    gl_Position = vec4(a_position, 0.0, 1.0);\n"
      "    v_texCoord = a_texCoord;\n"
      "}\n";

  QString fragmentShaderSource =
      "#version 320 es\n"
      "precision mediump float;\n"
      "in vec2 v_texCoord;\n"
      "uniform sampler2D u_texture;\n"
      "out vec4 fragColor;\n"
      "void main()\n"
      "{\n"
      "    fragColor = texture(u_texture, v_texCoord);\n"
      "}\n";

  m_program = new QOpenGLShaderProgram();

  if (!m_program->addShaderFromSourceCode(QOpenGLShader::Vertex,
                                          vertexShaderSource)) {
    qWarning() << "Failed to compile vertex shader:" << m_program->log();
    return;
  }

  if (!m_program->addShaderFromSourceCode(QOpenGLShader::Fragment,
                                          fragmentShaderSource)) {
    qWarning() << "Failed to compile fragment shader:" << m_program->log();
    return;
  }

  m_program->bindAttributeLocation("a_position", 0);
  m_program->bindAttributeLocation("a_texCoord", 1);

  if (!m_program->link()) {
    qWarning() << "Shader program failed to link:" << m_program->log();
    return;
  }

  qDebug() << "OpenGL ES 3.2 shaders compiled and linked successfully";

  float vertices[] = {
      // positions   // texture coords
      -1.0f, -1.0f, 0.0f, 1.0f,  // bottom left
      1.0f,  -1.0f, 1.0f, 1.0f,  // bottom right
      -1.0f, 1.0f,  0.0f, 0.0f,  // top left
      1.0f,  1.0f,  1.0f, 0.0f   // top right
  };

  m_vbo = new QOpenGLBuffer(QOpenGLBuffer::VertexBuffer);
  m_vbo->create();
  m_vbo->bind();
  m_vbo->allocate(vertices, sizeof(vertices));

  QOpenGLContext *ctx = QOpenGLContext::currentContext();
  if (ctx->hasExtension(QByteArrayLiteral("GL_OES_vertex_array_object"))) {
    m_vao = new QOpenGLVertexArrayObject();
    if (m_vao->create()) {
      m_vao->bind();

      m_program->enableAttributeArray(0);
      m_program->setAttributeBuffer(0, GL_FLOAT, 0, 2, 4 * sizeof(float));

      m_program->enableAttributeArray(1);
      m_program->setAttributeBuffer(1, GL_FLOAT, 2 * sizeof(float), 2,
                                    4 * sizeof(float));

      m_vao->release();
      qDebug() << "VAO created successfully";
    } else {
      delete m_vao;
      m_vao = nullptr;
      qDebug() << "VAO creation failed, using fallback method";
    }
  } else {
    qDebug() << "VAO not supported, using fallback method";
  }

  m_vbo->release();
}

/**
 * @brief Create framebuffer object for rendering
 * @param size Size of the framebuffer
 * @return Pointer to created framebuffer object
 */
QOpenGLFramebufferObject *GstVideoRenderer::createFramebufferObject(
    const QSize &size) {
  return new QOpenGLFramebufferObject(size);
}

#include "gstqmlglsink.moc"
